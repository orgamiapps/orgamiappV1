import 'package:attendus/firebase/firebase_messaging_helper.dart';
import 'package:flutter/foundation.dart';

/// A utility class to generate sample notifications for testing purposes
class SampleNotificationGenerator {
  static final FirebaseMessagingHelper _messagingHelper =
      FirebaseMessagingHelper();

  /// Generate a set of sample notifications for testing
  static Future<void> generateSampleNotifications() async {
    try {
      // Event Reminder
      await _messagingHelper.createLocalNotification(
        title: 'Event Reminder',
        body:
            'Your event "Tech Conference 2024" starts in 1 hour at Convention Center',
        type: 'event_reminder',
        eventId: 'sample_event_1',
        eventTitle: 'Tech Conference 2024',
      );

      await Future.delayed(const Duration(milliseconds: 500));

      // New Event in Area
      await _messagingHelper.createLocalNotification(
        title: 'New Event Near You',
        body:
            'Workshop: "Flutter Development Best Practices" happening tomorrow in your area',
        type: 'new_event',
        eventId: 'sample_event_2',
        eventTitle: 'Flutter Development Best Practices',
      );

      await Future.delayed(const Duration(milliseconds: 500));

      // Group Event Notification
      await _messagingHelper.createLocalNotification(
        title: 'New Event in Flutter Developers Group',
        body:
            '"Monthly Meetup: State Management Discussion" has been created in Flutter Developers Group',
        type: 'group_event',
        eventId: 'sample_event_8',
        eventTitle: 'Monthly Meetup: State Management Discussion',
        data: {
          'organizationId': 'sample_org_2',
          'organizationName': 'Flutter Developers Group',
        },
      );

      await Future.delayed(const Duration(milliseconds: 500));

      // Ticket Update
      await _messagingHelper.createLocalNotification(
        title: 'Ticket Confirmed',
        body:
            'Your ticket for "Music Festival 2024" has been confirmed. Check-in opens at 6 PM',
        type: 'ticket_update',
        eventId: 'sample_event_3',
        eventTitle: 'Music Festival 2024',
      );

      await Future.delayed(const Duration(milliseconds: 500));

      // Event Changes
      await _messagingHelper.createLocalNotification(
        title: 'Event Updated',
        body:
            'The venue for "Startup Meetup" has changed to Downtown Community Center',
        type: 'event_changes',
        eventId: 'sample_event_4',
        eventTitle: 'Startup Meetup',
      );

      await Future.delayed(const Duration(milliseconds: 500));

      // Geofence Check-in
      await _messagingHelper.createLocalNotification(
        title: 'You\'re Near the Event!',
        body:
            'You\'re close to "Art Exhibition". Tap to check in and get your digital badge',
        type: 'geofence_checkin',
        eventId: 'sample_event_5',
        eventTitle: 'Art Exhibition',
      );

      await Future.delayed(const Duration(milliseconds: 500));

      // Message Mention
      await _messagingHelper.createLocalNotification(
        title: '@johndoe mentioned you',
        body:
            '@you Great presentation! Can we connect to discuss collaboration?',
        type: 'message_mention',
        data: {
          'conversationId': 'sample_conversation_1',
          'senderId': 'sample_user_1',
        },
      );

      await Future.delayed(const Duration(milliseconds: 500));

      // Organization Update
      await _messagingHelper.createLocalNotification(
        title: 'Join Request Approved',
        body: 'You\'ve been approved to join "Flutter Developers Community"',
        type: 'org_update',
        data: {'organizationId': 'sample_org_1'},
      );

      await Future.delayed(const Duration(milliseconds: 500));

      // Organizer Feedback
      await _messagingHelper.createLocalNotification(
        title: 'New Feedback Received',
        body: 'Your event "Coding Bootcamp" received new feedback: 5 stars!',
        type: 'organizer_feedback',
        eventId: 'sample_event_6',
        eventTitle: 'Coding Bootcamp',
      );

      await Future.delayed(const Duration(milliseconds: 500));

      // Event Feedback Request
      await _messagingHelper.createLocalNotification(
        title: 'How was the event?',
        body: 'Share your experience at "Product Launch" and help us improve!',
        type: 'event_feedback',
        eventId: 'sample_event_7',
        eventTitle: 'Product Launch',
      );

      await Future.delayed(const Duration(milliseconds: 500));

      // General Notification
      await _messagingHelper.createLocalNotification(
        title: 'Welcome to AttendUs!',
        body: 'Start exploring events near you and connect with your community',
        type: 'general',
      );

      if (kDebugMode) {
        print('✅ Sample notifications generated successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error generating sample notifications: $e');
      }
    }
  }

  /// Delete all notifications for the current user (for testing)
  static Future<void> clearAllNotifications() async {
    try {
      await _messagingHelper.clearAllNotifications();
      if (kDebugMode) {
        print('✅ All notifications cleared');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error clearing notifications: $e');
      }
    }
  }
}
