import 'package:attendus/Services/public_profile_service.dart';
import 'package:attendus/Services/notification_preferences_service.dart';
import 'package:attendus/Services/pending_auth_intent_service.dart';
import 'package:attendus/Services/push_token_lifecycle.dart';
import 'package:attendus/Services/push_notification_intent.dart';
import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:attendus/main.dart' show appNavigatorKey;
import 'package:attendus/widgets/deferred_shared_event_screen.dart';
import 'package:attendus/widgets/deferred_shared_community_screen.dart';
import 'package:attendus/widgets/deferred_conversation_screen.dart';
import 'package:attendus/widgets/deferred_screen_loader.dart';
import 'package:attendus/screens/Home/dashboard_screen.dart'
    deferred as dashboard;
import 'package:flutter/material.dart' show MaterialPageRoute, WidgetsBinding;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:attendus/firebase_options.dart';
import 'package:firebase_messaging/firebase_messaging.dart' as fcm;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
// import 'dart:typed_data' show Int64List; // Unused; Int64List available via foundation

import 'package:attendus/models/message_model.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/models/notification_model.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class NotificationPage {
  final List<NotificationModel> items;
  final DocumentSnapshot? lastDoc;
  NotificationPage({required this.items, required this.lastDoc});
}

class FirebaseMessagingHelper {
  static final FirebaseMessagingHelper _instance =
      FirebaseMessagingHelper._internal();
  static bool _backgroundHandlerRegistered = false;
  factory FirebaseMessagingHelper() => _instance;
  FirebaseMessagingHelper._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final fcm.FirebaseMessaging _messaging = fcm.FirebaseMessaging.instance;
  FlutterLocalNotificationsPlugin? _localNotifications;
  late final NotificationPreferencesService _preferences =
      NotificationPreferencesService(
        currentUid: () => _auth.currentUser?.uid,
        load: (uid) async => (await NotificationPreferencesStore.read(
          _firestore,
          uid,
        )).effectiveData,
        save: (uid, patch) => NotificationPreferencesStore.save(
          _firestore,
          uid,
          patch,
          currentUid: () => _auth.currentUser?.uid,
        ),
      );
  UserNotificationSettings? get _settings => _preferences.cached;
  EventModel? _pendingFeedbackEvent;
  bool _listenersInitialized = false;
  StreamSubscription<User?>? _pushAuthSubscription;
  StreamSubscription<List<ConnectivityResult>>? _pushNetworkSubscription;
  static const _pushStateKey = 'push_installation_v1';

  String? get _pushUid {
    final user = _auth.currentUser;
    return user == null || user.isAnonymous ? null : user.uid;
  }

