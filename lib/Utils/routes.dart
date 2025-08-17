import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:orgami/models/event_model.dart';
import 'package:orgami/screens/Events/single_event_screen.dart';
import 'package:orgami/screens/Messaging/chat_screen.dart';
import 'package:orgami/screens/Organizations/organization_profile_screen.dart';
import 'package:orgami/screens/Home/notification_settings_screen.dart';
import 'package:orgami/screens/Events/event_feedback_management_screen.dart';
import 'package:orgami/screens/QRScanner/qr_scanner_flow_screen.dart';
import 'package:orgami/screens/Home/notifications_screen.dart';

class Nav {
  static Future<void> toEvent(BuildContext context, String eventId) async {
    final doc = await FirebaseFirestore.instance
        .collection(EventModel.firebaseKey)
        .doc(eventId)
        .get();
    if (!doc.exists) return;
    final event = EventModel.fromJson(doc);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SingleEventScreen(eventModel: event)),
    );
  }

  static Future<void> toChat(BuildContext context, String conversationId) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatScreen(conversationId: conversationId)),
    );
  }

  static Future<void> toOrganization(BuildContext context, String organizationId) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OrganizationProfileScreen(organizationId: organizationId)),
    );
  }

  static Future<void> toNotificationsSettings(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()),
    );
  }

  static Future<void> toNotifications(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
  }

  static Future<void> toEventFeedbackManagement(BuildContext context, String eventId) async {
    final doc = await FirebaseFirestore.instance
        .collection(EventModel.firebaseKey)
        .doc(eventId)
        .get();
    if (!doc.exists) return;
    final event = EventModel.fromJson(doc);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventFeedbackManagementScreen(eventModel: event),
      ),
    );
  }

  static Future<void> toQRScannerFlowReplacement(BuildContext context) {
    return Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const QRScannerFlowScreen()),
    );
  }
}