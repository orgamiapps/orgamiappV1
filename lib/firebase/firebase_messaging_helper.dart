import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart' as fcm;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

import 'package:orgami/models/message_model.dart';
import 'package:orgami/models/customer_model.dart';
import 'package:orgami/models/notification_model.dart';
import 'package:orgami/models/event_model.dart';
import 'package:orgami/Utils/logger.dart';

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
  UserNotificationSettings? _settings;
  EventModel? _pendingFeedbackEvent;

  // Initialize messaging
  Future<void> initialize() async {
    try {
      // Request permission
      fcm.NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (kDebugMode) {
        if (settings.authorizationStatus ==
            fcm.AuthorizationStatus.authorized) {
          Logger.success('✅ Notification permissions granted');
        } else {
          Logger.warning('❌ Notification permissions denied');
        }
      }

      // Initialize local notifications (mobile platforms)
      if (!kIsWeb) {
        await _initializeLocalNotifications();
      }

      // Enable auto-init and get FCM token
      await _messaging.setAutoInitEnabled(true);
      String? fcmToken;
      if (kIsWeb) {
        // Web requires a VAPID key and service worker
        fcmToken = await _messaging.getToken(
          vapidKey: 'BCFlVkRk4wUzL3pNaP7bVYqg8uH3M2vYsmYcB5dOSdpnqjWcW1O9xv5v3kHcQ8bYl1o3tB6Qx4HjG3C2D5E6F7G8',
        );
      } else {
        fcmToken = await _messaging.getToken();
      }
      if (fcmToken != null) {
        await _saveTokenToFirestore(fcmToken);
      }

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((token) {
        _saveTokenToFirestore(token);
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
        fcm.FirebaseMessaging.onMessageOpenedApp
            .listen(_handleNotificationTap);
      }

      // Load user settings
      await _loadNotificationSettings();
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
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    await _localNotifications!.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  Future<void> _saveTokenToFirestore(String token) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).set({
          'fcmToken': token,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (kDebugMode) {
          Logger.success('✅ FCM token saved to Firestore');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Error saving FCM token: $e', e);
      }
    }
  }

  Future<void> _loadNotificationSettings() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('settings')
            .doc('notifications')
            .get();

        if (doc.exists) {
          _settings = UserNotificationSettings.fromMap(doc.data()!);
        } else {
          _settings = UserNotificationSettings();
          await _saveNotificationSettings(_settings!);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Error loading notification settings: $e');
      }
      _settings = UserNotificationSettings();
    }
  }

  Future<void> _saveNotificationSettings(
    UserNotificationSettings settings,
  ) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('settings')
            .doc('notifications')
            .set(settings.toMap());
        _settings = settings;
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Error saving notification settings: $e');
      }
    }
  }

  void _handleForegroundMessage(fcm.RemoteMessage message) {
    if (kDebugMode) {
      Logger.error(
        '📱 Received foreground message: ${message.notification?.title}',
      );
    }

    if (_settings?.generalNotifications == true) {
      _showLocalNotification(message);
    }
  }

  void _handleNotificationTap(fcm.RemoteMessage message) {
    if (kDebugMode) {
      Logger.error('👆 Notification tapped: ${message.data}');
    }
    // Handle navigation based on message data
    _handleNotificationNavigation(message.data);
  }

  void _onNotificationTapped(NotificationResponse response) {
    if (kDebugMode) {
      Logger.error('👆 Local notification tapped: ${response.payload}');
    }
    if (response.payload != null) {
      final data = json.decode(response.payload!);
      _handleNotificationNavigation(data);
    }
  }

  void _handleNotificationNavigation(Map<String, dynamic> data) {
    // Handle navigation based on notification type
    final type = data['type'];
    final eventId = data['eventId'];

    switch (type) {
      case 'event_reminder':
        // Navigate to event details
        break;
      case 'new_event':
        // Navigate to events list
        break;
      case 'ticket_update':
        // Navigate to tickets
        break;
      case 'event_feedback':
        // Navigate to feedback screen
        _navigateToFeedbackScreen(eventId);
        break;
      default:
        // Navigate to notifications screen
        break;
    }
  }

  void _navigateToFeedbackScreen(String? eventId) {
    if (eventId == null) return;

    // Get the event model and navigate to feedback screen
    FirebaseFirestore.instance.collection('Events').doc(eventId).get().then((
      doc,
    ) {
      if (doc.exists) {
        final eventModel = EventModel.fromJson(doc);

        // Navigate to feedback screen
        // Note: This requires a global navigator key or context
        // For now, we'll store the event data to be used when the app opens
        _pendingFeedbackEvent = eventModel;
      }
    });
  }

  Future<void> _showLocalNotification(fcm.RemoteMessage message) async {
    if (_localNotifications == null) return;

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'orgami_channel',
          'Orgami Notifications',
          channelDescription: 'Notifications for Orgami events and updates',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
        );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    await _localNotifications!.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      message.notification?.title ?? 'New Notification',
      message.notification?.body ?? '',
      platformChannelSpecifics,
      payload: json.encode(message.data),
    );
  }

  // Messaging methods
  Future<String> sendMessage({
    String? receiverId, // for 1-1
    required String content,
    String messageType = 'text',
    String? mediaUrl,
    String? fileName,
    String? conversationId, // for group or existing thread
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      if (kDebugMode) {
        Logger.error(
          '📤 Creating message data for conv: ${conversationId ?? 'n/a'} receiver: ${receiverId ?? 'n/a'}',
        );
      }
      // Determine conversationId
      String resolvedConversationId =
          conversationId ??
          (receiverId != null ? _getConversationId(user.uid, receiverId) : '');

      if (resolvedConversationId.isEmpty) {
        throw Exception('conversationId or receiverId required');
      }

      final messageData = {
        'senderId': user.uid,
        'receiverId': receiverId,
        'conversationId': resolvedConversationId,
        'content': content,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'messageType': messageType,
        'mediaUrl': mediaUrl,
        'fileName': fileName,
      };

      if (kDebugMode) {
        Logger.error('📤 Adding message to Firestore...');
      }
      final messageRef = await _firestore
          .collection('Messages')
          .add(messageData);

      if (kDebugMode) {
        Logger.error('✅ Message added with ID: ${messageRef.id}');
      }

      // Update conversation metadata
      await _updateConversation(
        conversationId: resolvedConversationId,
        lastMessage: content,
        lastMessageTime: DateTime.now(),
        lastMessageSenderId: user.uid,
      );

      // Ensure conversation exists (1-1 only)
      if (receiverId != null) {
        await _ensureConversationExists(user.uid, receiverId);
      }

      // Send push notification to receiver
      if (receiverId != null) {
        await _sendPushNotification(receiverId, content, user.uid);
      } else {
        // TODO: Broadcast to group members (Cloud Function recommended)
      }

      return messageRef.id;
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Error sending message: $e');
      }
      rethrow;
    }
  }

  Future<void> _ensureConversationExists(String userId1, String userId2) async {
    try {
      final conversationId = _getConversationId(userId1, userId2);
      final conversationDoc = await _firestore
          .collection('Conversations')
          .doc(conversationId)
          .get();

      if (!conversationDoc.exists) {
        if (kDebugMode) {
          Logger.error('🔧 Creating conversation $conversationId');
        }
        await createConversation(
          userId: userId1,
          otherUserId: userId2,
          otherUserInfo: {
            'name': 'User',
            'profilePictureUrl': null,
            'username': 'user',
          },
        );
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Error ensuring conversation exists: $e');
      }
    }
  }

  Future<void> _sendPushNotification(
    String receiverId,
    String content,
    String senderId,
  ) async {
    try {
      // Get receiver's FCM token
      final receiverDoc = await _firestore
          .collection('users')
          .doc(receiverId)
          .get();
      if (!receiverDoc.exists) return;

      final receiverData = receiverDoc.data() as Map<String, dynamic>;
      final fcmToken = receiverData['fcmToken'] as String?;

      if (fcmToken == null) return;

      // Get sender's info
      final senderDoc = await _firestore
          .collection('Customers')
          .doc(senderId)
          .get();
      if (!senderDoc.exists) return;

      final senderData = senderDoc.data() as Map<String, dynamic>;
      final senderName = senderData['name'] as String? ?? 'Someone';

      // Send notification via Cloud Functions (you'll need to implement this)
      // For now, we'll just log it
      if (kDebugMode) {
        Logger.error(
          '📱 Sending push notification to $receiverId: $content from $senderName',
        );
      }

      // TODO: Implement Cloud Function call to send push notification
      // await _firestore.collection('notifications').add({
      //   'receiverId': receiverId,
      //   'senderId': senderId,
      //   'content': content,
      //   'senderName': senderName,
      //   'fcmToken': fcmToken,
      //   'timestamp': FieldValue.serverTimestamp(),
      // });
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Error sending push notification: $e');
      }
    }
  }

  Future<void> _updateConversation({
    required String conversationId,
    required String lastMessage,
    required DateTime lastMessageTime,
    String? lastMessageSenderId,
  }) async {
    try {
      final conversationRef = _firestore
          .collection('Conversations')
          .doc(conversationId);

      final conversationData = {
        'lastMessage': lastMessage,
        'lastMessageTime': lastMessageTime,
        'lastMessageSenderId': lastMessageSenderId,
      };

      if (kDebugMode) {
        Logger.error(
          '💬 Updating conversation $conversationId with message: $lastMessage',
        );
      }
      await conversationRef.set(conversationData, SetOptions(merge: true));
      if (kDebugMode) {
        Logger.error('✅ Conversation updated successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Error updating conversation: $e');
      }
    }
  }

  String _getConversationId(String userId1, String userId2) {
    final sortedIds = [userId1, userId2]..sort();
    return '${sortedIds[0]}_${sortedIds[1]}';
  }

  Future<CustomerModel> _getUserInfo(String userId) async {
    try {
      final userDoc = await _firestore
          .collection('Customers')
          .doc(userId)
          .get();
      return CustomerModel.fromFirestore(userDoc);
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Error getting user info: $e');
      }
      rethrow;
    }
  }

  Stream<List<ConversationModel>> getUserConversations(String userId) {
    if (kDebugMode) {
      Logger.error('🔍 Getting conversations for user: $userId');
    }

    try {
      // Prefer new schema: participantIds contains user
      final baseQuery = _firestore
          .collection('Conversations')
          .where('participantIds', arrayContains: userId)
          .snapshots();

      return baseQuery.asyncMap((snapshotNew) async {
        final convNew = snapshotNew.docs
            .map((doc) {
              try {
                return ConversationModel.fromFirestore(doc);
              } catch (e) {
                if (kDebugMode) Logger.error('❌ Parse conv error: $e');
                return null;
              }
            })
            .whereType<ConversationModel>()
            .toList();

        // Legacy fallback: participant1Id/participant2Id
        final legacy1 = await _firestore
            .collection('Conversations')
            .where('participant1Id', isEqualTo: userId)
            .get();
        final legacy2 = await _firestore
            .collection('Conversations')
            .where('participant2Id', isEqualTo: userId)
            .get();

        final convLegacy = <ConversationModel>[];
        for (final doc in [...legacy1.docs, ...legacy2.docs]) {
          try {
            convLegacy.add(ConversationModel.fromFirestore(doc));
          } catch (_) {}
        }

        // Merge by id
        final byId = <String, ConversationModel>{
          for (final c in convNew) c.id: c,
          for (final c in convLegacy) c.id: c,
        };
        final all = byId.values.toList();
        all.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
        return all;
      });
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Error in getUserConversations: $e');
      }
      return Stream.value([]);
    }
  }

  Future<ConversationModel?> createConversation({
    required String userId,
    required String otherUserId,
    required Map<String, dynamic> otherUserInfo,
  }) async {
    try {
      if (kDebugMode) {
        Logger.error(
          '🔧 Creating conversation between $userId and $otherUserId',
        );
      }

      // Get user info for both participants
      final userInfo = await _getUserInfo(userId);

      // Create conversation document with proper ID
      final conversationId = _getConversationId(userId, otherUserId);
      final participantIds = [userId, otherUserId]..sort();
      final conversationData = {
        'participant1Id': userId,
        'participant2Id': otherUserId,
        'participantIds': participantIds,
        'isGroup': false,
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unreadCount': 0,
        'participantInfo': {
          userId: {
            'name': userInfo.name,
            'profilePictureUrl': userInfo.profilePictureUrl,
            'username': userInfo.username,
          },
          otherUserId: otherUserInfo,
        },
      };

      await _firestore
          .collection('Conversations')
          .doc(conversationId)
          .set(conversationData);

      // Create the conversation model
      final conversation = ConversationModel(
        id: conversationId,
        participant1Id: userId,
        participant2Id: otherUserId,
        participantIds: participantIds,
        lastMessage: '',
        lastMessageTime: DateTime.now(),
        unreadCount: 0,
        participantInfo:
            conversationData['participantInfo'] as Map<String, dynamic>,
        isGroup: false,
      );

      if (kDebugMode) {
        Logger.error('✅ Conversation created with ID: $conversationId');
      }
      return conversation;
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Error creating conversation: $e');
      }
      return null;
    }
  }

  Stream<List<MessageModel>> getMessages(String conversationId) {
    try {
      if (kDebugMode) {
        Logger.error('🔍 Getting messages for conversation: $conversationId');
      }

      return _firestore
          .collection('Messages')
          .where('conversationId', isEqualTo: conversationId)
          .orderBy('timestamp', descending: false)
          .snapshots()
          .map((snapshot) {
            final messageModels = snapshot.docs
                .map((doc) {
                  try {
                    return MessageModel.fromFirestore(doc);
                  } catch (e) {
                    if (kDebugMode) {
                      Logger.error('❌ Error parsing message document: $e');
                    }
                    return null;
                  }
                })
                .whereType<MessageModel>()
                .toList();
            return messageModels;
          });
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Error in getMessages: $e');
      }
      return Stream.value([]);
    }
  }

  Future<void> markMessagesAsRead(
    String conversationId,
    String currentUserId,
  ) async {
    try {
      final batch = _firestore.batch();

      // Get conversation to know if it's group
      final convDoc = await _firestore
          .collection('Conversations')
          .doc(conversationId)
          .get();
      final isGroup = (convDoc.data() ?? const {})['isGroup'] == true;

      if (isGroup) {
        final messagesQuery = await _firestore
            .collection('Messages')
            .where('conversationId', isEqualTo: conversationId)
            .get();
        for (final doc in messagesQuery.docs) {
          batch.update(doc.reference, {
            'readByUserIds': FieldValue.arrayUnion([currentUserId]),
          });
        }
      } else {
        final participants = conversationId.split('_');
        if (participants.length == 2) {
          final otherParticipantId = participants.firstWhere(
            (id) => id != currentUserId,
          );
          final messagesQuery = await _firestore
              .collection('Messages')
              .where('senderId', isEqualTo: otherParticipantId)
              .where('receiverId', isEqualTo: currentUserId)
              .where('isRead', isEqualTo: false)
              .get();
          for (final doc in messagesQuery.docs) {
            batch.update(doc.reference, {'isRead': true});
          }
        }
      }

      await batch.commit();
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Error marking messages as read: $e');
      }
    }
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
        'unreadCount': 0,
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
    try {
      final queryLower = query.toLowerCase();
      final usersQuery = await _firestore
          .collection('Customers')
          .where('isDiscoverable', isEqualTo: true)
          .get();

      final users = usersQuery.docs
          .map((doc) => CustomerModel.fromFirestore(doc))
          .where(
            (user) =>
                user.uid != currentUserId &&
                (user.name.toLowerCase().contains(queryLower) ||
                    (user.username?.toLowerCase().contains(queryLower) ??
                        false)),
          )
          .toList();

      return users;
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Error searching users: $e');
      }
      return [];
    }
  }

  Future<String?> getConversationId(String userId1, String userId2) async {
    try {
      final conversationId = _getConversationId(userId1, userId2);
      final conversationDoc = await _firestore
          .collection('Conversations')
          .doc(conversationId)
          .get();

      return conversationDoc.exists ? conversationId : null;
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Error getting conversation ID: $e');
      }
      return null;
    }
  }

  // Public methods
  Future<void> updateNotificationSettings(
    UserNotificationSettings settings,
  ) async {
    await _saveNotificationSettings(settings);
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

  Future<void> sendEventReminder(
    String eventId,
    String eventTitle,
    DateTime eventTime,
  ) async {
    if (_settings?.eventReminders == true) {
      try {
        final reminderTime = DateTime.now().add(
          Duration(minutes: _settings!.reminderTime),
        );

        await _firestore.collection('scheduledNotifications').add({
          'type': 'event_reminder',
          'eventId': eventId,
          'eventTitle': eventTitle,
          'eventTime': Timestamp.fromDate(eventTime),
          'scheduledTime': Timestamp.fromDate(reminderTime),
          'title': 'Event Reminder',
          'body':
              'Your event "$eventTitle" starts in ${_settings!.reminderTime} minutes',
          'userId': _auth.currentUser?.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        if (kDebugMode) {
          Logger.error('❌ Error scheduling event reminder: $e');
        }
      }
    }
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

  Stream<List<NotificationModel>> getUserNotifications() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => NotificationModel.fromFirestore(doc))
              .toList(),
        );
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

// Background message handler
Future<void> _firebaseMessagingBackgroundHandler(
  fcm.RemoteMessage message,
) async {
  if (kDebugMode) {
    Logger.error('📱 Handling background message: ${message.messageId}');
  }
  // Handle background messages here
}
