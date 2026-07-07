import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:attendus/models/customer_model.dart';
import 'package:flutter/foundation.dart';

class SMSNotificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Send SMS notification to event attendees
  static Future<bool> sendSMSNotification({
    required String eventId,
    required String message,
    required String eventTitle,
  }) async {
    try {
      // Get event attendees
      List<CustomerModel> attendees = await _getEventAttendees(eventId);

      if (attendees.isEmpty) {
        if (kDebugMode) {
          debugPrint('No attendees found for event: $eventId');
        }
        return false;
      }

      // Send SMS to each attendee
      int successCount = 0;
      for (CustomerModel attendee in attendees) {
        if (attendee.phoneNumber != null && attendee.phoneNumber!.isNotEmpty) {
          bool success = await _sendSingleSMS(
            phoneNumber: attendee.phoneNumber!,
            message: message,
            attendeeName: attendee.name,
          );

          if (success) {
            successCount++;
          }
        }
      }

      if (kDebugMode) {
        debugPrint('SMS Notification sent to ${attendees.length} recipients');
        debugPrint('Message: $message');
        debugPrint('Event: $eventTitle');
      }

      // Log notification history
      await _logNotificationHistory(
        eventId,
        message,
        attendees.length,
        successCount,
      );

      return successCount > 0;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error sending SMS notification: $e');
      }
      return false;
    }
  }

  // Get event attendees
  static Future<List<CustomerModel>> _getEventAttendees(String eventId) async {
    try {
      QuerySnapshot attendanceSnapshot = await _firestore
          .collection('Attendance')
          .where('eventId', isEqualTo: eventId)
          .where('status', isEqualTo: 'confirmed')
          .get();

      List<CustomerModel> attendees = [];

      for (DocumentSnapshot doc in attendanceSnapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        String customerId = data['customerId'];

        // Get customer details
        DocumentSnapshot customerDoc = await _firestore
            .collection('Customers')
            .doc(customerId)
            .get();

        if (customerDoc.exists) {
          CustomerModel customer = CustomerModel.fromFirestore(customerDoc);
          attendees.add(customer);
        }
      }

      return attendees;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting previous attendees: $e');
      }
      return [];
    }
  }

  // Send single SMS
  static Future<bool> _sendSingleSMS({
    required String phoneNumber,
    required String message,
    required String attendeeName,
  }) async {
    try {
      // Here you would integrate with your SMS service provider
      // For example: Twilio, AWS SNS, etc.

      // Simulate SMS sending (replace with actual SMS service)
      await Future.delayed(const Duration(milliseconds: 100));

      if (kDebugMode) {
        print('Sent to: $attendeeName ($phoneNumber)');
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error sending SMS to $phoneNumber: $e');
      }
      return false;
    }
  }

  // Log notification history
  static Future<void> _logNotificationHistory(
    String eventId,
    String message,
    int totalRecipients,
    int successCount,
  ) async {
    try {
      await _firestore.collection('notification_history').add({
        'eventId': eventId,
        'type': 'sms',
        'message': message,
        'totalRecipients': totalRecipients,
        'successCount': successCount,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting notification history: $e');
      }
    }
  }

  // Get notification history
  static Future<List<Map<String, dynamic>>> getNotificationHistory(
    String eventId,
  ) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('notification_history')
          .where('eventId', isEqualTo: eventId)
          .orderBy('timestamp', descending: true)
          .get();

      List<Map<String, dynamic>> history = [];
      for (DocumentSnapshot doc in snapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        history.add(data);
      }

      return history;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting notification history: $e');
      }
      return [];
    }
  }
}
