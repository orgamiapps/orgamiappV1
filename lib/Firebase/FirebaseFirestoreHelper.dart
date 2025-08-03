import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:orgami/Controller/CustomerController.dart';
import 'package:orgami/Models/AttendanceModel.dart';
import 'package:orgami/Models/CommentModel.dart';
import 'package:orgami/Models/CustomerModel.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Models/EventQuestionModel.dart';

class FirebaseFirestoreHelper {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Retrieves a single customer from Firestore
  ///
  /// IMPORTANT: Ensure Firestore security rules allow read access for authenticated users:
  /// match /Customers/{customerId} {
  /// allow read, write: if request.auth != null && request.auth.uid == customerId;
  /// }
  ///
  /// This method handles PERMISSION_DENIED errors gracefully by returning null
  /// instead of throwing exceptions, allowing the app to continue functioning.
  Future<CustomerModel?> getSingleCustomer({required String customerId}) async {
    CustomerModel? customerModel;
    try {
      await _firestore
          .collection(CustomerModel.firebaseKey)
          .doc(customerId)
          .get()
          .then((singleCustomerData) {
            if (singleCustomerData.exists) {
              customerModel = CustomerModel.fromFirestore(singleCustomerData);
            }
          });
    } catch (e) {
      // Handle permission denied and other Firestore errors
      print('Permission denied for customer: $customerId');
      print('Error details: $e');
      // For manual/without_login users, create a temporary customer model
      if (customerId == 'manual' || customerId == 'without_login') {
        customerModel = CustomerModel(
          uid: customerId,
          name: customerId == 'manual' ? 'Manual User' : 'Anonymous User',
          email: '$customerId@orgami.app',
          createdAt: DateTime.now(),
        );
        print('Created temporary customer model for: $customerId');
      }
      // Return null instead of throwing to allow graceful handling
      return customerModel;
    }
    return customerModel;
  }

  Future<List<AttendanceModel>> getAttendance({required String eventId}) async {
    QuerySnapshot querySnapshot = await _firestore
        .collection(AttendanceModel.firebaseKey)
        .where('eventId', isEqualTo: eventId)
        .get();
    List<AttendanceModel> list = querySnapshot.docs.map((doc) {
      return AttendanceModel.fromJson(doc);
    }).toList();
    print('list Data length is ${list.length}');
    return list;
  }

  Future<List<AttendanceModel>> getRegisterAttendance({
    required String eventId,
  }) async {
    QuerySnapshot querySnapshot = await _firestore
        .collection(AttendanceModel.registerFirebaseKey)
        .where('eventId', isEqualTo: eventId)
        .get();
    List<AttendanceModel> list = querySnapshot.docs.map((doc) {
      return AttendanceModel.fromJson(doc);
    }).toList();
    print('list Data length is ${list.length}');
    return list;
  }

  Future<List<EventQuestionModel>> getEventQuestions({
    required String eventId,
  }) async {
    List<EventQuestionModel> list = [];
    try {
      QuerySnapshot querySnapshot = await _firestore
          .collection(EventModel.firebaseKey)
          .doc(eventId)
          .collection(EventQuestionModel.firebaseKey)
          .get();
      list = querySnapshot.docs.map((doc) {
        return EventQuestionModel.fromJson(doc);
      }).toList();
      print('list Data length is ${list.length}');
    } catch (e) {
      // Handle permission denied and other Firestore errors
      print('Error fetching event questions for event: $eventId');
      print('Error details: $e');
      // Return empty list instead of throwing to allow graceful handling
      return [];
    }
    return list;
  }

  Future<bool> checkIfUserIsSignedIn(String eventId) async {
    QuerySnapshot querySnapshot = await _firestore
        .collection(AttendanceModel.firebaseKey)
        .where('eventId', isEqualTo: eventId)
        .where('customerUid', isEqualTo: CustomerController.logeInCustomer!.uid)
        .get();
    List<AttendanceModel> list = querySnapshot.docs.map((doc) {
      return AttendanceModel.fromJson(doc);
    }).toList();
    print('list Data length is ${list.length}');
    return list.isNotEmpty ? true : false;
  }

