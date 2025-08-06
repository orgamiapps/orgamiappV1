import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:orgami/Models/CustomerModel.dart';
import 'package:orgami/Models/AttendanceModel.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';

class SMSNotificationService {
  static final SMSNotificationService _instance = SMSNotificationService._internal();
  factory SMSNotificationService() => _instance;
  SMSNotificationService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get all unique attendees who have attended any of the user's events
  Future<List<AttendeeInfo>> getAllPreviousAttendees() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // Get all events created by the current user
      final eventsQuery = await _firestore
          .collection('Events')
          .where('customerUid', isEqualTo: currentUser.uid)
          .get();

      final eventIds = eventsQuery.docs.map((doc) => doc.id).toList();
      if (eventIds.isEmpty) return [];

      // Get all attendance records for these events
      final attendanceQuery = await _firestore
          .collection('Attendance')
          .where('eventId', whereIn: eventIds)
          .get();

      // Group attendees by customerUid to get unique attendees
      final Map<String, AttendeeInfo> uniqueAttendees = {};
      
      for (final doc in attendanceQuery.docs) {
        final attendance = AttendanceModel.fromJson(doc);
        
        if (attendance.customerUid != currentUser.uid && 
            attendance.customerUid != 'manual' && 
            attendance.customerUid != 'without_login') {
          
          if (!uniqueAttendees.containsKey(attendance.customerUid)) {
            // Get customer details
            final customerDoc = await _firestore
                .collection('Customers')
                .doc(attendance.customerUid)
                .get();
            
            if (customerDoc.exists) {
              final customer = CustomerModel.fromFirestore(customerDoc);
              uniqueAttendees[attendance.customerUid] = AttendeeInfo(
                uid: attendance.customerUid,
                name: customer.name,
                email: customer.email,
                hasPhoneNumber: customer.phoneNumber != null && customer.phoneNumber!.isNotEmpty,
                phoneNumber: customer.phoneNumber, // This will be null for privacy
                lastAttendedEvent: attendance.attendanceDateTime,
                totalEventsAttended: 1, // Will be updated in the loop
              );
            }
          } else {
            // Update existing attendee info
            final existing = uniqueAttendees[attendance.customerUid]!;
            existing.totalEventsAttended++;
            if (attendance.attendanceDateTime.isAfter(existing.lastAttendedEvent)) {
              existing.lastAttendedEvent = attendance.attendanceDateTime;
            }
          }
        }
      }

      return uniqueAttendees.values.toList();
    } catch (e) {
      print('Error getting previous attendees: $e');
      return [];
    }
  }

  /// Send SMS notification to selected attendees
  Future<NotificationResult> sendSMSNotification({
    required List<String> attendeeUids,
    required String message,
    required String eventTitle,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // Get attendee details and validate phone numbers
      final attendees = <AttendeeInfo>[];
      final missingPhoneNumbers = <String>[];
      
      for (final uid in attendeeUids) {
        final customerDoc = await _firestore
            .collection('Customers')
            .doc(uid)
            .get();
        
        if (customerDoc.exists) {
          final customer = CustomerModel.fromFirestore(customerDoc);
          if (customer.phoneNumber != null && customer.phoneNumber!.isNotEmpty) {
            attendees.add(AttendeeInfo(
              uid: customer.uid,
              name: customer.name,
              email: customer.email,
              hasPhoneNumber: true,
              phoneNumber: customer.phoneNumber,
              lastAttendedEvent: DateTime.now(),
              totalEventsAttended: 1,
            ));
          } else {
            missingPhoneNumbers.add(customer.name);
          }
        }
      }

      // Store notification record in Firestore
      final notificationData = {
        'senderUid': currentUser.uid,
        'attendeeUids': attendeeUids,
        'message': message,
        'eventTitle': eventTitle,
        'sentAt': FieldValue.serverTimestamp(),
        'totalRecipients': attendees.length,
        'missingPhoneNumbers': missingPhoneNumbers,
        'status': 'sent',
      };

      await _firestore
          .collection('SMSNotifications')
          .add(notificationData);

      // In a real implementation, you would integrate with an SMS service here
      // For now, we'll simulate the SMS sending
      await _simulateSMSSending(attendees, message, eventTitle);

      return NotificationResult(
        success: true,
        sentCount: attendees.length,
        missingPhoneNumbers: missingPhoneNumbers,
        message: 'Notification sent successfully to ${attendees.length} recipients',
      );
    } catch (e) {
      print('Error sending SMS notification: $e');
      return NotificationResult(
        success: false,
        sentCount: 0,
        missingPhoneNumbers: [],
        message: 'Failed to send notification: $e',
      );
    }
  }

  /// Simulate SMS sending (replace with actual SMS service integration)
  Future<void> _simulateSMSSending(
    List<AttendeeInfo> attendees,
    String message,
    String eventTitle,
  ) async {
    // Simulate API delay
    await Future.delayed(const Duration(seconds: 2));
    
    // In a real implementation, you would:
    // 1. Use a service like Twilio, AWS SNS, or similar
    // 2. Send the actual SMS messages
    // 3. Handle delivery confirmations
    // 4. Update the notification status in Firestore
    
    print('SMS Notification sent to ${attendees.length} recipients');
    print('Message: $message');
    print('Event: $eventTitle');
    
    for (final attendee in attendees) {
      print('Sent to: ${attendee.name} (${attendee.phoneNumber})');
    }
  }

  /// Get notification history for the current user
  Future<List<NotificationHistory>> getNotificationHistory() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return [];

      final querySnapshot = await _firestore
          .collection('SMSNotifications')
          .where('senderUid', isEqualTo: currentUser.uid)
          .orderBy('sentAt', descending: true)
          .limit(50)
          .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        return NotificationHistory(
          id: doc.id,
          message: data['message'] ?? '',
          eventTitle: data['eventTitle'] ?? '',
          sentAt: (data['sentAt'] as Timestamp).toDate(),
          totalRecipients: data['totalRecipients'] ?? 0,
          missingPhoneNumbers: List<String>.from(data['missingPhoneNumbers'] ?? []),
          status: data['status'] ?? 'unknown',
        );
      }).toList();
    } catch (e) {
      print('Error getting notification history: $e');
      return [];
    }
  }
}

class AttendeeInfo {
  final String uid;
  final String name;
  final String email;
  final bool hasPhoneNumber;
  final String? phoneNumber; // Will be null for privacy
  DateTime lastAttendedEvent;
  int totalEventsAttended;

  AttendeeInfo({
    required this.uid,
    required this.name,
    required this.email,
    required this.hasPhoneNumber,
    this.phoneNumber,
    required this.lastAttendedEvent,
    required this.totalEventsAttended,
  });
}

class NotificationResult {
  final bool success;
  final int sentCount;
  final List<String> missingPhoneNumbers;
  final String message;

  NotificationResult({
    required this.success,
    required this.sentCount,
    required this.missingPhoneNumbers,
    required this.message,
  });
}

class NotificationHistory {
  final String id;
  final String message;
  final String eventTitle;
  final DateTime sentAt;
  final int totalRecipients;
  final List<String> missingPhoneNumbers;
  final String status;

  NotificationHistory({
    required this.id,
    required this.message,
    required this.eventTitle,
    required this.sentAt,
    required this.totalRecipients,
    required this.missingPhoneNumbers,
    required this.status,
  });
} 