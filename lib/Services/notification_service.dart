import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  // Initialize notification service
  static Future<void> initialize() async {
    try {
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

      await _notifications.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: onNotificationTapped,
      );

      // Create Android notification channel (Android 8+)
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'attendus_channel',
        'Attendus Notifications',
        description: 'Notifications for Attendus events and updates',
        importance: Importance.high,
      );
      await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error initializing notification service: $e');
      }
    }
  }

  // Show local notification
  static Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
            'attendus_channel',
            'Attendus Notifications',
            channelDescription: 'Notifications for Attendus events and updates',
            importance: Importance.max,
            priority: Priority.high,
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

      await _notifications.show(
        id: 0,
        title: title,
        body: body,
        notificationDetails: platformChannelSpecifics,
        payload: payload,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error showing notification: $e');
      }
    }
  }

  // Handle notification tap
  static void onNotificationTapped(NotificationResponse response) {
    if (kDebugMode) {
      debugPrint('Notification tapped: ${response.payload}');
    }
    // Handle navigation based on payload
  }
}
