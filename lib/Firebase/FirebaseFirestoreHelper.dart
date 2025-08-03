import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:orgami/Controller/CustomerController.dart';
import 'package:orgami/Models/AttendanceModel.dart';
import 'package:orgami/Models/CommentModel.dart';
import 'package:orgami/Models/CustomerModel.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Models/EventQuestionModel.dart';
import 'package:orgami/Models/TicketModel.dart';

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
    print('Generating random event ID...');

    // Curated list of positive, memorable words
    const List<String> positiveWords = [
      'SUNNY',
      'HAPPY',
      'BRIGHT',
      'SHINE',
      'SPARK',
      'GLOW',
      'BEAM',
      'RISE',
      'PEACE',
      'JOY',
      'HOPE',
      'DREAM',
      'STAR',
      'MOON',
      'SKY',
      'OCEAN',
      'MOUNTAIN',
      'RIVER',
      'FOREST',
      'GARDEN',
      'FLOWER',
      'TREE',
      'BIRD',
      'DOLPHIN',
      'EAGLE',
      'LION',
      'TIGER',
      'BEAR',
      'WOLF',
      'FOX',
      'DEER',
      'MUSIC',
      'DANCE',
      'SING',
      'PLAY',
      'LAUGH',
      'SMILE',
      'FRIEND',
      'LOVE',
      'HEART',
      'SOUL',
      'MIND',
      'SPIRIT',
      'WISDOM',
      'POWER',
      'STRENGTH',
      'BRAVE',
      'BOLD',
      'SWIFT',
      'QUICK',
      'FAST',
      'SLOW',
      'GENTLE',
      'KIND',
      'WARM',
      'COOL',
      'FRESH',
      'NEW',
      'OLD',
      'YOUNG',
      'WISE',
      'CLEVER',
      'SMART',
      'BRIGHT',
      'SHARP',
      'FOCUS',
      'AIM',
      'GOAL',
      'DREAM',
      'PLAN',
      'BUILD',
      'CREATE',
      'MAKE',
      'DO',
      'GO',
      'COME',
      'STAY',
      'WAIT',
      'WATCH',
      'SEE',
      'LOOK',
      'FIND',
      'SEEK',
      'SEARCH',
      'EXPLORE',
      'DISCOVER',
    ];

    // Generate a word-based ID (Word-Number format)
    String generateWordBasedId() {
      final random = Random();
      final word = positiveWords[random.nextInt(positiveWords.length)];
      final number = random.nextInt(999) + 1; // 1-999
      return '$word-$number';
    }

    // Generate a random alphanumeric ID
    String generateRandomId() {
      final random = Random();
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      // Generate a 6-character alphanumeric ID
      return String.fromCharCodes(
        Iterable.generate(
          6,
          (_) => chars.codeUnitAt(random.nextInt(chars.length)),
        ),
      );
    }

    // Generate a random numeric ID (easier to share verbally)
    String generateNumericId() {
      final random = Random();
      // Generate a 6-digit number (100000 to 999999)
      int randomNumber = random.nextInt(900000) + 100000;
      return randomNumber.toString();
    }

    try {
      // Priority 1: Word-based IDs (most user-friendly)
      String randomId = generateWordBasedId();
      int attempts = 0;
      const maxAttempts = 20; // More attempts for word-based IDs

      // Check if the ID already exists
      while (attempts < maxAttempts) {
        DocumentSnapshot eventDoc = await _firestore
            .collection(EventModel.firebaseKey)
            .doc(randomId)
            .get();

        if (!eventDoc.exists) {
          // ID is unique, return it
          print('Generated unique word-based event ID: $randomId');
          return randomId;
        }

        // ID exists, generate a new one
        randomId = generateWordBasedId();
        attempts++;
      }

      // Priority 2: Numeric IDs (fallback for high volume)
      print('Could not generate unique word-based ID, trying numeric...');
      randomId = generateNumericId();
      attempts = 0;

      while (attempts < maxAttempts) {
        DocumentSnapshot eventDoc = await _firestore
            .collection(EventModel.firebaseKey)
            .doc(randomId)
            .get();

        if (!eventDoc.exists) {
          // ID is unique, return it
          print('Generated unique numeric event ID: $randomId');
          return randomId;
        }

        // ID exists, generate a new one
        randomId = generateNumericId();
        attempts++;
      }

      // Priority 3: Alphanumeric IDs
      print('Could not generate unique numeric ID, trying alphanumeric...');
      randomId = generateRandomId();
      attempts = 0;

      while (attempts < maxAttempts) {
        DocumentSnapshot eventDoc = await _firestore
            .collection(EventModel.firebaseKey)
            .doc(randomId)
            .get();

        if (!eventDoc.exists) {
          // ID is unique, return it
          print('Generated unique alphanumeric event ID: $randomId');
          return randomId;
        }

        // ID exists, generate a new one
        randomId = generateRandomId();
        attempts++;
      }

      // Final fallback: use timestamp-based ID
      print(
        'Could not generate unique ID after multiple attempts, using timestamp',
      );
      return DateTime.now().millisecondsSinceEpoch.toString();
    } catch (e) {
      print('Error generating event ID: $e');
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

  // Get events attended by a user - Optimized version
  Future<List<EventModel>> getEventsAttendedByUser(String userId) async {
    try {
      print('=== DEBUG: Fetching events attended by user: $userId ===');

      // Get attendance records for this specific user with timeout
      final attendanceQuery = await _firestore
          .collection(AttendanceModel.firebaseKey)
          .where('customerUid', isEqualTo: userId)
          .get()
          .timeout(const Duration(seconds: 10));

      print(
        'Found ${attendanceQuery.docs.length} attendance records for user $userId',
      );

      if (attendanceQuery.docs.isEmpty) {
        print('No attendance records found for user $userId');
        return [];
      }

      // Clean and extract event IDs from attendance records
      Set<String> cleanedEventIds = {};
      for (var doc in attendanceQuery.docs) {
        try {
          String rawEventId = doc['eventId'] as String;
          String cleanedEventId = _cleanEventId(rawEventId);
          cleanedEventIds.add(cleanedEventId);
        } catch (e) {
          print('Error processing attendance record: $e');
          continue;
        }
      }

      final eventIds = cleanedEventIds.toList();
      print('Unique cleaned event IDs from attendance: $eventIds');

      if (eventIds.isEmpty) {
        print('No valid event IDs found for user $userId');
        return [];
      }

      // Fetch events in parallel with timeout
      List<EventModel> allEvents = [];
      final futures = eventIds.map(
        (eventId) => _fetchEventSafely(eventId, userId),
      );

      final results = await Future.wait(
        futures,
        eagerError: false,
      ).timeout(const Duration(seconds: 15));

      for (var result in results) {
        if (result != null) {
          allEvents.add(result);
        }
      }

      print(
        '=== FINAL RESULT: Successfully parsed ${allEvents.length} total attended events ===',
      );
      return allEvents;
    } catch (e) {
      print('Error fetching attended events: $e');
      if (e.toString().contains('PERMISSION_DENIED')) {
        print('PERMISSION_DENIED error - check Firestore rules');
      }
      return [];
    }
  }

  // Safely fetch a single event with error handling
  Future<EventModel?> _fetchEventSafely(String eventId, String userId) async {
    try {
      final eventDoc = await _firestore
          .collection(EventModel.firebaseKey)
          .doc(eventId)
          .get()
          .timeout(const Duration(seconds: 5));

      if (!eventDoc.exists) {
        print('Event document not found for ID: $eventId');
        return null;
      }

      final eventData = eventDoc.data() as Map<String, dynamic>;

      // Check if the event is accessible to the user
      bool canAccessEvent = false;
      if (eventData.containsKey('customerUid')) {
        String eventOwnerId = eventData['customerUid'] as String;
        bool isPrivate = eventData['private'] ?? false;
        canAccessEvent = (eventOwnerId == userId) || !isPrivate;
      } else {
        canAccessEvent = true;
      }

      if (!canAccessEvent) {
        print('Skipping private event $eventId - user does not have access');
        return null;
      }

      // Ensure the document has an 'id' field
      if (!eventData.containsKey('id')) {
        eventData['id'] = eventId;
      }

      final event = EventModel.fromJson(eventData);
      return event;
    } catch (e) {
      print('Error fetching event $eventId: $e');
      return null;
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

  // Ticket-related methods
  Future<void> enableTicketsForEvent({
    required String eventId,
    required int maxTickets,
  }) async {
    try {
      await _firestore.collection(EventModel.firebaseKey).doc(eventId).update({
        'ticketsEnabled': true,
        'maxTickets': maxTickets,
        'issuedTickets': 0,
      });
    } catch (e) {
      print('Error enabling tickets for event: $e');
      rethrow;
    }
  }

  Future<void> disableTicketsForEvent({required String eventId}) async {
    try {
      await _firestore.collection(EventModel.firebaseKey).doc(eventId).update({
        'ticketsEnabled': false,
        'maxTickets': 0,
        'issuedTickets': 0,
      });
    } catch (e) {
      print('Error disabling tickets for event: $e');
      rethrow;
    }
  }

  Future<TicketModel?> issueTicket({
    required String eventId,
    required String customerUid,
    required String customerName,
    required EventModel eventModel,
  }) async {
    try {
      print('=== TICKET ISSUANCE DEBUG ===');
      print('Event ID: $eventId');
      print('Customer UID: $customerUid');
      print('Customer Name: $customerName');

      // First, check if tickets are enabled and available
      final eventDoc = await _firestore
          .collection(EventModel.firebaseKey)
          .doc(eventId)
          .get();

      if (!eventDoc.exists) {
        throw Exception('Event not found');
      }

      final eventData = eventDoc.data() as Map<String, dynamic>;
      final ticketsEnabled = eventData['ticketsEnabled'] ?? false;
      final maxTickets = eventData['maxTickets'] ?? 0;
      final issuedTickets = eventData['issuedTickets'] ?? 0;

      print('Event data:');
      print('- Tickets enabled: $ticketsEnabled');
      print('- Max tickets: $maxTickets');
      print('- Issued tickets: $issuedTickets');

      if (!ticketsEnabled) {
        throw Exception('Tickets are not enabled for this event');
      }

      if (issuedTickets >= maxTickets) {
        throw Exception('No tickets available for this event');
      }

      // Check if user already has a ticket for this event
      final existingTicketQuery = await _firestore
          .collection(TicketModel.firebaseKey)
          .where('eventId', isEqualTo: eventId)
          .where('customerUid', isEqualTo: customerUid)
          .get();

      print(
        'Existing tickets for this user: ${existingTicketQuery.docs.length}',
      );

      // Debug: Print details of existing tickets
      for (var doc in existingTicketQuery.docs) {
        final ticketData = doc.data();
        print('Existing ticket: ${ticketData}');
      }

      // Only block if user has an active (unused) ticket
      final activeTickets = existingTicketQuery.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['isUsed'] != true;
      }).toList();

      print('Active tickets for this user: ${activeTickets.length}');

      if (activeTickets.isNotEmpty) {
        throw Exception('You already have a ticket for this event');
      }

      // Generate ticket
      final ticketId = _firestore.collection(TicketModel.firebaseKey).doc().id;
      final ticketCode = TicketModel.generateTicketCode();

      final ticket = TicketModel(
        id: ticketId,
        eventId: eventId,
        eventTitle: eventModel.title,
        eventImageUrl: eventModel.imageUrl,
        eventLocation: eventModel.location,
        eventDateTime: eventModel.selectedDateTime,
        customerUid: customerUid,
        customerName: customerName,
        ticketCode: ticketCode,
        issuedDateTime: DateTime.now(),
      );

      print('Creating ticket with ID: $ticketId');
      print('Ticket code: $ticketCode');

      // Save ticket
      await _firestore
          .collection(TicketModel.firebaseKey)
          .doc(ticketId)
          .set(ticket.toJson());

      print('Ticket created successfully');

      // Update event ticket count
      await _firestore.collection(EventModel.firebaseKey).doc(eventId).update({
        'issuedTickets': issuedTickets + 1,
      });

      print('Event ticket count updated');

      return ticket;
    } catch (e) {
      print('Error issuing ticket: $e');
      rethrow;
    }
  }

  Future<List<TicketModel>> getUserTickets({
    required String customerUid,
  }) async {
    try {
      final querySnapshot = await _firestore
          .collection(TicketModel.firebaseKey)
          .where('customerUid', isEqualTo: customerUid)
          .orderBy('issuedDateTime', descending: true)
          .get();

      return querySnapshot.docs.map((doc) {
        return TicketModel.fromJson(doc);
      }).toList();
    } catch (e) {
      print('Error getting user tickets: $e');
      return [];
    }
  }

  Future<List<TicketModel>> getEventTickets({required String eventId}) async {
    try {
      final querySnapshot = await _firestore
          .collection(TicketModel.firebaseKey)
          .where('eventId', isEqualTo: eventId)
          .orderBy('issuedDateTime', descending: true)
          .get();

      return querySnapshot.docs.map((doc) {
        return TicketModel.fromJson(doc);
      }).toList();
    } catch (e) {
      print('Error getting event tickets: $e');
      return [];
    }
  }

  Future<void> useTicket({
    required String ticketId,
    required String usedBy,
  }) async {
    try {
      await _firestore.collection(TicketModel.firebaseKey).doc(ticketId).update(
        {'isUsed': true, 'usedDateTime': DateTime.now(), 'usedBy': usedBy},
      );
    } catch (e) {
      print('Error using ticket: $e');
      rethrow;
    }
  }

  Future<TicketModel?> getTicketByCode({required String ticketCode}) async {
    try {
      final querySnapshot = await _firestore
          .collection(TicketModel.firebaseKey)
          .where('ticketCode', isEqualTo: ticketCode)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return TicketModel.fromJson(querySnapshot.docs.first);
      }
      return null;
    } catch (e) {
      print('Error getting ticket by code: $e');
      return null;
    }
  }

  // Debug method to clear all tickets for a user (for testing)
  Future<void> clearUserTickets({
    required String customerUid,
    String? eventId,
  }) async {
    try {
      Query query = _firestore
          .collection(TicketModel.firebaseKey)
          .where('customerUid', isEqualTo: customerUid);

      if (eventId != null) {
        query = query.where('eventId', isEqualTo: eventId);
      }

      final querySnapshot = await query.get();

      for (var doc in querySnapshot.docs) {
        await doc.reference.delete();
      }

      print(
        'Cleared ${querySnapshot.docs.length} tickets for user: $customerUid',
      );
    } catch (e) {
      print('Error clearing user tickets: $e');
      rethrow;
    }
  }
}
