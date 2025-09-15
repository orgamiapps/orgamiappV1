import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationBroadcastService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Send in-app notifications to specific userIds via callable
  static Future<Map<String, dynamic>> sendInApp({
    required List<String> userIds,
    required String title,
    required String body,
    String type = 'custom',
    Map<String, dynamic>? data,
  }) async {
    final callable = _functions.httpsCallable('sendCustomNotifications');
    final result = await callable.call({
      'userIds': userIds,
      'title': title,
      'body': body,
      'type': type,
      'data': data ?? {},
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  // Send SMS via callable Twilio backend (safe no-op if not configured)
  static Future<Map<String, dynamic>> sendSms({
    required List<String> phoneNumbers,
    required String message,
    Map<String, dynamic>? meta,
  }) async {
    final callable = _functions.httpsCallable('sendBulkSms');
    final result = await callable.call({
      'phoneNumbers': phoneNumbers,
      'message': message,
      'meta': meta ?? {},
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  // Fetch notification history
  static Future<List<Map<String, dynamic>>> getHistory({
    String? eventId,
  }) async {
    Query query = _firestore
        .collection('notification_history')
        .orderBy('timestamp', descending: true);
    if (eventId != null && eventId.isNotEmpty) {
      query = query.where('meta.eventId', isEqualTo: eventId);
    }
    final snap = await query.limit(50).get();
    return snap.docs
        .map((d) => Map<String, dynamic>.from(d.data() as Map))
        .toList();
  }
}