  Future<bool> checkIfUserIsRegistered(String eventId) async {
    QuerySnapshot querySnapshot = await _firestore
        .collection(AttendanceModel.registerFirebaseKey)
        .where('eventId', isEqualTo: eventId)
        .where('customerUid', isEqualTo: CustomerController.logeInCustomer!.uid)
        .get();
    List<AttendanceModel> list = querySnapshot.docs.map((doc) {
      return AttendanceModel.fromJson(doc);
    }).toList();
    print('list Data length is ${list.length}');
    return list.isNotEmpty ? true : false;
  }

  Future<EventModel?> getSingleEvent(String eventId) async {
    EventModel? eventData;
    try {
      DocumentSnapshot snap = await _firestore
          .collection(EventModel.firebaseKey)
          .doc(eventId)
          .get();
      if (snap.exists) {
        eventData = EventModel.fromJson(snap);
      }
    } catch (e) {
      // Handle permission denied and other Firestore errors
      print('Error fetching event: $eventId');
      print('Error details: $e');
      // Return null instead of throwing to allow graceful handling
      return null;
    }
    return eventData;
  }

  Future<List<AttendanceModel>> getSignedInAttendance() async {
    QuerySnapshot querySnapshot = await _firestore
        .collection(AttendanceModel.firebaseKey)
        .where('customerUid', isEqualTo: CustomerController.logeInCustomer!.uid)
        .get();
    List<AttendanceModel> list = querySnapshot.docs.map((doc) {
      return AttendanceModel.fromJson(doc);
    }).toList();
    return list;
  }

  Future<List<AttendanceModel>> getPreRegisteredAttendance() async {
    QuerySnapshot querySnapshot = await _firestore
        .collection(AttendanceModel.registerFirebaseKey)
        .where('customerUid', isEqualTo: CustomerController.logeInCustomer!.uid)
        .get();
    List<AttendanceModel> list = querySnapshot.docs.map((doc) {
      return AttendanceModel.fromJson(doc);
    }).toList();
    return list;
  }

  Future<void> addEventToCustomersList() async {
    _firestore.collection(CustomerModel.firebaseKey).doc();
  }

  Future<String> getEventID() async {
    print('M Called for 1');
    const String fieldName = 'eventId';
    final DocumentReference ref = _firestore
        .collection('Settings')
        .doc('EventsSettings');
    try {
      DocumentSnapshot snap = await ref.get();
      if (snap.exists == true) {
        int itemCount = snap[fieldName] ?? 0;
        await _firestore.collection('Settings').doc('EventsSettings').update({
          'eventId': itemCount + 1,
        });
        print('M Called for $itemCount');
        return itemCount.toString();
      } else {
        // Create the document if it doesn't exist
        await ref.set({fieldName: 1});
        print('M Created new EventsSettings document');
        return '0';
      }
    } catch (e) {
      print('Error getting event ID: $e');
      // Fallback: use timestamp as event ID
      return DateTime.now().millisecondsSinceEpoch.toString();
    }
  }

  Future<int> getPreRegisterAttendanceCount({required String eventId}) async {
    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('RegisterAttendance')
        .where('eventId', isEqualTo: eventId)
        .get();
    return snapshot.docs.length;
  }

  // Update customer profile information
  Future<bool> updateCustomerProfile({
    required String customerId,
    String? name,
    String? profilePictureUrl,
    String? bio,
  }) async {
    try {
      Map<String, dynamic> updateData = {};
      if (name != null) {
        updateData['name'] = name;
      }
      if (profilePictureUrl != null) {
        updateData['profilePictureUrl'] = profilePictureUrl;
      }
      if (bio != null) {
        updateData['bio'] = bio;
      }
      await _firestore
          .collection(CustomerModel.firebaseKey)
          .doc(customerId)
          .update(updateData);
      return true;
    } catch (e) {
      print('Error updating customer profile: $e');
      return false;
    }
  }

