import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart' as fcm;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:orgami/Models/NotificationModel.dart';

class FirebaseMessagingHelper {
  static final FirebaseMessagingHelper _instance =
      FirebaseMessagingHelper._internal();
  factory FirebaseMessagingHelper() => _instance;
  FirebaseMessagingHelper._internal();

  final fcm.FirebaseMessaging _messaging = fcm.FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  FlutterLocalNotificationsPlugin? _localNotifications;
  String? _fcmToken;
  UserNotificationSettings? _settings;

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
      _fcmToken = await _messaging.getToken();
      if (_fcmToken != null) {
        await _saveTokenToFirestore(_fcmToken!);
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
      default:
        // Navigate to notifications screen
        break;
    }
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