  late final PushTokenLifecycle _pushLifecycle = PushTokenLifecycle(
    currentUid: () => _pushUid,
    readState: () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString(_pushStateKey);
      if (raw == null) return <String, dynamic>{};
      try {
        return Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {
        return <String, dynamic>{};
      }
    },
    writeState: (state) async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(_pushStateKey, jsonEncode(state))) {
        throw StateError('Could not persist notification session');
      }
    },
    newInstallationId: () => const Uuid().v4(),
    acquireToken: () async {
      final settings = await _messaging.getNotificationSettings();
      if (settings.authorizationStatus != fcm.AuthorizationStatus.authorized &&
          settings.authorizationStatus != fcm.AuthorizationStatus.provisional) {
        await _messaging.setAutoInitEnabled(false);
        return null;
      }
      await _messaging.setAutoInitEnabled(true);
      const publicKey = String.fromEnvironment('ATTENDUS_WEB_PUSH_VAPID_KEY');
      return _messaging.getToken(
        vapidKey: kIsWeb && publicKey.isNotEmpty ? publicKey : null,
      );
    },
    deleteToken: () async {
      await _messaging.setAutoInitEnabled(false);
      await _messaging.deleteToken();
    },
    register: (intent) => _pushRequest('registerPushTokenV1', intent),
    revoke: (intent) => _pushRequest('revokePushTokenV1', intent),
    clearNotifications: () async {
      if (!kIsWeb) {
        await (_localNotifications ?? FlutterLocalNotificationsPlugin())
            .cancelAll();
      }
    },
    onError: (error) =>
        Logger.warning('Notification session cleanup pending: $error'),
  );

  Future<void> _pushRequest(String name, Map<String, dynamic> intent) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      if (_pushUid != intent['expectedUid']) {
        throw StateError('Notification account changed');
      }
      try {
        await FirebaseFunctions.instance.httpsCallable(name).call(intent);
        return;
      } on FirebaseFunctionsException catch (error) {
        final details = error.details;
        if (details is Map &&
            details['code'] == 'installation-reset-required') {
          throw PushInstallationReset();
        }
        if (attempt != 0 ||
            !const {'unavailable', 'deadline-exceeded'}.contains(error.code)) {
          rethrow;
        }
        // The same generation is replayed; an obsolete intent is never promoted.
      }
    }
  }

  Future<void> clearForSignOut() async {
    _pushIntents.invalidate();
    _pendingFeedbackEvent = null;
    await _pushLifecycle.clearForSignOut();
  }

  Future<void> requestEventReminders() async {
    await requestPermissions();
  }

  // Initialize messaging with optimizations
  Future<void> initialize() async {
    try {
      _pushAuthSubscription ??= _auth.authStateChanges().listen((_) {
        _pushIntents.invalidate();
        _pendingFeedbackEvent = null;
        unawaited(
          _pushLifecycle.synchronize().catchError((Object error) {
            Logger.warning('Notification session registration pending: $error');
          }),
        );
        if (_pushUid != null) {
          unawaited(
            _loadNotificationSettings().catchError((Object error) {
              Logger.warning('Notification preferences unavailable: $error');
            }),
          );
        }
      });
      _pushNetworkSubscription ??= Connectivity().onConnectivityChanged.listen((
        results,
      ) {
        if (results.any((value) => value != ConnectivityResult.none)) {
          unawaited(
            _pushLifecycle.synchronize().catchError((Object error) {
              Logger.warning('Notification session retry pending: $error');
            }),
          );
        }
      });
      unawaited(
        _pushLifecycle.synchronize().catchError((Object error) {
          Logger.warning('Notification session registration pending: $error');
        }),
      );

      // Taps and auth changes remain relevant when offline or when permission
      // was revoked after delivery. Only token acquisition requires permission.
      if (_listenersInitialized) return;
      _listenersInitialized = true;
      if (!kIsWeb) {
        unawaited(
          _initializeLocalNotifications().catchError((Object error) {
            Logger.warning('Local notifications init failed: $error');
          }),
        );
      }
      // Listen for token refresh
      _messaging.onTokenRefresh.listen((token) {
        _pushLifecycle.tokenRefreshed(token).catchError((e) {
          Logger.warning('Failed to save refreshed token: $e');
        });
      });

      // Handle background messages (mobile only)
      if (!kIsWeb && !_backgroundHandlerRegistered) {
        fcm.FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler,
        );
        _backgroundHandlerRegistered = true;
      }

      // Handle foreground messages
      fcm.FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle notification taps (mobile only)
      if (!kIsWeb) {
        fcm.FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
        unawaited(
          _messaging
              .getInitialMessage()
              .then((message) {
                if (message != null) _handleNotificationTap(message);
              })
              .catchError((Object error) {
                Logger.warning('Initial notification unavailable: $error');
              }),
        );
      }

      // Load user settings async
      _loadNotificationSettings().catchError((e) {
        Logger.warning('Failed to load notification settings: $e');
      });
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Error initializing Firebase Messaging: $e', e);
      }
    }
  }

  Future<void> _initializeLocalNotifications() async {
    _localNotifications = FlutterLocalNotificationsPlugin();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    await _localNotifications!.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  Future<void> _loadNotificationSettings() async {
    await _preferences.read();
  }

  Future<void> _saveNotificationSettings(
    UserNotificationSettings settings, {
    UserNotificationSettings? baseline,
  }) => _preferences.write(settings, baseline: baseline);

  late final PushIntentCoordinator _pushIntents = PushIntentCoordinator(
    currentUid: () => _pushUid,
    remember: (intent) => switch (intent.destination) {
      PushDestination.event => PendingAuthIntentService.rememberSharedEvent(
        intent.id,
      ),
      PushDestination.community => PendingAuthIntentService.rememberCommunity(
        intent.id,
      ),
      PushDestination.conversation =>
        PendingAuthIntentService.rememberConversation(intent.id),
      PushDestination.discovery => PendingAuthIntentService.rememberHome(),
    },
    present: (intent, stillCurrent) {
      final result = Completer<bool>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!stillCurrent()) {
          result.complete(false);
          return;
        }
        final navigator = appNavigatorKey.currentState;
        if (navigator == null) {
          result.complete(false);
          return;
        }
        final screen = switch (intent.destination) {
          PushDestination.event => DeferredSharedEventScreen(
            eventId: intent.id,
          ),
          PushDestination.community => DeferredSharedCommunityScreen(
            organizationId: intent.id,
          ),
          PushDestination.conversation => DeferredConversationScreen(
            conversationId: intent.id,
          ),
          PushDestination.discovery => DeferredScreenLoader(
            loadLibrary: dashboard.loadLibrary,
            builder: () => dashboard.DashboardScreen(restoreSavedTab: false),
            recoveryKey: 'dashboard',
            loadingLabel: 'Loading Discover',
          ),
        };
        navigator.push(MaterialPageRoute<void>(builder: (_) => screen));
        result.complete(true);
      });
      WidgetsBinding.instance.ensureVisualUpdate();
      return result.future;
    },
  );

  void _handleForegroundMessage(fcm.RemoteMessage message) {
    final uid = _pushUid;
    if (uid == null || !PushNotificationIntent.belongsTo(message.data, uid)) {
      return;
    }
    if (_settings?.generalNotifications == true) {
      unawaited(
        _showLocalNotification(message).catchError((Object error) {
          Logger.warning('Could not display notification: $error');
        }),
      );
    }
  }

  void _handleNotificationTap(fcm.RemoteMessage message) {
    handleNotificationPayload(message.data);
  }

  void _onNotificationTapped(NotificationResponse response) {
    handleLocalNotificationTap(response);
  }

  void handleLocalNotificationTap(NotificationResponse response) {
    if (response.payload == null) return;
    try {
      final decoded = jsonDecode(response.payload!);
      if (decoded is Map) {
        handleNotificationPayload(Map<String, dynamic>.from(decoded));
      }
    } catch (error) {
      Logger.warning('Ignoring invalid notification payload: $error');
    }
  }

  void handleNotificationPayload(Map<String, dynamic> data) {
    unawaited(
      _pushIntents.handle(data).catchError((Object error) {
        Logger.warning('Could not open notification destination: $error');
      }),
    );
  }

  Future<void> _showLocalNotification(fcm.RemoteMessage message) async {
    if (_localNotifications == null) return;

    final bool playSound = _settings?.soundEnabled ?? true;
    final bool enableVibration = _settings?.vibrationEnabled ?? true;

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'attendus_channel',
          'Attendus Notifications',
          channelDescription: 'Notifications for Attendus events and updates',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
          playSound: playSound,
          enableVibration: enableVibration,
          vibrationPattern: enableVibration
              ? Int64List.fromList([0, 250, 150, 250])
              : null,
        );

    final DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: playSound,
        );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    await _localNotifications!.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: message.notification?.title ?? 'New Notification',
      body: message.notification?.body ?? '',
      notificationDetails: platformChannelSpecifics,
      payload: json.encode(message.data),
    );
  }

  // Message writes are authenticated, atomic and idempotent on the server.
  Future<String> sendMessage({
    String? receiverId,
    required String content,
    String messageType = 'text',
    String? mediaUrl,
    String? fileName,
    String? conversationId,
    String? requestId,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('Sign in to send messages');
    }
    if (messageType != 'text') {
      throw UnsupportedError('Only text messages are supported');
    }
    final id =
        conversationId ??
        (receiverId == null
            ? null
            : await getConversationId(user.uid, receiverId));
    if (id == null) throw ArgumentError('A conversation is required');
    final result = await FirebaseFunctions.instance
        .httpsCallable('sendConversationMessageV2')
        .call({
          'conversationId': id,
          'requestId': requestId ?? _firestore.collection('Messages').doc().id,
          'content': content,
        });
    return result.data['messageId'] as String;
  }

  Future<CustomerModel> _getUserInfo(String userId) async {
    final profiles = await PublicProfileService().getByIds([userId]);
    if (profiles.isEmpty) throw StateError('This profile is unavailable.');
    return profiles.first;
  }

  Stream<List<ConversationModel>> getUserConversations(String userId) {
    return _firestore
        .collection('Conversations')
        .where('participantIds', arrayContains: userId)
        .orderBy('lastMessageTime', descending: true)
        .snapshots(includeMetadataChanges: true)
        .where(
          (snapshot) =>
              !snapshot.metadata.isFromCache || snapshot.docs.isNotEmpty,
        )
        .map(
          (snapshot) => snapshot.docs
              .where((doc) => doc.data()['redirectConversationId'] == null)
              .map(
                (doc) =>
                    ConversationModel.fromFirestore(doc, currentUserId: userId),
              )
              .toList(),
        );
  }

  Future<ConversationModel?> createConversation({
    required String userId,
    required String otherUserId,
    required Map<String, dynamic> otherUserInfo,
  }) async {
    final id = await getConversationId(userId, otherUserId);
    if (id == null) return null;
    final doc = await _firestore.collection('Conversations').doc(id).get();
    return ConversationModel.fromFirestore(doc, currentUserId: userId);
  }

  Stream<List<MessageModel>> getMessages(String conversationId) {
    return _firestore
        .collection('Messages')
        .where('conversationId', isEqualTo: conversationId)
        .orderBy('timestamp')
        .snapshots(includeMetadataChanges: true)
        .where(
          (snapshot) =>
              !snapshot.metadata.isFromCache || snapshot.docs.isNotEmpty,
        )
        .map(
          (snapshot) => snapshot.docs.map(MessageModel.fromFirestore).toList(),
        );
  }

  Future<void> markMessagesAsRead(
    String conversationId,
    String currentUserId, {
    required String lastMessageId,
  }) async {
    if (_auth.currentUser?.uid != currentUserId) return;
    await FirebaseFunctions.instance
        .httpsCallable('markConversationReadV2')
        .call({
          'conversationId': conversationId,
          'lastMessageId': lastMessageId,
        });
  }

  // Create a group conversation
  Future<ConversationModel?> createGroupConversation({
    String? groupName,
    String? groupAvatarUrl,
    required List<String> participantIds,
  }) async {
    try {
      if (participantIds.length < 3) {
        throw Exception('Group must have at least 3 participants');
      }
      final sorted = [...participantIds]..sort();
      final docRef = _firestore.collection('Conversations').doc();

      // Build participantInfo map and collect names to generate default name
      final infoEntries = <String, Map<String, dynamic>>{};
      final names = <String>[];
      for (final uid in sorted) {
        try {
          final u = await _getUserInfo(uid);
          infoEntries[uid] = {
            'name': u.name,
            'profilePictureUrl': u.profilePictureUrl,
            'username': u.username,
          };
          if (u.name.isNotEmpty) names.add(u.name);
        } catch (_) {}
      }

      // Auto-generate a group name if not provided
      String finalName = (groupName ?? '').trim();
      if (finalName.isEmpty) {
        if (names.isNotEmpty) {
          finalName = names.join(', ');
        } else {
          finalName = 'Group';
        }
      }

      await docRef.set({
        'isGroup': true,
        'groupName': finalName,
        'groupAvatarUrl': groupAvatarUrl,
        'participantIds': sorted,
        'participantInfo': infoEntries,
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'messagingVersion': 2,
        'sequence': 0,
        'receivedTotals': <String, int>{},
        'readTotals': <String, int>{},
        'readSequences': <String, int>{},
        'unreadCounts': <String, int>{},
      });

      return ConversationModel(
        id: docRef.id,
        participantIds: sorted,
        lastMessage: '',
        lastMessageTime: DateTime.now(),
        unreadCount: 0,
        participantInfo: infoEntries,
        isGroup: true,
        groupName: finalName,
        groupAvatarUrl: groupAvatarUrl,
      );
    } catch (e) {
      if (kDebugMode) Logger.error('❌ Error creating group: $e');
      return null;
    }
  }

  Future<List<CustomerModel>> searchUsers(
    String query,
    String currentUserId,
  ) async {
    if (_auth.currentUser?.uid != currentUserId) {
      throw StateError('Your account changed.');
    }
    final users = await PublicProfileService().search(query, limit: 50);
    if (_auth.currentUser?.uid != currentUserId) {
      throw StateError('Your account changed.');
    }
    return users.where((user) => user.uid != currentUserId).toList();
  }

  Future<String?> getConversationId(String userId1, String userId2) async {
    if (_auth.currentUser?.uid != userId1) {
      throw StateError('Sign in to start a conversation');
    }
    final result = await FirebaseFunctions.instance
        .httpsCallable('getOrCreateDirectConversationV2')
        .call({'otherUserId': userId2});
    return result.data['conversationId'] as String;
  }

  // Public methods
  Future<void> updateNotificationSettings(
    UserNotificationSettings settings, {
    UserNotificationSettings? baseline,
  }) async {
    await _saveNotificationSettings(settings, baseline: baseline);
  }

  Future<UserNotificationSettings> getUserNotificationSettings() async {
    await _loadNotificationSettings();
    return _settings ?? UserNotificationSettings();
  }

  UserNotificationSettings? get settings => _settings;
  EventModel? get pendingFeedbackEvent => _pendingFeedbackEvent;

  void clearPendingFeedbackEvent() {
    _pendingFeedbackEvent = null;
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('notifications')
            .doc(notificationId)
            .update({'isRead': true});
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Error marking notification as read: $e');
      }
    }
  }

  Future<void> deleteNotification(String notificationId) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('notifications')
            .doc(notificationId)
            .delete();
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Error deleting notification: $e');
      }
    }
  }

  // Create notification in user's collection (client-side)
  Future<void> createLocalNotification({
    required String title,
    required String body,
    required String type,
    String? eventId,
    String? eventTitle,
    Map<String, dynamic>? data,
    String? userId, // Optional, defaults to current user
  }) async {
    try {
      final targetUserId = userId ?? _auth.currentUser?.uid;
      if (targetUserId == null) {
        if (kDebugMode) {
          Logger.error('❌ Cannot create notification: No user ID provided');
        }
        return;
      }

      await _firestore
          .collection('users')
          .doc(targetUserId)
          .collection('notifications')
          .add({
            'title': title,
            'body': body,
            'type': type,
            'eventId': eventId,
            'eventTitle': eventTitle,
            'data': data,
            'createdAt': FieldValue.serverTimestamp(),
            'isRead': false,
          });

      if (kDebugMode) {
        Logger.error('✅ Created local notification: $title');
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Error creating local notification: $e');
      }
    }
  }

  Stream<List<NotificationModel>> getUserNotifications() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .snapshots(includeMetadataChanges: true)
        .where(
          (snapshot) =>
              !snapshot.metadata.isFromCache || snapshot.docs.isNotEmpty,
        )
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => NotificationModel.fromFirestore(doc))
              .toList(),
        );
  }

  // Paged fetch for notifications (infinite scroll)
  Future<NotificationPage> fetchUserNotificationsPage({
    DocumentSnapshot? startAfter,
    int pageSize = 20,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      return NotificationPage(items: const [], lastDoc: null);
    }

    Query<Map<String, dynamic>> query = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(pageSize);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snap = await query.get();
    final items = snap.docs
        .map((d) => NotificationModel.fromFirestore(d))
        .toList();
    final last = snap.docs.isNotEmpty ? snap.docs.last : null;
    return NotificationPage(items: items, lastDoc: last);
  }

  // Add a notification directly to the user's inbox (client-side helper)
  Future<void> addNotificationToInbox({
    required String title,
    required String body,
    String type = 'general',
    String? eventId,
    String? eventTitle,
    Map<String, dynamic>? data,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .add({
            'title': title,
            'body': body,
            'type': type,
            'eventId': eventId,
            'eventTitle': eventTitle,
            'createdAt': FieldValue.serverTimestamp(),
            'isRead': false,
            'data': data ?? <String, dynamic>{},
          });
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Error adding notification to inbox: $e');
      }
    }
  }

  // Bulk mark all notifications as read
  Future<void> markAllNotificationsAsRead() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      final query = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .where('isRead', isEqualTo: false)
          .get();
      final batch = _firestore.batch();
      for (final doc in query.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Error marking all notifications as read: $e');
      }
    }
  }

  // Bulk clear all notifications
  Future<void> clearAllNotifications() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      final query = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .get();
      final batch = _firestore.batch();
      for (final doc in query.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Error clearing notifications: $e');
      }
    }
  }

  // Expose permission request to allow manual trigger from Settings UI
  Future<fcm.NotificationSettings> requestPermissions() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    if (settings.authorizationStatus == fcm.AuthorizationStatus.authorized ||
        settings.authorizationStatus == fcm.AuthorizationStatus.provisional) {
      // Settings can grant permission after startup left token auto-init off.
      // Listener setup is immediate; the lifecycle bounds registration itself.
      await initialize();
    }
    return settings;
  }

  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      if (kDebugMode) {
        Logger.error('✅ Subscribed to topic: $topic');
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Error subscribing to topic: $e');
      }
    }
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      if (kDebugMode) {
        Logger.error('✅ Unsubscribed from topic: $topic');
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Error unsubscribing from topic: $e');
      }
    }
  }
}

// Retained by release tree shaking and initialized in the background isolate.
// The server owns inbox records; a device must never copy an old account's
// payload into whichever account happens to be current when it wakes up.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(
  fcm.RemoteMessage message,
) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null ||
        user.isAnonymous ||
        !PushNotificationIntent.belongsTo(message.data, user.uid)) {
      return;
    }
  } catch (error) {
    Logger.warning('Background notification initialization failed: $error');
  }
}