  // Get comments for an event
  Future<List<CommentModel>> getEventComments({required String eventId}) async {
    try {
      print('Fetching comments for event: $eventId');
      QuerySnapshot querySnapshot = await _firestore
          .collection(CommentModel.firebaseKey)
          .where('eventId', isEqualTo: eventId)
          .orderBy('createdAt', descending: true)
          .get();
      print('Found ${querySnapshot.docs.length} comment documents');
      List<CommentModel> comments = querySnapshot.docs.map((doc) {
        print('Processing comment doc: ${doc.id}');
        return CommentModel.fromFirestore(doc);
      }).toList();
      print('Processed ${comments.length} comments');
      return comments;
    } catch (e) {
      print('Error getting comments: $e');
      return [];
    }
  }

  // Add a new comment with validation, event existence check, and detailed logging
  Future<bool> addComment({
    required String eventId,
    required String comment,
    BuildContext? context,
  }) async {
    try {
      // Validate comment text
      final trimmedComment = comment.trim();
      if (trimmedComment.isEmpty) {
        print('Firestore add error: Comment is empty');
        if (context != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to add comment: Comment is empty')),
          );
        }
        return false;
      }

      // Validate user
      final user = CustomerController.logeInCustomer;
      if (user == null) {
        print('Firestore add error: User not authenticated');
        if (context != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to add comment: User not authenticated'),
            ),
          );
        }
        return false;
      }

      // Check if event exists
      final eventDoc = await _firestore
          .collection(EventModel.firebaseKey)
          .doc(eventId)
          .get();
      if (!eventDoc.exists) {
        print(
          'Firestore add error: Event document does not exist for eventId: $eventId',
        );
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to add comment: Event does not exist'),
            ),
          );
        }
        return false;
      }

      String commentId = _firestore
          .collection(CommentModel.firebaseKey)
          .doc()
          .id;
      print('Generated comment ID: $commentId');

      // Prepare payload
      final payload = {
        'id': commentId,
        'eventId': eventId.trim(),
        'userId': user.uid.trim(),
        'userName': user.name.trim(),
        'userProfilePictureUrl': user.profilePictureUrl?.trim(),
        'comment': trimmedComment,
        'createdAt': FieldValue.serverTimestamp(),
      };
      print('Comment payload: $payload');

      await _firestore
          .collection(CommentModel.firebaseKey)
          .doc(commentId)
          .set(payload);
      print('Comment successfully saved to Firestore');
      return true;
    } catch (e) {
      print('Firestore add error: $e');
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add comment: ${e.toString()}')),
        );
      }
      return false;
    }
  }

  // Add a manual attendance record
  Future<void> addAttendance(AttendanceModel attendance) async {
    try {
      await _firestore
          .collection(AttendanceModel.firebaseKey)
          .doc(attendance.id)
          .set(attendance.toJson());
      print('Manual attendance added: ${attendance.userName}');
    } catch (e) {
      print('Error adding manual attendance: $e');
      rethrow;
    }
  }

  // Get events created by a user
  Future<List<EventModel>> getEventsCreatedByUser(String userId) async {
    try {
      print('Fetching events created by user: $userId');
      final query = await _firestore
          .collection(EventModel.firebaseKey)
          .where('customerUid', isEqualTo: userId)
          .get();
      print('Found ${query.docs.length} events created by user');
      final events = query.docs
          .map((doc) {
            try {
              return EventModel.fromJson(doc.data());
            } catch (e) {
              print('Error parsing event document: $e');
              return null;
            }
          })
          .where((event) => event != null)
          .cast<EventModel>()
          .toList();
      print('Successfully parsed ${events.length} events');
      return events;
    } catch (e) {
      print('Error fetching created events: $e');
      return [];
    }
  }

  // Test method to manually add attendance for debugging
  Future<void> addTestAttendance(String eventId, String userId) async {
    try {
      String docId = '$eventId-$userId';
      AttendanceModel testAttendance = AttendanceModel(
        id: docId,
        eventId: eventId,
        userName: 'Test User',
        customerUid: userId,
        attendanceDateTime: DateTime.now(),
        answers: [],
        isAnonymous: false,
        realName: null,
      );
      print('Adding test attendance: $docId');
      print('Test attendance data: ${testAttendance.toJson()}');
      await _firestore
          .collection(AttendanceModel.firebaseKey)
          .doc(docId)
          .set(testAttendance.toJson());
      print('Test attendance added successfully: $docId');
    } catch (e) {
      print('Error adding test attendance: $e');
    }
  }

  // Test method to create a test event
  Future<String> createTestEvent() async {
    try {
      String eventId = 'test-event-${DateTime.now().millisecondsSinceEpoch}';
      EventModel testEvent = EventModel(
        id: eventId,
        groupName: 'Test Group',
        title: 'Test Event',
        description: 'This is a test event for debugging',
        location: 'Test Location',
        customerUid: 'test-user',
        imageUrl:
            'https://picsum.photos/300/200', // Using a working image service
        selectedDateTime: DateTime.now().add(const Duration(days: 1)),
        eventGenerateTime: DateTime.now(),
        status: 'active',
        private: false, // Make sure it's public so users can access it
        getLocation: false,
        radius: 1.0,
        latitude: 0.0,
        longitude: 0.0,
        categories: ['Test'],
      );
      await _firestore
          .collection(EventModel.firebaseKey)
          .doc(eventId)
          .set(testEvent.toJson());
      print('Test event created: $eventId (Public: true)');
      return eventId;
    } catch (e) {
      print('Error creating test event: $e');
      return '';
    }
  }

  // Comprehensive test method to create test data for debugging attended events
  Future<void> createTestDataForAttendedEvents(String userId) async {
    try {
      print('=== Creating test data for attended events debugging ===');

      // Create a test event
      String eventId = await createTestEvent();
      if (eventId.isEmpty) {
        print('Failed to create test event');
        return;
      }

      // Create attendance record for the user
      String attendanceId = '$eventId-$userId';
      AttendanceModel testAttendance = AttendanceModel(
        id: attendanceId,
        eventId: eventId,
        userName: 'Test User',
        customerUid: userId,
        attendanceDateTime: DateTime.now(),
        answers: ['Test answer 1', 'Test answer 2'],
        isAnonymous: false,
        realName: 'Test User Real Name',
      );

      await _firestore
          .collection(AttendanceModel.firebaseKey)
          .doc(attendanceId)
          .set(testAttendance.toJson());

      print('Test attendance created: $attendanceId');
      print('Test data summary:');
      print('- Event ID: $eventId');
      print('- User ID: $userId');
      print('- Attendance ID: $attendanceId');
      print('- Attendance data: ${testAttendance.toJson()}');

      // Verify the data was created
      final attendanceDoc = await _firestore
          .collection(AttendanceModel.firebaseKey)
          .doc(attendanceId)
          .get();

      if (attendanceDoc.exists) {
        print('✓ Attendance record verified in database');
      } else {
        print('✗ Attendance record not found in database');
      }

      final eventDoc = await _firestore
          .collection(EventModel.firebaseKey)
          .doc(eventId)
          .get();

      if (eventDoc.exists) {
        print('✓ Event record verified in database');
      } else {
        print('✗ Event record not found in database');
      }
    } catch (e) {
      print('Error creating test data: $e');
    }
  }

  // Test method to create a past event and attendance
  Future<void> createPastEventAndAttendance(String userId) async {
    try {
      print('=== Creating past event and attendance for debugging ===');

      // Create a past event (event date in the past)
      String eventId = 'past-event-${DateTime.now().millisecondsSinceEpoch}';
      EventModel pastEvent = EventModel(
        id: eventId,
        groupName: 'Past Test Group',
        title: 'Past Test Event',
        description: 'This is a past test event for debugging attended events',
        location: 'Past Test Location',
        customerUid: 'test-host-user',
        imageUrl:
            'https://picsum.photos/300/200', // Using a working image service
        selectedDateTime: DateTime.now().subtract(
          const Duration(days: 7),
        ), // Past event
        eventGenerateTime: DateTime.now().subtract(const Duration(days: 14)),
        status: 'completed',
        private: false, // Make sure it's public so users can access it
        getLocation: false,
        radius: 1.0,
        latitude: 0.0,
        longitude: 0.0,
        categories: ['Educational', 'Test'],
      );

      await _firestore
          .collection(EventModel.firebaseKey)
          .doc(eventId)
          .set(pastEvent.toJson());
      print('Past test event created: $eventId');

      // Create attendance record for the user
      String attendanceId = '$eventId-$userId';
      AttendanceModel pastAttendance = AttendanceModel(
        id: attendanceId,
        eventId: eventId,
        userName: 'Test User',
        customerUid: userId,
        attendanceDateTime: DateTime.now().subtract(
          const Duration(days: 6),
        ), // Attended 6 days ago
        answers: ['Past test answer 1', 'Past test answer 2'],
        isAnonymous: false,
        realName: 'Test User Real Name',
      );

      await _firestore
          .collection(AttendanceModel.firebaseKey)
          .doc(attendanceId)
          .set(pastAttendance.toJson());

      print('Past test attendance created: $attendanceId');
      print('Past test data summary:');
      print('- Event ID: $eventId');
      print('- User ID: $userId');
      print('- Attendance ID: $attendanceId');
      print('- Event date: ${pastEvent.selectedDateTime}');
      print('- Attendance date: ${pastAttendance.attendanceDateTime}');

      // Test the getEventsAttendedByUser method
      print('=== Testing getEventsAttendedByUser method ===');
      List<EventModel> attendedEvents = await getEventsAttendedByUser(userId);
      print('Found ${attendedEvents.length} attended events for user $userId');

      for (var event in attendedEvents) {
        print('- Attended event: ${event.title} (ID: ${event.id})');
      }
    } catch (e) {
      print('Error creating past event and attendance: $e');
    }
  }

  // Get events attended by a user
  Future<List<EventModel>> getEventsAttendedByUser(String userId) async {
    try {
      print('=== DEBUG: Fetching events attended by user: $userId ===');

      // First, let's check if there are any attendance records at all
      final allAttendanceQuery = await _firestore
          .collection(AttendanceModel.firebaseKey)
          .get();
      print(
        'Total attendance records in database: ${allAttendanceQuery.docs.length}',
      );

      // Now get attendance records for this specific user
      final attendanceQuery = await _firestore
          .collection(AttendanceModel.firebaseKey)
          .where('customerUid', isEqualTo: userId)
          .get();
      print(
        'Found ${attendanceQuery.docs.length} attendance records for user $userId',
      );

      // Print all attendance records for debugging
      for (var doc in attendanceQuery.docs) {
        print('Attendance record: ${doc.data()}');
        print('Document ID: ${doc.id}');
        print('Event ID from record: ${doc.data()['eventId']}');
        print('Customer UID from record: ${doc.data()['customerUid']}');
      }

      // Also check if there are any attendance records at all for this user
      if (attendanceQuery.docs.isEmpty) {
        print('WARNING: No attendance records found for user $userId');
        print('This could mean:');
        print('1. User has never signed into any events');
        print('2. Attendance records are not being created properly');
        print('3. User ID mismatch');
        print('4. Firestore permissions issue');
        return [];
      }

      // Clean and extract event IDs from attendance records
      Set<String> cleanedEventIds = {};
      for (var doc in attendanceQuery.docs) {
        String rawEventId = doc['eventId'] as String;

        // Clean the event ID by taking the numeric part before '-'
        String cleanedEventId = _cleanEventId(rawEventId);
        cleanedEventIds.add(cleanedEventId);

        print('Raw event ID: $rawEventId -> Cleaned: $cleanedEventId');
      }

      final eventIds = cleanedEventIds.toList();
      print('Unique cleaned event IDs from attendance: $eventIds');

      // Also log attendance dates for debugging
      for (var doc in attendanceQuery.docs) {
        final attendanceDate = (doc.data()['attendanceDateTime'] as Timestamp)
            .toDate();
        print('Attended event ${doc.data()['eventId']} on ${attendanceDate}');
      }

      if (eventIds.isEmpty) {
        print('No events attended by user $userId');
        return [];
      }

      // Let's also check what events exist in the database
      final allEventsQuery = await _firestore
          .collection(EventModel.firebaseKey)
          .get();
      print('Total events in database: ${allEventsQuery.docs.length}');
      for (var doc in allEventsQuery.docs) {
        print('Event in database: ID=${doc['id']}, Title=${doc['title']}');
      }

      // Handle the case where we have more than 10 event IDs
      List<EventModel> allEvents = [];
      // Process event IDs in batches of 10 (Firestore limitation)
      for (int i = 0; i < eventIds.length; i += 10) {
        final batch = eventIds.skip(i).take(10).toList();
        print('Processing batch ${i ~/ 10 + 1}: $batch');

        // Use document IDs directly instead of querying by field
        for (String eventId in batch) {
          try {
            final eventDoc = await _firestore
                .collection(EventModel.firebaseKey)
                .doc(eventId)
                .get();
            if (eventDoc.exists) {
              print('Found event document for ID: $eventId');
              final eventData = eventDoc.data() as Map<String, dynamic>;

              // Check if the event is accessible to the user
              bool canAccessEvent = false;
              if (eventData.containsKey('customerUid')) {
                String eventOwnerId = eventData['customerUid'] as String;
                bool isPrivate = eventData['private'] ?? false;

                // User can access if they own the event or if it's public
                canAccessEvent = (eventOwnerId == userId) || !isPrivate;
                print(
                  'Event $eventId - Owner: $eventOwnerId, Private: $isPrivate, CanAccess: $canAccessEvent',
                );
              } else {
                // If no customerUid field, assume it's accessible
                canAccessEvent = true;
                print(
                  'Event $eventId - No customerUid field, assuming accessible',
                );
              }

              if (canAccessEvent) {
                // Check if the document has an 'id' field and if it matches the document ID
                if (eventData.containsKey('id')) {
                  final documentId = eventData['id'] as String;
                  if (documentId == eventId) {
                    try {
                      final event = EventModel.fromJson(eventData);
                      allEvents.add(event);
                      print('Successfully parsed event: ${event.title}');
                    } catch (e) {
                      print('Error parsing event document for ID $eventId: $e');
                      print('Document data: $eventData');
                    }
                  } else {
                    print(
                      'Document ID mismatch: expected $eventId, got $documentId',
                    );
                  }
                } else {
                  print('Document does not have an id field: $eventId');
                  // Try to create event with document ID as the id
                  try {
                    eventData['id'] = eventId;
                    final event = EventModel.fromJson(eventData);
                    allEvents.add(event);
                    print(
                      'Successfully parsed event with document ID: ${event.title}',
                    );
                  } catch (e) {
                    print('Error parsing event document for ID $eventId: $e');
                    print('Document data: $eventData');
                  }
                }
              } else {
                print(
                  'Skipping private event $eventId - user does not have access',
                );
              }
            } else {
              print('Event document not found for ID: $eventId');
            }
          } catch (e) {
            print('Error fetching event document for ID $eventId: $e');
            // Check if it's a permission error
            if (e.toString().contains('PERMISSION_DENIED')) {
              print(
                'PERMISSION_DENIED for event $eventId - this might be a private event',
              );
            }
          }
        }
        print('Successfully parsed ${allEvents.length} events so far');
      }

      print(
        '=== FINAL RESULT: Successfully parsed ${allEvents.length} total attended events ===',
      );
      return allEvents;
    } catch (e) {
      print('Error fetching attended events: $e');
      print('Stack trace: ${StackTrace.current}');
      // Check if it's a permission error
      if (e.toString().contains('PERMISSION_DENIED')) {
        print('PERMISSION_DENIED error - this might be due to Firestore rules');
        print(
          'Make sure the Attendance collection rules allow users to read their own records',
        );
      }
      return [];
    }
  }

  // Helper method to clean malformed event IDs
  String _cleanEventId(String rawEventId) {
    // If the event ID contains a dash, take only the part before the dash
    if (rawEventId.contains('-')) {
      String cleaned = rawEventId.split('-')[0];
      print('Cleaned event ID: $rawEventId -> $cleaned');
      return cleaned;
    }
    // If no dash, return as is
    return rawEventId;
  }

  // Method to fix existing malformed attendance records
  Future<void> fixMalformedAttendanceRecords(String userId) async {
    try {
      print(
        '=== DEBUG: Fixing malformed attendance records for user: $userId ===',
      );

      // Get all attendance records for the user
      final attendanceQuery = await _firestore
          .collection(AttendanceModel.firebaseKey)
          .where('customerUid', isEqualTo: userId)
          .get();

      print('Found ${attendanceQuery.docs.length} attendance records to check');

      int fixedCount = 0;
      for (var doc in attendanceQuery.docs) {
        String rawEventId = doc.data()['eventId'] as String;
        String cleanedEventId = _cleanEventId(rawEventId);

        // If the event ID needs cleaning
        if (rawEventId != cleanedEventId) {
          print('Fixing malformed event ID: $rawEventId -> $cleanedEventId');

          // Update the attendance record with the cleaned event ID
          await _firestore
              .collection(AttendanceModel.firebaseKey)
              .doc(doc.id)
              .update({'eventId': cleanedEventId});

          fixedCount++;
        }
      }

      print('Fixed $fixedCount malformed attendance records');
    } catch (e) {
      print('Error fixing malformed attendance records: $e');
    }
  }

  // Debug method to check if user has any attendance records
  Future<void> debugUserAttendance(String userId) async {
    try {
      print('=== DEBUG: Checking attendance for user: $userId ===');

      // Check all attendance records
      final allAttendanceQuery = await _firestore
          .collection(AttendanceModel.firebaseKey)
          .get();
      print(
        'Total attendance records in database: ${allAttendanceQuery.docs.length}',
      );

      // Show all attendance records
      for (var doc in allAttendanceQuery.docs) {
        print('Attendance record: ${doc.data()}');
      }

      // Check user-specific attendance
      final userAttendanceQuery = await _firestore
          .collection(AttendanceModel.firebaseKey)
          .where('customerUid', isEqualTo: userId)
          .get();
      print('User attendance records: ${userAttendanceQuery.docs.length}');

      for (var doc in userAttendanceQuery.docs) {
        print('User attendance: ${doc.data()}');
      }

      // Check if the user exists in Customers collection
      final userDoc = await _firestore
          .collection('Customers')
          .doc(userId)
          .get();
      print('User exists in Customers: ${userDoc.exists}');
      if (userDoc.exists) {
        print('User data: ${userDoc.data()}');
      }
    } catch (e) {
      print('Error in debugUserAttendance: $e');
    }
  }

  // Debug method to check if a specific event is accessible
  Future<void> debugEventAccess(String eventId, String userId) async {
    try {
      print(
        '=== DEBUG: Checking access to event: $eventId for user: $userId ===',
      );

      final eventDoc = await _firestore
          .collection(EventModel.firebaseKey)
          .doc(eventId)
          .get();

      if (eventDoc.exists) {
        final eventData = eventDoc.data() as Map<String, dynamic>;
        print('Event exists: ${eventData}');

        String eventOwnerId = eventData['customerUid'] ?? 'unknown';
        bool isPrivate = eventData['private'] ?? false;
        String eventTitle = eventData['title'] ?? 'No title';

        print('Event details:');
        print('- Title: $eventTitle');
        print('- Owner: $eventOwnerId');
        print('- Private: $isPrivate');
        print('- User ID: $userId');

        bool canAccess = (eventOwnerId == userId) || !isPrivate;
        print('- Can access: $canAccess');

        if (!canAccess) {
          print('User cannot access this event because:');
          if (isPrivate) {
            print('- Event is private');
          }
          if (eventOwnerId != userId) {
            print('- User is not the owner');
          }
        }
      } else {
        print('Event does not exist: $eventId');
      }
    } catch (e) {
      print('Error checking event access: $e');
    }
  }
}
