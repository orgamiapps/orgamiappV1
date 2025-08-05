import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart' as fcm;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:orgami/Models/MessageModel.dart';
import 'package:orgami/Models/CustomerModel.dart';
import 'package:orgami/Models/NotificationModel.dart';
import 'package:orgami/Models/EventModel.dart';

class FirebaseMessagingHelper {
  static final FirebaseMessagingHelper _instance =
      FirebaseMessagingHelper._internal();
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

      if (settings.authorizationStatus == fcm.AuthorizationStatus.authorized) {
        print('✅ Notification permissions granted');
      } else {
        print('❌ Notification permissions denied');
      }

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Get FCM token
      String? _fcmToken = await _messaging.getToken();
      if (_fcmToken != null) {
        await _saveTokenToFirestore(_fcmToken);
      }

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((token) {
        _fcmToken = token;
        _saveTokenToFirestore(token);
      });

      // Handle background messages
      fcm.FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      // Handle foreground messages
      fcm.FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle notification taps
      fcm.FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // Load user settings
      await _loadNotificationSettings();
    } catch (e) {
      print('❌ Error initializing Firebase Messaging: $e');
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
        await _firestore.collection('users').doc(user.uid).update({
          'fcmToken': token,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        });
        print('✅ FCM token saved to Firestore');
      }
    } catch (e) {
      print('❌ Error saving FCM token: $e');
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
      print('❌ Error loading notification settings: $e');
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
      print('❌ Error saving notification settings: $e');
    }
  }

  void _handleForegroundMessage(fcm.RemoteMessage message) {
    print('📱 Received foreground message: ${message.notification?.title}');

    if (_settings?.generalNotifications == true) {
      _showLocalNotification(message);
    }
  }

  void _handleNotificationTap(fcm.RemoteMessage message) {
    print('👆 Notification tapped: ${message.data}');
    // Handle navigation based on message data
    _handleNotificationNavigation(message.data);
  }

  void _onNotificationTapped(NotificationResponse response) {
    print('👆 Local notification tapped: ${response.payload}');
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
        final eventData = doc.data() as Map<String, dynamic>;
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
    required String receiverId,
    required String content,
    String messageType = 'text',
    String? mediaUrl,
    String? fileName,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      print('📤 Creating message data for receiver: $receiverId');
      final messageData = {
        'senderId': user.uid,
        'receiverId': receiverId,
        'content': content,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'messageType': messageType,
        'mediaUrl': mediaUrl,
        'fileName': fileName,
      };

      print('📤 Adding message to Firestore...');
      final messageRef = await _firestore
          .collection('Messages')
          .add(messageData);

      print('✅ Message added with ID: ${messageRef.id}');

      // Update or create conversation
      await _updateConversation(
        senderId: user.uid,
        receiverId: receiverId,
        lastMessage: content,
        lastMessageTime: DateTime.now(),
      );

      // Ensure conversation exists
      await _ensureConversationExists(user.uid, receiverId);

      // Send push notification to receiver
      await _sendPushNotification(receiverId, content, user.uid);

      return messageRef.id;
    } catch (e) {
      print('❌ Error sending message: $e');
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
        print('🔧 Creating conversation $conversationId');
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
      print('❌ Error ensuring conversation exists: $e');
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
      print(
        '📱 Sending push notification to $receiverId: $content from $senderName',
      );

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
      print('❌ Error sending push notification: $e');
    }
  }

  Future<void> _updateConversation({
    required String senderId,
    required String receiverId,
    required String lastMessage,
    required DateTime lastMessageTime,
  }) async {
    try {
      final conversationId = _getConversationId(senderId, receiverId);
      final conversationRef = _firestore
          .collection('Conversations')
          .doc(conversationId);

      // Get participant info
      final senderInfo = await _getUserInfo(senderId);
      final receiverInfo = await _getUserInfo(receiverId);

      // Use sorted IDs for consistency
      final sortedIds = [senderId, receiverId]..sort();
      final participant1Id = sortedIds[0];
      final participant2Id = sortedIds[1];

      final conversationData = {
        'participant1Id': participant1Id,
        'participant2Id': participant2Id,
        'lastMessage': lastMessage,
        'lastMessageTime': lastMessageTime,
        'participantInfo': {
          senderId: {
            'name': senderInfo.name,
            'profilePictureUrl': senderInfo.profilePictureUrl,
            'username': senderInfo.username,
          },
          receiverId: {
            'name': receiverInfo.name,
            'profilePictureUrl': receiverInfo.profilePictureUrl,
            'username': receiverInfo.username,
          },
        },
      };

      print('💬 Updating conversation $conversationId with message: $lastMessage');
      await conversationRef.set(conversationData, SetOptions(merge: true));
      print('✅ Conversation updated successfully');
    } catch (e) {
      print('❌ Error updating conversation: $e');
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
      print('❌ Error getting user info: $e');
      rethrow;
    }
  }

  Stream<List<ConversationModel>> getUserConversations(String userId) {
    print('🔍 Getting conversations for user: $userId');

    try {
      // Get conversations where user is either participant1 or participant2
      return _firestore
          .collection('Conversations')
          .where('participant1Id', isEqualTo: userId)
          .snapshots()
          .asyncMap((snapshot1) async {
            print(
              '📊 Found ${snapshot1.docs.length} conversations as participant1',
            );

            final conversations1 = snapshot1.docs
                .map((doc) {
                  try {
                    return ConversationModel.fromFirestore(doc);
                  } catch (e) {
                    print('❌ Error parsing conversation document: $e');
                    return null;
                  }
                })
                .where((conversation) => conversation != null)
                .cast<ConversationModel>()
                .toList();

            // Also get conversations where user is participant2
            final snapshot2 = await _firestore
                .collection('Conversations')
                .where('participant2Id', isEqualTo: userId)
                .get();

            print(
              '📊 Found ${snapshot2.docs.length} conversations as participant2',
            );

            final conversations2 = snapshot2.docs
                .map((doc) {
                  try {
                    return ConversationModel.fromFirestore(doc);
                  } catch (e) {
                    print('❌ Error parsing conversation document: $e');
                    return null;
                  }
                })
                .where((conversation) => conversation != null)
                .cast<ConversationModel>()
                .toList();

            // Combine and sort by last message time
            final allConversations = [...conversations1, ...conversations2];
            allConversations.sort(
              (a, b) => b.lastMessageTime.compareTo(a.lastMessageTime),
            );

            print('✅ Total conversations found: ${allConversations.length}');
            return allConversations;
          });
    } catch (e) {
      print('❌ Error in getUserConversations: $e');
      return Stream.value([]);
    }
  }

  Future<ConversationModel?> createConversation({
    required String userId,
    required String otherUserId,
    required Map<String, dynamic> otherUserInfo,
  }) async {
    try {
      print('🔧 Creating conversation between $userId and $otherUserId');

      // Get user info for both participants
      final userInfo = await _getUserInfo(userId);

      // Create conversation document with proper ID
      final conversationId = _getConversationId(userId, otherUserId);
      final conversationData = {
        'participant1Id': userId,
        'participant2Id': otherUserId,
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
        lastMessage: '',
        lastMessageTime: DateTime.now(),
        unreadCount: 0,
        participantInfo:
            conversationData['participantInfo'] as Map<String, dynamic>,
      );

      print('✅ Conversation created with ID: $conversationId');
      return conversation;
    } catch (e) {
      print('❌ Error creating conversation: $e');
      return null;
    }
  }

  Stream<List<MessageModel>> getMessages(String conversationId) {
    try {
      print('🔍 Getting messages for conversation: $conversationId');

      // Parse conversation ID to get participants
      final participants = conversationId.split('_');
      if (participants.length != 2) {
        print('❌ Invalid conversation ID format: $conversationId');
        return Stream.value([]);
      }

      final participant1Id = participants[0];
      final participant2Id = participants[1];

      print('📊 Getting messages between $participant1Id and $participant2Id');

      // Get messages in both directions using separate queries
      return _firestore
          .collection('Messages')
          .where('senderId', isEqualTo: participant1Id)
          .where('receiverId', isEqualTo: participant2Id)
          .orderBy('timestamp', descending: false)
          .snapshots()
          .asyncMap((snapshot1) async {
            final messages1 = snapshot1.docs;

            // Get messages in the other direction
            final snapshot2 = await _firestore
                .collection('Messages')
                .where('senderId', isEqualTo: participant2Id)
                .where('receiverId', isEqualTo: participant1Id)
                .orderBy('timestamp', descending: false)
                .get();

            final messages2 = snapshot2.docs;

            // Combine and sort all messages
            final allMessages = [...messages1, ...messages2];
            allMessages.sort((a, b) {
              final timestampA = (a.data()['timestamp'] as Timestamp).toDate();
              final timestampB = (b.data()['timestamp'] as Timestamp).toDate();
              return timestampA.compareTo(timestampB);
            });

            final messageModels = allMessages
                .map((doc) {
                  try {
                    return MessageModel.fromFirestore(doc);
                  } catch (e) {
                    print('❌ Error parsing message document: $e');
                    return null;
                  }
                })
                .where((message) => message != null)
                .cast<MessageModel>()
                .toList();

            print('✅ Found ${messageModels.length} messages');
            return messageModels;
          });
    } catch (e) {
      print('❌ Error in getMessages: $e');
      return Stream.value([]);
    }
  }

  Future<void> markMessagesAsRead(
    String conversationId,
    String currentUserId,
  ) async {
    try {
      final participants = conversationId.split('_');
      if (participants.length != 2) return;

      final batch = _firestore.batch();
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

      await batch.commit();
    } catch (e) {
      print('❌ Error marking messages as read: $e');
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
      print('❌ Error searching users: $e');
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
      print('❌ Error getting conversation ID: $e');
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
    if (_settings?.eventReminders != true) return;

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
      print('❌ Error scheduling event reminder: $e');
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
      print('❌ Error marking notification as read: $e');
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
      print('❌ Error deleting notification: $e');
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
      print('✅ Subscribed to topic: $topic');
    } catch (e) {
      print('❌ Error subscribing to topic: $e');
    }
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      print('✅ Unsubscribed from topic: $topic');
    } catch (e) {
      print('❌ Error unsubscribing from topic: $e');
    }
  }
}

// Background message handler
Future<void> _firebaseMessagingBackgroundHandler(
  fcm.RemoteMessage message,
) async {
  print('📱 Handling background message: ${message.messageId}');
  // Handle background messages here
}
