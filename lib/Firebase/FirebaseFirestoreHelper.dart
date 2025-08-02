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
  ///   allow read, write: if request.auth != null && request.auth.uid == customerId;
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

  Future<List<AttendanceModel>> getAttendance({
    required String eventId,
  }) async {
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
    final DocumentReference ref =
        _firestore.collection('Settings').doc('EventsSettings');

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
  Future<List<CommentModel>> getEventComments({
    required String eventId,
  }) async {
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
                content: Text('Failed to add comment: User not authenticated')),
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
            'Firestore add error: Event document does not exist for eventId: $eventId');
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Failed to add comment: Event does not exist')),
          );
        }
        return false;
      }

      String commentId =
          _firestore.collection(CommentModel.firebaseKey).doc().id;
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

  // Future<void> makeEventSignIn({required String eventId}) async {
  //   String docId = '$eventId-${CustomerController.logeInCustomer!.uid}';
  //   AttendanceModel newAttendanceMode = AttendanceModel(
  //     id: docId,
  //     eventId: eventId,
  //     userName: CustomerController.logeInCustomer!.name,
  //     customerUid: CustomerController.logeInCustomer!.uid,
  //     attendanceDateTime: DateTime.now(),
  //     answers: [],
  //   );
  //
  //   await FirebaseFirestore.instance
  //       .collection(AttendanceModel.firebaseKey)
  //       .doc(docId)
  //       .set(newAttendanceMode.toJson())
  //       .then((value) {
  //     ShowToast().showNormalToast(msg: 'Signed In Successful!');
  //   });
  // }

  // Get events created by a user
  Future<List<EventModel>> getEventsCreatedByUser(String userId) async {
    final query = await _firestore
        .collection(EventModel.firebaseKey)
        .where('customerUid', isEqualTo: userId)
        .get();
    return query.docs.map((doc) => EventModel.fromJson(doc.data())).toList();
  }

  // Get events attended by a user
  Future<List<EventModel>> getEventsAttendedByUser(String userId) async {
    final attendanceQuery = await _firestore
        .collection(AttendanceModel.firebaseKey)
        .where('customerUid', isEqualTo: userId)
        .get();
    final eventIds = attendanceQuery.docs
        .map((doc) => doc['eventId'] as String)
        .toSet()
        .toList();
    if (eventIds.isEmpty) return [];
    final eventsQuery = await _firestore
        .collection(EventModel.firebaseKey)
        .where('id',
            whereIn: eventIds.length > 10 ? eventIds.sublist(0, 10) : eventIds)
        .get();
    return eventsQuery.docs
        .map((doc) => EventModel.fromJson(doc.data()))
        .toList();
  }
}
