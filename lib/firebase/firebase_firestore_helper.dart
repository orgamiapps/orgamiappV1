import 'dart:math' as math;
import 'dart:math' show Random;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/models/attendance_model.dart';
import 'package:attendus/models/comment_model.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/models/event_question_model.dart';
import 'package:attendus/models/ticket_model.dart';
import 'package:attendus/models/event_feedback_model.dart';
import 'package:attendus/models/app_feedback_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:attendus/firebase/firebase_messaging_helper.dart';
import 'package:attendus/Services/on_device_nlp_service.dart';

class FirebaseFirestoreHelper {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _functionsRegion = 'us-central1';

  // Cache for frequently accessed data
  static final Map<String, dynamic> _cache = {};
  static const Duration _cacheExpiry = Duration(minutes: 5);

  // ===== On-Device AI Natural Language Event Search =====
  Future<List<EventModel>> aiSearchEvents({
    required String query,
    double? latitude,
    double? longitude,
    int limit = 50,
  }) async {
    try {
      // Use on-device NLP service instead of cloud function
      final nlpService = OnDeviceNLPService.instance;
      final intent = await nlpService.parseQuery(query);

      Logger.debug('Parsed query intent: $intent');

      // Build Firestore query based on parsed intent
      return await _searchEventsWithIntent(intent, latitude, longitude, limit);
    } catch (e) {
      Logger.error('Error with on-device AI search', e);
      // Fallback to simple text search
      return await _fallbackTextSearch(query, limit);
    }
  }

  /// Search events using parsed intent from on-device AI
  Future<List<EventModel>> _searchEventsWithIntent(
    Map<String, dynamic> intent,
    double? latitude,
    double? longitude,
    int limit,
  ) async {
    final categories = intent['categories'] as List<String>? ?? [];
    final keywords = intent['keywords'] as List<String>? ?? [];
    final nearMe = intent['nearMe'] as bool? ?? false;
    final radiusKm = intent['radiusKm'] as double? ?? 0.0;
    final dateRange = intent['dateRange'] as Map<String, String>? ?? {};

    // Build base timeframe
    final now = DateTime.now();
    final start = dateRange['start'] != null
        ? DateTime.parse(dateRange['start']!)
        : now.subtract(const Duration(hours: 3));
    final end = dateRange['end'] != null
        ? DateTime.parse(dateRange['end']!)
        : now.add(const Duration(days: 60));

    // Query public events within timeframe
    Query query = _firestore
        .collection(EventModel.firebaseKey)
        .where('private', isEqualTo: false)
        .where(
          'selectedDateTime',
          isGreaterThanOrEqualTo: Timestamp.fromDate(start),
        )
        .where('selectedDateTime', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('selectedDateTime')
        .limit(limit * 2); // Get more for filtering

    final snapshot = await query.get();
    List<EventModel> events = snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      data['id'] = data['id'] ?? doc.id;
      return EventModel.fromJson(data);
    }).toList();

    // Apply category filtering
    if (categories.isNotEmpty) {
      events = events.where((event) {
        final eventCategories = event.categories
            .map((c) => c.toLowerCase())
            .toList();
        return categories.any(
          (category) =>
              eventCategories.any((ec) => ec.contains(category.toLowerCase())),
        );
      }).toList();
    }

    // Apply keyword filtering
    if (keywords.isNotEmpty) {
      events = events.where((event) {
        final searchText =
            '${event.title} ${event.description} ${event.location}'
                .toLowerCase();
        return keywords.any(
          (keyword) => searchText.contains(keyword.toLowerCase()),
        );
      }).toList();
    }

    // Apply location filtering
    if (nearMe && latitude != null && longitude != null && radiusKm > 0) {
      events = events.where((event) {
        if (event.latitude == 0.0 && event.longitude == 0.0) return false;
        final distance = _calculateDistance(
          latitude,
          longitude,
          event.latitude,
          event.longitude,
        );
        return distance <= radiusKm;
      }).toList();
    }

    // Sort: featured first, then by distance (if location search), then by date
    events.sort((a, b) {
      // Featured events first
      if (a.isFeatured && !b.isFeatured) return -1;
      if (!a.isFeatured && b.isFeatured) return 1;

      // If location search, sort by distance
      if (nearMe && latitude != null && longitude != null) {
        final distA = _calculateDistance(
          latitude,
          longitude,
          a.latitude,
          a.longitude,
        );
        final distB = _calculateDistance(
          latitude,
          longitude,
          b.latitude,
          b.longitude,
        );
        final distComparison = distA.compareTo(distB);
        if (distComparison != 0) return distComparison;
      }

      // Finally sort by date
      return a.selectedDateTime.compareTo(b.selectedDateTime);
    });

    // Limit results
    return events.take(limit).toList();
  }

  /// Calculate distance between two points in kilometers
  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371; // km
    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);
    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  /// Fallback text search when AI parsing fails
  Future<List<EventModel>> _fallbackTextSearch(String query, int limit) async {
    final queryLower = query.toLowerCase();
    final now = DateTime.now();

    Query firestoreQuery = _firestore
        .collection(EventModel.firebaseKey)
        .where('private', isEqualTo: false)
        .where(
          'selectedDateTime',
          isGreaterThan: now.subtract(const Duration(hours: 3)),
        )
        .orderBy('selectedDateTime')
        .limit(limit);

    final snapshot = await firestoreQuery.get();
    List<EventModel> events = snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      data['id'] = data['id'] ?? doc.id;
      return EventModel.fromJson(data);
    }).toList();

    // Filter by text matching
    events = events.where((event) {
      final searchText = '${event.title} ${event.description} ${event.location}'
          .toLowerCase();
      return searchText.contains(queryLower);
    }).toList();

    return events;
  }

  /// UGC: Report content or user
  Future<void> submitUserReport({
    required String type, // user|message|comment|event
    String? targetUserId,
    String? contentId,
    String? reason,
    String? details,
  }) async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: _functionsRegion);
      final callable = functions.httpsCallable('submitUserReport');
      await callable.call({
        'type': type,
        'targetUserId': targetUserId,
        'contentId': contentId,
        'reason': reason,
        'details': details,
      });
    } catch (e) {
      Logger.error('Error submitting report', e);
      rethrow;
    }
  }

  /// UGC: Block a user (mutual exclusion in conversations/feeds client-side)
  Future<void> blockUser({
    required String blockerId,
    required String blockedUserId,
  }) async {
    try {
      await _firestore
          .collection('Customers')
          .doc(blockerId)
          .collection('blocks')
          .doc(blockedUserId)
          .set({'blockedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      Logger.error('Error blocking user', e);
      rethrow;
    }
  }

  Future<void> unblockUser({
    required String blockerId,
    required String blockedUserId,
  }) async {
    try {
      await _firestore
          .collection('Customers')
          .doc(blockerId)
          .collection('blocks')
          .doc(blockedUserId)
          .delete();
    } catch (e) {
      Logger.error('Error unblocking user', e);
      rethrow;
    }
  }

  Future<bool> isUserBlocked({
    required String blockerId,
    required String otherUserId,
  }) async {
    try {
      final doc = await _firestore
          .collection('Customers')
          .doc(blockerId)
          .collection('blocks')
          .doc(otherUserId)
          .get();
      return doc.exists;
    } catch (e) {
      Logger.error('Error checking block status', e);
      return false;
    }
  }

  /// Retrieves a single customer from Firestore with caching
  ///
  /// IMPORTANT: Ensure Firestore security rules allow read access for authenticated users:
  /// match /Customers/{customerId} {
  /// allow read, write: if request.auth != null && request.auth.uid == customerId;
  /// }
  ///
  /// This method handles PERMISSION_DENIED errors gracefully by returning null
  /// instead of throwing exceptions, allowing the app to continue functioning.
  Future<CustomerModel?> getSingleCustomer({required String customerId}) async {
    // Check cache first
    final cacheKey = 'customer_$customerId';
    final cachedData = _cache[cacheKey];
    if (cachedData != null) {
      final timestamp = cachedData['timestamp'] as DateTime;
      if (DateTime.now().difference(timestamp) < _cacheExpiry) {
        Logger.debug('Using cached customer data for: $customerId');
        return cachedData['data'] as CustomerModel;
      }
    }

    try {
      // Get from Firestore (primary collection)
      final doc = await _firestore
          .collection('Customers')
          .doc(customerId)
          .get();

      if (doc.exists) {
        final customer = CustomerModel.fromFirestore(doc);

        // Cache the result
        _cache[cacheKey] = {'data': customer, 'timestamp': DateTime.now()};

        return customer;
      }

      // Fallback: legacy collection name support ('Customer')
      try {
        final legacyDoc = await _firestore
            .collection('Customer')
            .doc(customerId)
            .get();

        if (legacyDoc.exists) {
          final legacyCustomer = CustomerModel.fromFirestore(legacyDoc);

          // Migrate to current collection name for consistency
          await _firestore
              .collection('Customers')
              .doc(customerId)
              .set(
                CustomerModel.getMap(legacyCustomer),
                SetOptions(merge: true),
              );

          // Cache and return
          _cache[cacheKey] = {
            'data': legacyCustomer,
            'timestamp': DateTime.now(),
          };
          Logger.debug(
            'Migrated legacy user document to \'Customers\' for: $customerId',
          );
          return legacyCustomer;
        }
      } catch (e) {
        Logger.debug('Legacy collection lookup failed for $customerId: $e');
      }

      Logger.warning('Customer document not found: $customerId');
      return null;
    } catch (e) {
      Logger.error('Error getting customer data', e);
      return null;
    }
  }

  // Soft-delete user (mark as deleted). For full deletion, implement a Cloud Function.
  Future<void> markUserAsDeleted(String userId) async {
    try {
      await _firestore.collection('Customers').doc(userId).set({
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      Logger.error('Error marking user as deleted', e);
      rethrow;
    }
  }

  // Fully delete account via Cloud Function (recommended for App Store compliance)
  Future<void> deleteAccountViaCloudFunction(String userId) async {
    try {
      // Use callable function to perform server-side deletion
      final functions = FirebaseFunctions.instanceFor(region: _functionsRegion);
      final callable = functions.httpsCallable('deleteUserAccount');
      await callable.call(<String, dynamic>{});
    } catch (e) {
      Logger.error('Error calling deleteUserAccount function', e);
      rethrow;
    }
  }

  // Clear cache
  static void clearCache() {
    _cache.clear();
  }

  // Update customer data
  Future<void> updateCustomerData(
    String customerId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _firestore.collection('Customers').doc(customerId).update(data);

      // Clear cache for this customer
      try {
        _cache.remove('customer_$customerId');
      } catch (_) {}
    } catch (e) {
      Logger.error('Error updating customer data', e);
      rethrow;
    }
  }

  Future<List<AttendanceModel>> getAttendance({required String eventId}) async {
    // Check cache first
    final cacheKey = 'attendance_$eventId';
    final cachedData = _cache[cacheKey];
    if (cachedData != null && cachedData['timestamp'] != null) {
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(
        cachedData['timestamp'],
      );
      if (DateTime.now().difference(cacheTime) < _cacheExpiry) {
        Logger.debug('Using cached attendance data for event: $eventId');
        return cachedData['data'] as List<AttendanceModel>;
      }
    }

    QuerySnapshot querySnapshot = await _firestore
        .collection(AttendanceModel.firebaseKey)
        .where('eventId', isEqualTo: eventId)
        .get();
    List<AttendanceModel> list = querySnapshot.docs.map((doc) {
      return AttendanceModel.fromJson(doc);
    }).toList();

    // Cache the result
    _cache[cacheKey] = {
      'data': list,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    Logger.debug('Attendance data length: ${list.length}');
    return list;
  }

  Future<List<AttendanceModel>> getRegisterAttendance({
    required String eventId,
  }) async {
    // Check cache first
    final cacheKey = 'register_attendance_$eventId';
    final cachedData = _cache[cacheKey];
    if (cachedData != null && cachedData['timestamp'] != null) {
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(
        cachedData['timestamp'],
      );
      if (DateTime.now().difference(cacheTime) < _cacheExpiry) {
        Logger.debug(
          '📦 Using cached register attendance data for event: $eventId',
        );
        return cachedData['data'] as List<AttendanceModel>;
      }
    }

    QuerySnapshot querySnapshot = await _firestore
        .collection(AttendanceModel.registerFirebaseKey)
        .where('eventId', isEqualTo: eventId)
        .get();
    List<AttendanceModel> list = querySnapshot.docs.map((doc) {
      return AttendanceModel.fromJson(doc);
    }).toList();

    // Cache the result
    _cache[cacheKey] = {
      'data': list,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    Logger.debug('list Data length is ${list.length}');
    return list;
  }

  Future<List<EventQuestionModel>> getEventQuestions({
    required String eventId,
  }) async {
    // Check cache first
    final cacheKey = 'event_questions_$eventId';
    final cachedData = _cache[cacheKey];
    if (cachedData != null && cachedData['timestamp'] != null) {
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(
        cachedData['timestamp'],
      );
      if (DateTime.now().difference(cacheTime) < _cacheExpiry) {
        Logger.debug('📦 Using cached event questions for event: $eventId');
        return cachedData['data'] as List<EventQuestionModel>;
      }
    }

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

      // Cache the result
      _cache[cacheKey] = {
        'data': list,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      Logger.debug('list Data length is ${list.length}');
    } catch (e) {
      // Handle permission denied and other Firestore errors
      Logger.error('Error fetching event questions for event: $eventId', e);
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
    Logger.debug('list Data length is ${list.length}');
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
    Logger.debug('list Data length is ${list.length}');
    return list.isNotEmpty ? true : false;
  }

  Future<bool> unregisterFromEvent(String eventId) async {
    try {
      QuerySnapshot querySnapshot = await _firestore
          .collection(AttendanceModel.registerFirebaseKey)
          .where('eventId', isEqualTo: eventId)
          .where(
            'customerUid',
            isEqualTo: CustomerController.logeInCustomer!.uid,
          )
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        // Delete all registration records for this user and event
        for (var doc in querySnapshot.docs) {
          await doc.reference.delete();
        }

        // Clear cache for this event's registration data
        _cache.remove('register_attendance_$eventId');

        Logger.debug('Successfully unregistered user from event: $eventId');
        return true;
      }

      Logger.debug('No registration found to remove for event: $eventId');
      return false;
    } catch (e) {
      Logger.error('Error unregistering from event: $eventId', e);
      rethrow;
    }
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
      Logger.error('Error fetching event: $eventId', e);
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
    Logger.debug('Generating random event ID...');

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

    try {
      // Avoid Firestore reads (blocked by rules for non-existent docs).
      // Compose a robust, low-collision ID locally.
      final wordId = generateWordBasedId(); // e.g. DISCOVER-585
      final suffix = generateRandomId().substring(0, 2); // e.g. AB
      final candidate = '$wordId$suffix'; // e.g. DISCOVER-585AB
      Logger.success('Generated event ID (no read): $candidate');
      return candidate;
    } catch (e) {
      Logger.error('Error generating event ID: $e', e);
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
    String? bannerUrl,
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
      if (bannerUrl != null) {
        updateData['bannerUrl'] = bannerUrl;
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
      Logger.error('Error updating customer profile: $e', e);
      return false;
    }
  }

  // Get comments for an event
  Future<List<CommentModel>> getEventComments({required String eventId}) async {
    try {
      Logger.debug('Fetching comments for event: $eventId');
      QuerySnapshot querySnapshot = await _firestore
          .collection(CommentModel.firebaseKey)
          .where('eventId', isEqualTo: eventId)
          .orderBy('createdAt', descending: true)
          .get();
      Logger.debug('Found ${querySnapshot.docs.length} comment documents');
      List<CommentModel> comments = querySnapshot.docs.map((doc) {
        Logger.debug('Processing comment doc: ${doc.id}');
        return CommentModel.fromFirestore(doc);
      }).toList();
      Logger.debug('Processed ${comments.length} comments');
      return comments;
    } catch (e) {
      Logger.error('Error getting comments: $e', e);
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
        Logger.warning('Firestore add error: Comment is empty');
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
        Logger.warning('Firestore add error: User not authenticated');
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
        Logger.warning(
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
      Logger.debug('Generated comment ID: $commentId');

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
      Logger.debug('Comment payload: $payload');

      await _firestore
          .collection(CommentModel.firebaseKey)
          .doc(commentId)
          .set(payload);
      Logger.success('Comment successfully saved to Firestore');
      return true;
    } catch (e) {
      Logger.error('Firestore add error: $e', e);
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
      Logger.success('Manual attendance added: ${attendance.userName}');

      // Invalidate cached attendance for this event so UI refresh picks up the new record
      try {
        final cacheKey = 'attendance_${attendance.eventId}';
        _cache.remove(cacheKey);
      } catch (_) {
        // Ignore cache errors
      }
    } catch (e) {
      Logger.error('Error adding manual attendance: $e', e);
      rethrow;
    }
  }

  // Get attendance by user and event
  Future<AttendanceModel?> getAttendanceByUserAndEvent({
    required String customerUid,
    required String eventId,
  }) async {
    try {
      final querySnapshot = await _firestore
          .collection(AttendanceModel.firebaseKey)
          .where('customerUid', isEqualTo: customerUid)
          .where('eventId', isEqualTo: eventId)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return AttendanceModel.fromJson(querySnapshot.docs.first);
      }
      return null;
    } catch (e) {
      Logger.error('Error getting attendance by user and event: $e', e);
      return null;
    }
  }

  // Get events created by a user - OPTIMIZED with pagination support
  Future<List<EventModel>> getEventsCreatedByUser(
    String userId, {
    int? limit,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      Logger.debug(
        'Fetching events created by user: $userId (limit: ${limit ?? "none"})',
      );
      
      // PERFORMANCE: Add limit and ordering for faster queries
      Query query = _firestore
          .collection(EventModel.firebaseKey)
          .where('customerUid', isEqualTo: userId)
          .orderBy('created_at', descending: true); // Most recent first
      
      if (limit != null) {
        query = query.limit(limit);
      }
      
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }
      
      // PERFORMANCE: Add timeout to prevent hanging
      final querySnapshot = await query.get().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          Logger.warning('Query timed out, returning empty results');
          throw TimeoutException('getEventsCreatedByUser timed out');
        },
      );
      
      Logger.debug('Found ${querySnapshot.docs.length} events created by user');
      
      final events = querySnapshot.docs
          .map((doc) {
            try {
              // Add document ID to data before parsing
              final data = doc.data();
              data['id'] = data['id'] ?? doc.id;
              return EventModel.fromJson(data);
            } catch (e) {
              Logger.error('Error parsing event document ${doc.id}: $e', e);
              return null;
            }
          })
          .where((event) => event != null)
          .cast<EventModel>()
          .toList();
      Logger.debug('Successfully parsed ${events.length} events');
      return events;
    } catch (e) {
      Logger.error('Error fetching created events: $e', e);
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
      Logger.debug('Adding test attendance: $docId');
      Logger.debug('Test attendance data: ${testAttendance.toJson()}');
      await _firestore
          .collection(AttendanceModel.firebaseKey)
          .doc(docId)
          .set(testAttendance.toJson());
      Logger.success('Test attendance added successfully: $docId');
    } catch (e) {
      Logger.error('Error adding test attendance: $e', e);
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
      Logger.success('Test event created: $eventId (Public: true)');
      return eventId;
    } catch (e) {
      Logger.error('Error creating test event: $e', e);
      return '';
    }
  }

  // Comprehensive test method to create test data for debugging attended events
  Future<void> createTestDataForAttendedEvents(String userId) async {
    try {
      Logger.debug('=== Creating test data for attended events debugging ===');

      // Create a test event
      String eventId = await createTestEvent();
      if (eventId.isEmpty) {
        Logger.warning('Failed to create test event');
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

      Logger.success('Test attendance created: $attendanceId');
      Logger.debug('Test data summary:');
      Logger.debug('- Event ID: $eventId');
      Logger.debug('- User ID: $userId');
      Logger.debug('- Attendance ID: $attendanceId');
      Logger.debug('- Attendance data: ${testAttendance.toJson()}');

      // Verify the data was created
      final attendanceDoc = await _firestore
          .collection(AttendanceModel.firebaseKey)
          .doc(attendanceId)
          .get();

      if (attendanceDoc.exists) {
        Logger.debug('✓ Attendance record verified in database');
      } else {
        Logger.debug('✗ Attendance record not found in database');
      }

      final eventDoc = await _firestore
          .collection(EventModel.firebaseKey)
          .doc(eventId)
          .get();

      if (eventDoc.exists) {
        Logger.debug('✓ Event record verified in database');
      } else {
        Logger.debug('✗ Event record not found in database');
      }
    } catch (e) {
      Logger.debug('Error creating test data: $e');
    }
  }

  // Test method to create a past event and attendance
  Future<void> createPastEventAndAttendance(String userId) async {
    try {
      Logger.debug('=== Creating past event and attendance for debugging ===');

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
      Logger.debug('Past test event created: $eventId');

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

      Logger.debug('Past test attendance created: $attendanceId');
      Logger.debug('Past test data summary:');
      Logger.debug('- Event ID: $eventId');
      Logger.debug('- User ID: $userId');
      Logger.debug('- Attendance ID: $attendanceId');
      Logger.debug('- Event date: ${pastEvent.selectedDateTime}');
      Logger.debug('- Attendance date: ${pastAttendance.attendanceDateTime}');

      // Test the getEventsAttendedByUser method
      Logger.debug('=== Testing getEventsAttendedByUser method ===');
      List<EventModel> attendedEvents = await getEventsAttendedByUser(userId);
      Logger.debug(
        'Found ${attendedEvents.length} attended events for user $userId',
      );

      for (var event in attendedEvents) {
        Logger.debug('- Attended event: ${event.title} (ID: ${event.id})');
      }
    } catch (e) {
      Logger.debug('Error creating past event and attendance: $e');
    }
  }

  // Get events attended by a user - Optimized version
  Future<List<EventModel>> getEventsAttendedByUser(String userId) async {
    try {
      Logger.debug('=== DEBUG: Fetching events attended by user: $userId ===');

      // Get attendance records for this specific user with timeout
      final attendanceQuery = await _firestore
          .collection(AttendanceModel.firebaseKey)
          .where('customerUid', isEqualTo: userId)
          .get()
          .timeout(const Duration(seconds: 3));

      Logger.debug(
        'Found ${attendanceQuery.docs.length} attendance records for user $userId',
      );

      if (attendanceQuery.docs.isEmpty) {
        Logger.debug('No attendance records found for user $userId');
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
          Logger.debug('Error processing attendance record: $e');
          continue;
        }
      }

      final eventIds = cleanedEventIds.toList();
      Logger.debug('Unique cleaned event IDs from attendance: $eventIds');

      if (eventIds.isEmpty) {
        Logger.debug('No valid event IDs found for user $userId');
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
      ).timeout(const Duration(seconds: 5));

      for (var result in results) {
        if (result != null) {
          allEvents.add(result);
        }
      }

      Logger.debug(
        '=== FINAL RESULT: Successfully parsed ${allEvents.length} total attended events ===',
      );
      return allEvents;
    } catch (e) {
      Logger.debug('Error fetching attended events: $e');
      if (e.toString().contains('PERMISSION_DENIED')) {
        Logger.debug('PERMISSION_DENIED error - check Firestore rules');
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
          .timeout(const Duration(seconds: 2));

      if (!eventDoc.exists) {
        Logger.debug('Event document not found for ID: $eventId');
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
        Logger.debug(
          'Skipping private event $eventId - user does not have access',
        );
        return null;
      }

      // Ensure the document has an 'id' field
      if (!eventData.containsKey('id')) {
        eventData['id'] = eventId;
      }

      final event = EventModel.fromJson(eventData);
      return event;
    } catch (e) {
      Logger.debug('Error fetching event $eventId: $e');
      return null;
    }
  }

  // Helper method to clean malformed event IDs
  String _cleanEventId(String rawEventId) {
    // If the event ID contains a dash, take only the part before the dash
    if (rawEventId.contains('-')) {
      String cleaned = rawEventId.split('-')[0];
      Logger.debug('Cleaned event ID: $rawEventId -> $cleaned');
      return cleaned;
    }
    // If no dash, return as is
    return rawEventId;
  }

  // Method to fix existing malformed attendance records
  Future<void> fixMalformedAttendanceRecords(String userId) async {
    try {
      Logger.debug(
        '=== DEBUG: Fixing malformed attendance records for user: $userId ===',
      );

      // Get all attendance records for the user
      final attendanceQuery = await _firestore
          .collection(AttendanceModel.firebaseKey)
          .where('customerUid', isEqualTo: userId)
          .get();

      Logger.debug(
        'Found ${attendanceQuery.docs.length} attendance records to check',
      );

      int fixedCount = 0;
      for (var doc in attendanceQuery.docs) {
        String rawEventId = doc.data()['eventId'] as String;
        String cleanedEventId = _cleanEventId(rawEventId);

        // If the event ID needs cleaning
        if (rawEventId != cleanedEventId) {
          Logger.debug(
            'Fixing malformed event ID: $rawEventId -> $cleanedEventId',
          );

          // Update the attendance record with the cleaned event ID
          await _firestore
              .collection(AttendanceModel.firebaseKey)
              .doc(doc.id)
              .update({'eventId': cleanedEventId});

          fixedCount++;
        }
      }

      Logger.debug('Fixed $fixedCount malformed attendance records');
    } catch (e) {
      Logger.debug('Error fixing malformed attendance records: $e');
    }
  }

  // Debug method to check if user has any attendance records
  Future<void> debugUserAttendance(String userId) async {
    try {
      Logger.debug('=== DEBUG: Checking attendance for user: $userId ===');

      // Check all attendance records
      final allAttendanceQuery = await _firestore
          .collection(AttendanceModel.firebaseKey)
          .get();
      Logger.debug(
        'Total attendance records in database: ${allAttendanceQuery.docs.length}',
      );

      // Show all attendance records
      for (var doc in allAttendanceQuery.docs) {
        Logger.debug('Attendance record: ${doc.data()}');
      }

      // Check user-specific attendance
      final userAttendanceQuery = await _firestore
          .collection(AttendanceModel.firebaseKey)
          .where('customerUid', isEqualTo: userId)
          .get();
      Logger.debug(
        'User attendance records: ${userAttendanceQuery.docs.length}',
      );

      for (var doc in userAttendanceQuery.docs) {
        Logger.debug('User attendance: ${doc.data()}');
      }

      // Check if the user exists in Customers collection
      final userDoc = await _firestore
          .collection('Customers')
          .doc(userId)
          .get();
      Logger.debug('User exists in Customers: ${userDoc.exists}');
      if (userDoc.exists) {
        Logger.debug('User data: ${userDoc.data()}');
      }
    } catch (e) {
      Logger.debug('Error in debugUserAttendance: $e');
    }
  }

  // Debug method to check if a specific event is accessible
  Future<void> debugEventAccess(String eventId, String userId) async {
    try {
      Logger.debug(
        '=== DEBUG: Checking access to event: $eventId for user: $userId ===',
      );

      final eventDoc = await _firestore
          .collection(EventModel.firebaseKey)
          .doc(eventId)
          .get();

      if (eventDoc.exists) {
        final eventData = eventDoc.data() as Map<String, dynamic>;
        Logger.debug('Event exists: $eventData');

        String eventOwnerId = eventData['customerUid'] ?? 'unknown';
        bool isPrivate = eventData['private'] ?? false;
        String eventTitle = eventData['title'] ?? 'No title';

        Logger.debug('Event details:');
        Logger.debug('- Title: $eventTitle');
        Logger.debug('- Owner: $eventOwnerId');
        Logger.debug('- Private: $isPrivate');
        Logger.debug('- User ID: $userId');

        bool canAccess = (eventOwnerId == userId) || !isPrivate;
        Logger.debug('- Can access: $canAccess');

        if (!canAccess) {
          Logger.debug('User cannot access this event because:');
          if (isPrivate) {
            Logger.debug('- Event is private');
          }
          if (eventOwnerId != userId) {
            Logger.debug('- User is not the owner');
          }
        }
      } else {
        Logger.debug('Event does not exist: $eventId');
      }
    } catch (e) {
      Logger.debug('Error checking event access: $e');
    }
  }

  // Ticket-related methods
  Future<void> enableTicketsForEvent({
    required String eventId,
    required int maxTickets,
    double? ticketPrice,
    bool ticketUpgradeEnabled = false,
    double? ticketUpgradePrice,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'ticketsEnabled': true,
        'maxTickets': maxTickets,
        'issuedTickets': 0,
        'ticketUpgradeEnabled': ticketUpgradeEnabled,
      };

      if (ticketPrice != null) {
        updateData['ticketPrice'] = ticketPrice;
      }

      if (ticketUpgradePrice != null) {
        updateData['ticketUpgradePrice'] = ticketUpgradePrice;
      }

      await _firestore
          .collection(EventModel.firebaseKey)
          .doc(eventId)
          .update(updateData);
    } catch (e) {
      Logger.debug('Error enabling tickets for event: $e');
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
      Logger.debug('Error disabling tickets for event: $e');
      rethrow;
    }
  }

  Future<void> updateTicketPrice({
    required String eventId,
    required double ticketPrice,
    double? ticketUpgradePrice,
  }) async {
    try {
      final updateData = <String, dynamic>{'ticketPrice': ticketPrice};

      if (ticketUpgradePrice != null) {
        updateData['ticketUpgradePrice'] = ticketUpgradePrice;
      }

      await _firestore
          .collection(EventModel.firebaseKey)
          .doc(eventId)
          .update(updateData);
    } catch (e) {
      Logger.debug('Error updating ticket price: $e');
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
      Logger.debug('=== TICKET ISSUANCE DEBUG ===');
      Logger.debug('Event ID: $eventId');
      Logger.debug('Customer UID: $customerUid');
      Logger.debug('Customer Name: $customerName');

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

      Logger.debug('Event data:');
      Logger.debug('- Tickets enabled: $ticketsEnabled');
      Logger.debug('- Max tickets: $maxTickets');
      Logger.debug('- Issued tickets: $issuedTickets');

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

      Logger.debug(
        'Existing tickets for this user: ${existingTicketQuery.docs.length}',
      );

      // Debug: Log details of existing tickets
      for (var doc in existingTicketQuery.docs) {
        final ticketData = doc.data();
        Logger.debug('Existing ticket: $ticketData');
      }

      // Only block if user has an active (unused) ticket
      final activeTickets = existingTicketQuery.docs.where((doc) {
        final data = doc.data();
        return data['isUsed'] != true;
      }).toList();

      Logger.debug('Active tickets for this user: ${activeTickets.length}');

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

      Logger.debug('Creating ticket with ID: $ticketId');
      Logger.debug('Ticket code: $ticketCode');

      // Save ticket
      await _firestore
          .collection(TicketModel.firebaseKey)
          .doc(ticketId)
          .set(ticket.toJson());

      Logger.success('Ticket created successfully');

      // Update event ticket count
      await _firestore.collection(EventModel.firebaseKey).doc(eventId).update({
        'issuedTickets': issuedTickets + 1,
      });

      Logger.debug('Event ticket count updated');

      // Create ticket notification
      final messagingHelper = FirebaseMessagingHelper();
      await messagingHelper.createLocalNotification(
        title: 'Ticket Confirmed',
        body: 'You\'ve successfully registered for "${eventModel.title}"',
        type: 'ticket_update',
        eventId: eventId,
        eventTitle: eventModel.title,
      );

      // AUTO-REGISTER USER FOR THE EVENT (combining pre-registration with ticketing)
      try {
        // Check if user is already registered
        final existingRegistrationQuery = await _firestore
            .collection(AttendanceModel.registerFirebaseKey)
            .where('eventId', isEqualTo: eventId)
            .where('customerUid', isEqualTo: customerUid)
            .get();

        if (existingRegistrationQuery.docs.isEmpty) {
          // Create registration record
          final registrationId = _firestore
              .collection(AttendanceModel.registerFirebaseKey)
              .doc()
              .id;
          final registration = AttendanceModel(
            id: registrationId,
            eventId: eventId,
            userName: customerName,
            customerUid: customerUid,
            attendanceDateTime: DateTime.now(),
            answers: [],
            isAnonymous: false,
            realName: customerName,
          );

          await _firestore
              .collection(AttendanceModel.registerFirebaseKey)
              .doc(registrationId)
              .set(registration.toJson());

          Logger.success('User automatically registered for event');
        } else {
          Logger.debug('User already registered for this event');
        }
      } catch (e) {
        Logger.error('Error auto-registering user: $e');
        // Don't fail the ticket issuance if registration fails
      }

      return ticket;
    } catch (e) {
      Logger.error('Error issuing ticket: $e');
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
      Logger.debug('Error getting user tickets: $e');
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
      Logger.debug('Error getting event tickets: $e');
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
      Logger.debug('Error using ticket: $e');
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
      Logger.debug('Error getting ticket by code: $e');
      return null;
    }
  }

  Future<TicketModel?> getActiveTicketForUserAndEvent({
    required String customerUid,
    required String eventId,
  }) async {
    try {
      final query = await _firestore
          .collection(TicketModel.firebaseKey)
          .where('customerUid', isEqualTo: customerUid)
          .where('eventId', isEqualTo: eventId)
          .where('isUsed', isEqualTo: false)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        return TicketModel.fromJson(query.docs.first);
      }
      return null;
    } catch (e) {
      Logger.debug('Error getting active ticket for user/event: $e');
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

      Logger.debug(
        'Cleared ${querySnapshot.docs.length} tickets for user: $customerUid',
      );
    } catch (e) {
      Logger.debug('Error clearing user tickets: $e');
      rethrow;
    }
  }

  Stream<EventModel> getEventStream(String eventId) {
    return _firestore
        .collection(EventModel.firebaseKey)
        .doc(eventId)
        .snapshots()
        .map((snapshot) => EventModel.fromJson(snapshot.data()!));
  }

  Stream<List<TicketModel>> getTicketsStream(String eventId) {
    return _firestore
        .collection(TicketModel.firebaseKey)
        .where('eventId', isEqualTo: eventId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => TicketModel.fromJson(doc.data()))
              .toList(),
        );
  }

  /// Deletes an event from Firestore
  ///
  /// This method deletes the event document and all related data
  Future<void> deleteEvent(String eventId) async {
    try {
      // Delete the event document
      await _firestore.collection(EventModel.firebaseKey).doc(eventId).delete();

      // Delete related attendance records
      final attendanceQuery = await _firestore
          .collection(AttendanceModel.firebaseKey)
          .where('eventId', isEqualTo: eventId)
          .get();

      for (var doc in attendanceQuery.docs) {
        await doc.reference.delete();
      }

      // Delete related pre-registration records
      final preRegistrationQuery = await _firestore
          .collection(AttendanceModel.registerFirebaseKey)
          .where('eventId', isEqualTo: eventId)
          .get();

      for (var doc in preRegistrationQuery.docs) {
        await doc.reference.delete();
      }

      // Delete related tickets
      final ticketsQuery = await _firestore
          .collection(TicketModel.firebaseKey)
          .where('eventId', isEqualTo: eventId)
          .get();

      for (var doc in ticketsQuery.docs) {
        await doc.reference.delete();
      }

      // Delete related comments
      final commentsQuery = await _firestore
          .collection(CommentModel.firebaseKey)
          .where('eventId', isEqualTo: eventId)
          .get();

      for (var doc in commentsQuery.docs) {
        await doc.reference.delete();
      }

      Logger.debug('Successfully deleted event: $eventId');
    } catch (e) {
      Logger.debug('Error deleting event: $e');
      rethrow;
    }
  }

  // Event Feedback Methods
  Future<void> submitEventFeedback({
    required String eventId,
    required int rating,
    String? comment,
    required bool isAnonymous,
    String? userId,
  }) async {
    try {
      final feedbackData = {
        'eventId': eventId,
        'userId': isAnonymous ? null : userId,
        'rating': rating,
        'comment': comment,
        'timestamp': Timestamp.now(),
        'isAnonymous': isAnonymous,
      };

      await _firestore
          .collection(EventFeedbackModel.firebaseKey)
          .add(feedbackData);

      Logger.debug('Feedback submitted successfully for event: $eventId');

      // Create notification for user who submitted feedback (if not anonymous)
      if (!isAnonymous && userId != null) {
        final messagingHelper = FirebaseMessagingHelper();
        await messagingHelper.createLocalNotification(
          title: 'Thank You for Your Feedback!',
          body: 'Your feedback has been submitted successfully',
          type: 'event_feedback',
          eventId: eventId,
        );
      }
    } catch (e) {
      Logger.debug('Error submitting feedback: $e');
      rethrow;
    }
  }

  Future<List<EventFeedbackModel>> getEventFeedback({
    required String eventId,
  }) async {
    try {
      final querySnapshot = await _firestore
          .collection(EventFeedbackModel.firebaseKey)
          .where('eventId', isEqualTo: eventId)
          .orderBy('timestamp', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => EventFeedbackModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      Logger.debug('Error getting event feedback: $e');
      return [];
    }
  }

  Future<EventFeedbackAnalytics?> getEventFeedbackAnalytics({
    required String eventId,
  }) async {
    try {
      final analyticsDoc = await _firestore
          .collection('event_analytics')
          .doc(eventId)
          .get();

      if (analyticsDoc.exists) {
        final data = analyticsDoc.data() as Map<String, dynamic>;
        if (data.containsKey('feedbackAnalytics')) {
          return EventFeedbackAnalytics.fromFirestore(
            data['feedbackAnalytics'],
          );
        }
      }
      return null;
    } catch (e) {
      Logger.debug('Error getting feedback analytics: $e');
      return null;
    }
  }

  Future<bool> hasUserSubmittedFeedback({
    required String eventId,
    required String userId,
  }) async {
    try {
      final querySnapshot = await _firestore
          .collection(EventFeedbackModel.firebaseKey)
          .where('eventId', isEqualTo: eventId)
          .where('userId', isEqualTo: userId)
          .get();

      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      Logger.debug('Error checking if user submitted feedback: $e');
      return false;
    }
  }

  // Enhanced user search with username support
  Future<List<CustomerModel>> searchUsers({
    required String searchQuery,
    int limit = 100,
  }) async {
    try {
      Logger.debug('Searching users with query: "$searchQuery"');

      List<CustomerModel> users = [];

      // Remove @ prefix if present for searching
      String cleanSearchQuery = searchQuery.startsWith('@')
          ? searchQuery.substring(1)
          : searchQuery;

      // If search query is empty, get all discoverable users
      if (searchQuery.isEmpty) {
        try {
          final allUsersQuery = await _firestore
              .collection(CustomerModel.firebaseKey)
              .where('isDiscoverable', isEqualTo: true)
              .orderBy('name', descending: false)
              .limit(limit)
              .get();

          users = allUsersQuery.docs
              .map((doc) => CustomerModel.fromFirestore(doc))
              .toList();
        } catch (e) {
          Logger.debug(
            'Composite index query failed, falling back to client-side filtering: $e',
          );
          // Fallback: get all users and filter client-side
          final allUsersQuery = await _firestore
              .collection(CustomerModel.firebaseKey)
              .get();

          users = allUsersQuery.docs
              .map((doc) => CustomerModel.fromFirestore(doc))
              .where((user) => user.isDiscoverable == true)
              .take(limit)
              .toList();
        }
      } else {
        // Search by username first (exact match)
        if (cleanSearchQuery.isNotEmpty) {
          try {
            final usernameQuery = await _firestore
                .collection(CustomerModel.firebaseKey)
                .where('username', isEqualTo: cleanSearchQuery.toLowerCase())
                .where('isDiscoverable', isEqualTo: true)
                .get();

            users.addAll(
              usernameQuery.docs
                  .map((doc) => CustomerModel.fromFirestore(doc))
                  .toList(),
            );
          } catch (e) {
            Logger.debug('Error searching by username: $e');
          }
        }

        // Search by name (prefix search)
        try {
          Query query = _firestore
              .collection(CustomerModel.firebaseKey)
              .where('isDiscoverable', isEqualTo: true)
              .orderBy('name', descending: false)
              .limit(limit);

          if (searchQuery.isNotEmpty) {
            query = query
                .where('name', isGreaterThanOrEqualTo: searchQuery)
                .where('name', isLessThan: '$searchQuery\uf8ff');
          }

          final querySnapshot = await query.get();
          Logger.debug('Found ${querySnapshot.docs.length} users in Firestore');

          final nameUsers = querySnapshot.docs
              .map((doc) => CustomerModel.fromFirestore(doc))
              .toList();

          // Combine and remove duplicates
          users.addAll(nameUsers);
          users = users.toSet().toList(); // Remove duplicates
        } catch (e) {
          Logger.debug(
            'Composite index query failed, falling back to client-side filtering: $e',
          );
          // Fallback: get all users and filter client-side
          final allUsersQuery = await _firestore
              .collection(CustomerModel.firebaseKey)
              .get();

          final allUsers = allUsersQuery.docs
              .map((doc) => CustomerModel.fromFirestore(doc))
              .where((user) => user.isDiscoverable == true)
              .toList();

          // Filter by search query
          users = allUsers
              .where(
                (user) =>
                    user.name.toLowerCase().contains(
                      searchQuery.toLowerCase(),
                    ) ||
                    (user.username != null &&
                        user.username!.toLowerCase().contains(
                          cleanSearchQuery.toLowerCase(),
                        )),
              )
              .take(limit)
              .toList();
        }
      }

      // Sort users alphabetically by name
      users.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      Logger.debug('Returning ${users.length} users after sorting');
      return users;
    } catch (e) {
      Logger.debug('Error searching users: $e');
      return [];
    }
  }

  /// Updates user discoverability setting
  Future<void> updateUserDiscoverability({
    required String userId,
    required bool isDiscoverable,
  }) async {
    try {
      await _firestore.collection('Customers').doc(userId).update({
        'isDiscoverable': isDiscoverable,
      });
    } catch (e) {
      Logger.debug('Error updating user discoverability: $e');
      rethrow;
    }
  }

  /// Follow a user
  Future<void> followUser({
    required String followerId,
    required String followingId,
  }) async {
    try {
      if (followerId == followingId) {
        throw Exception('Users cannot follow themselves');
      }

      final followerFollowingRef = _firestore
          .collection('Customers')
          .doc(followerId)
          .collection('following')
          .doc(followingId);

      final followingFollowersRef = _firestore
          .collection('Customers')
          .doc(followingId)
          .collection('followers')
          .doc(followerId);

      final batch = _firestore.batch();

      batch.set(followerFollowingRef, {
        'followingId': followingId,
        'followedAt': FieldValue.serverTimestamp(),
      });

      batch.set(followingFollowersRef, {
        'followerId': followerId,
        'followedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      Logger.debug('User $followerId is now following $followingId');
    } catch (e) {
      Logger.debug('Error following user: $e');
      if (e.toString().contains('permission-denied')) {
        throw Exception(
          'Follow feature is not available. Please contact support.',
        );
      }
      rethrow;
    }
  }

  /// Unfollow a user
  Future<void> unfollowUser({
    required String followerId,
    required String followingId,
  }) async {
    try {
      final followerFollowingRef = _firestore
          .collection('Customers')
          .doc(followerId)
          .collection('following')
          .doc(followingId);

      final followingFollowersRef = _firestore
          .collection('Customers')
          .doc(followingId)
          .collection('followers')
          .doc(followerId);

      final batch = _firestore.batch();

      batch.delete(followerFollowingRef);
      batch.delete(followingFollowersRef);

      await batch.commit();

      Logger.debug('User $followerId unfollowed $followingId');
    } catch (e) {
      Logger.debug('Error unfollowing user: $e');
      if (e.toString().contains('permission-denied')) {
        throw Exception(
          'Unfollow feature is not available. Please contact support.',
        );
      }
      rethrow;
    }
  }

  /// Check if a user is following another user
  Future<bool> isFollowingUser({
    required String followerId,
    required String followingId,
  }) async {
    try {
      final doc = await _firestore
          .collection('Customers')
          .doc(followerId)
          .collection('following')
          .doc(followingId)
          .get();
      return doc.exists;
    } catch (e) {
      Logger.debug('Error checking follow status: $e');
      // If permission denied or collection doesn't exist, return false
      if (e.toString().contains('permission-denied') ||
          e.toString().contains('not-found')) {
        Logger.debug('Following collection not accessible, returning false');
        return false;
      }
      return false;
    }
  }

  /// Get followers count for a user
  Future<int> getFollowersCount({required String userId}) async {
    try {
      final querySnapshot = await _firestore
          .collection('Customers')
          .doc(userId)
          .collection('followers')
          .get();
      return querySnapshot.docs.length;
    } catch (e) {
      Logger.debug('Error getting followers count: $e');
      // If permission denied or collection doesn't exist, return 0
      if (e.toString().contains('permission-denied') ||
          e.toString().contains('not-found')) {
        Logger.debug('Followers collection not accessible, returning 0');
        return 0;
      }
      return 0;
    }
  }

  /// Get following count for a user
  Future<int> getFollowingCount({required String userId}) async {
    try {
      final querySnapshot = await _firestore
          .collection('Customers')
          .doc(userId)
          .collection('following')
          .get();
      return querySnapshot.docs.length;
    } catch (e) {
      Logger.debug('Error getting following count: $e');
      // If permission denied or collection doesn't exist, return 0
      if (e.toString().contains('permission-denied') ||
          e.toString().contains('not-found')) {
        Logger.debug('Following collection not accessible, returning 0');
        return 0;
      }
      return 0;
    }
  }

  /// Get list of followers for a user
  Future<List<String>> getFollowersList({required String userId}) async {
    try {
      final querySnapshot = await _firestore
          .collection('Customers')
          .doc(userId)
          .collection('followers')
          .get();
      return querySnapshot.docs.map((doc) => doc.id).toList();
    } catch (e) {
      Logger.debug('Error getting followers list: $e');
      return [];
    }
  }

  /// Get list of users that a user is following
  Future<List<String>> getFollowingList({required String userId}) async {
    try {
      final querySnapshot = await _firestore
          .collection('Customers')
          .doc(userId)
          .collection('following')
          .get();
      return querySnapshot.docs.map((doc) => doc.id).toList();
    } catch (e) {
      Logger.debug('Error getting following list: $e');
      return [];
    }
  }

  // Method to ensure current user has required fields
  Future<void> ensureCurrentUserFields() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await _firestore
          .collection(CustomerModel.firebaseKey)
          .doc(user.uid)
          .get();

      if (!userDoc.exists) return;

      final data = userDoc.data()!;
      Map<String, dynamic> updates = {};

      // Check for missing isDiscoverable field
      if (!data.containsKey('isDiscoverable')) {
        updates['isDiscoverable'] = true;
      }

      // Check for missing username field
      if (!data.containsKey('username') || data['username'] == null) {
        final customer = CustomerModel.fromFirestore(userDoc);
        final username = await generateUsernameForExistingUser(customer.name);
        updates['username'] = username;
      }

      // Update if there are any missing fields
      if (updates.isNotEmpty) {
        await userDoc.reference.update(updates);
        Logger.debug('Updated current user with: $updates');

        // Update the CustomerController if user is logged in
        if (CustomerController.logeInCustomer != null) {
          CustomerController.logeInCustomer!.isDiscoverable =
              updates['isDiscoverable'] ??
              CustomerController.logeInCustomer!.isDiscoverable;
          if (updates['username'] != null) {
            CustomerController.logeInCustomer!.username = updates['username'];
          }
        }
      }
    } catch (e) {
      Logger.debug('Error ensuring current user fields: $e');
    }
  }

  Future<List<CustomerModel>> getUsersByIds({
    required List<String> userIds,
  }) async {
    try {
      if (userIds.isEmpty) return [];

      // Firestore has a limit of 10 items in 'in' queries
      // So we need to batch the requests
      List<CustomerModel> allUsers = [];

      for (int i = 0; i < userIds.length; i += 10) {
        final batch = userIds.skip(i).take(10).toList();

        final querySnapshot = await _firestore
            .collection(CustomerModel.firebaseKey)
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        final users = querySnapshot.docs
            .map((doc) => CustomerModel.fromFirestore(doc))
            .toList();

        allUsers.addAll(users);
      }

      return allUsers;
    } catch (e) {
      Logger.debug('Error getting users by IDs: $e');
      return [];
    }
  }

  // Utility method to update existing users to have isDiscoverable field
  Future<void> updateExistingUsersWithDiscoverability() async {
    try {
      final querySnapshot = await _firestore
          .collection(CustomerModel.firebaseKey)
          .get();

      int updatedCount = 0;
      for (var doc in querySnapshot.docs) {
        try {
          final data = doc.data();
          if (!data.containsKey('isDiscoverable')) {
            await doc.reference.update({
              'isDiscoverable': true, // Default to true for existing users
            });
            updatedCount++;
            Logger.debug('Updated user ${doc.id} with isDiscoverable field');
          }
        } catch (e) {
          Logger.debug('Error updating user ${doc.id}: $e');
          // Continue with other users even if one fails
        }
      }
      Logger.debug(
        'Finished updating $updatedCount users with discoverability field',
      );
    } catch (e) {
      Logger.debug('Error updating existing users: $e');
    }
  }

  // Method to ensure all users have required fields
  Future<void> ensureUserProfileCompleteness(String userId) async {
    try {
      final userDoc = await _firestore
          .collection(CustomerModel.firebaseKey)
          .doc(userId)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        Map<String, dynamic> updates = {};

        // Ensure isDiscoverable field exists
        if (!data.containsKey('isDiscoverable')) {
          updates['isDiscoverable'] = true;
        }

        // Update if there are any missing fields
        if (updates.isNotEmpty) {
          await userDoc.reference.update(updates);
          Logger.debug('Updated user $userId with missing fields: $updates');
        }
      }
    } catch (e) {
      Logger.debug('Error ensuring user profile completeness: $e');
    }
  }

  // Method to update user profile from Firebase Auth data if incomplete
  Future<bool> updateUserProfileFromFirebaseAuth(String userId) async {
    try {
      final userDoc = await _firestore
          .collection(CustomerModel.firebaseKey)
          .doc(userId)
          .get();

      if (!userDoc.exists) {
        Logger.debug('User document does not exist: $userId');
        return false;
      }

      final customerModel = CustomerModel.fromFirestore(userDoc);

      // Get Firebase Auth user data
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser == null || firebaseUser.uid != userId) {
        Logger.debug('Firebase Auth user not found or UID mismatch');
        return false;
      }

      Map<String, dynamic> updates = {};

      // Check if we should update the name
      bool shouldUpdateName = false;

      if (customerModel.name.isEmpty ||
          customerModel.name == customerModel.email.split('@')[0] ||
          customerModel.name.toLowerCase() == 'user' ||
          customerModel.name.toLowerCase() == 'unknown' ||
          customerModel.name.contains('@')) {
        shouldUpdateName = true;
      }

      // Update name if needed and Firebase Auth has better data
      if (shouldUpdateName &&
          firebaseUser.displayName != null &&
          firebaseUser.displayName!.trim().isNotEmpty &&
          firebaseUser.displayName != customerModel.name) {
        updates['name'] = firebaseUser.displayName!.trim();
        Logger.debug(
          'Updating user $userId name to: ${firebaseUser.displayName}',
        );
      }

      // Update profile picture if missing and available in Firebase Auth
      if ((customerModel.profilePictureUrl == null ||
              customerModel.profilePictureUrl!.isEmpty) &&
          firebaseUser.photoURL != null &&
          firebaseUser.photoURL!.isNotEmpty) {
        updates['profilePictureUrl'] = firebaseUser.photoURL;
        Logger.debug('Updating user $userId profile picture');
      }

      // Apply updates if any
      if (updates.isNotEmpty) {
        await userDoc.reference.update(updates);
        Logger.info(
          'Updated user $userId profile from Firebase Auth with: ${updates.keys.join(', ')}',
        );
        return true;
      }

      return false;
    } catch (e) {
      Logger.error('Error updating user profile from Firebase Auth: $e', e);
      return false;
    }
  }

  // Check if username is available
  Future<bool> isUsernameAvailable(String username) async {
    try {
      // Remove @ prefix if present for checking
      String cleanUsername = username.startsWith('@')
          ? username.substring(1)
          : username;

      final querySnapshot = await _firestore
          .collection(CustomerModel.firebaseKey)
          .where('username', isEqualTo: cleanUsername.toLowerCase())
          .get();

      return querySnapshot.docs.isEmpty;
    } catch (e) {
      Logger.debug('Error checking username availability: $e');
      return false;
    }
  }

  // Generate a unique username from full name
  Future<String> generateUniqueUsername(String fullName) async {
    try {
      // Remove special characters and convert to lowercase
      String baseUsername = fullName
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '')
          .trim();

      if (baseUsername.isEmpty) {
        baseUsername = 'user';
      }

      String username = baseUsername;
      int counter = 1;

      // Keep trying until we find an available username
      while (!await isUsernameAvailable(username)) {
        username = '$baseUsername$counter';
        counter++;

        // Prevent infinite loop
        if (counter > 100) {
          username = 'user${DateTime.now().millisecondsSinceEpoch}';
          break;
        }
      }

      return username;
    } catch (e) {
      Logger.debug('Error generating unique username: $e');
      return 'user${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  // Generate username for existing users (name + 100)
  Future<String> generateUsernameForExistingUser(String fullName) async {
    try {
      // Remove special characters and convert to lowercase
      String baseUsername = fullName
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '')
          .trim();

      if (baseUsername.isEmpty) {
        baseUsername = 'user';
      }

      // Add 100 to the end
      String username = '${baseUsername}100';
      int counter = 1;

      // Keep trying until we find an available username
      while (!await isUsernameAvailable(username)) {
        username = '$baseUsername${100 + counter}';
        counter++;

        // Prevent infinite loop
        if (counter > 100) {
          username = 'user${DateTime.now().millisecondsSinceEpoch}';
          break;
        }
      }

      return username;
    } catch (e) {
      Logger.debug('Error generating username for existing user: $e');
      return 'user${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  // Update user's username
  Future<bool> updateUsername({
    required String userId,
    required String newUsername,
  }) async {
    try {
      // Remove @ prefix if present for storage
      String cleanUsername = newUsername.startsWith('@')
          ? newUsername.substring(1)
          : newUsername;

      // Check if username is available
      if (!await isUsernameAvailable(cleanUsername)) {
        return false;
      }

      await _firestore.collection(CustomerModel.firebaseKey).doc(userId).update(
        {'username': cleanUsername.toLowerCase()},
      );

      Logger.debug('Username updated successfully');
      return true;
    } catch (e) {
      Logger.debug('Error updating username: $e');
      return false;
    }
  }

  // Update existing users to have usernames if they don't have one
  Future<void> updateExistingUsersWithUsernames() async {
    try {
      final querySnapshot = await _firestore
          .collection(CustomerModel.firebaseKey)
          .get();

      int updatedCount = 0;
      for (var doc in querySnapshot.docs) {
        try {
          final data = doc.data();
          if (!data.containsKey('username') || data['username'] == null) {
            final user = CustomerModel.fromFirestore(doc);
            final username = await generateUsernameForExistingUser(user.name);

            await doc.reference.update({'username': username});
            updatedCount++;
            Logger.debug('Updated user ${doc.id} with username: $username');
          }
        } catch (e) {
          Logger.debug('Error updating user ${doc.id}: $e');
          // Continue with other users even if one fails
        }
      }
      Logger.debug('Finished updating $updatedCount users with usernames');
    } catch (e) {
      Logger.debug('Error updating existing users with usernames: $e');
    }
  }

  // Method to update event location
  static Future<void> updateEventLocation(
    String eventId,
    double latitude,
    double longitude,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection(EventModel.firebaseKey)
          .doc(eventId)
          .update({'latitude': latitude, 'longitude': longitude});
      Logger.success('Event location updated successfully for event: $eventId');
    } catch (e) {
      Logger.error('Error updating event location: $e');
      rethrow;
    }
  }

  // Co-host management methods
  Future<bool> addCoHost({
    required String eventId,
    required String coHostUserId,
  }) async {
    try {
      // Get the current event
      final eventDoc = await _firestore
          .collection(EventModel.firebaseKey)
          .doc(eventId)
          .get();

      if (!eventDoc.exists) {
        Logger.debug('Event not found: $eventId');
        return false;
      }

      final eventData = eventDoc.data()!;
      List<String> coHosts = List<String>.from(eventData['coHosts'] ?? []);

      // Check if user is already a co-host
      if (coHosts.contains(coHostUserId)) {
        Logger.debug('User is already a co-host: $coHostUserId');
        return false;
      }

      // Add the new co-host
      coHosts.add(coHostUserId);

      // Update the event
      await _firestore.collection(EventModel.firebaseKey).doc(eventId).update({
        'coHosts': coHosts,
      });

      Logger.debug(
        'Co-host added successfully: $coHostUserId to event: $eventId',
      );
      return true;
    } catch (e) {
      Logger.debug('Error adding co-host: $e');
      return false;
    }
  }

  Future<bool> removeCoHost({
    required String eventId,
    required String coHostUserId,
  }) async {
    try {
      // Get the current event
      final eventDoc = await _firestore
          .collection(EventModel.firebaseKey)
          .doc(eventId)
          .get();

      if (!eventDoc.exists) {
        Logger.debug('Event not found: $eventId');
        return false;
      }

      final eventData = eventDoc.data()!;
      List<String> coHosts = List<String>.from(eventData['coHosts'] ?? []);

      // Check if user is a co-host
      if (!coHosts.contains(coHostUserId)) {
        Logger.debug('User is not a co-host: $coHostUserId');
        return false;
      }

      // Remove the co-host
      coHosts.remove(coHostUserId);

      // Update the event
      await _firestore.collection(EventModel.firebaseKey).doc(eventId).update({
        'coHosts': coHosts,
      });

      Logger.debug(
        'Co-host removed successfully: $coHostUserId from event: $eventId',
      );
      return true;
    } catch (e) {
      Logger.debug('Error removing co-host: $e');
      return false;
    }
  }

  Future<List<CustomerModel>> getCoHosts({required String eventId}) async {
    try {
      final eventDoc = await _firestore
          .collection(EventModel.firebaseKey)
          .doc(eventId)
          .get();

      if (!eventDoc.exists) {
        Logger.debug('Event not found: $eventId');
        return [];
      }

      final eventData = eventDoc.data()!;
      List<String> coHostIds = List<String>.from(eventData['coHosts'] ?? []);

      if (coHostIds.isEmpty) {
        return [];
      }

      // Get co-host user details
      return await getUsersByIds(userIds: coHostIds);
    } catch (e) {
      Logger.debug('Error getting co-hosts: $e');
      return [];
    }
  }

  Future<bool> isUserCoHost({
    required String eventId,
    required String userId,
  }) async {
    try {
      final eventDoc = await _firestore
          .collection(EventModel.firebaseKey)
          .doc(eventId)
          .get();

      if (!eventDoc.exists) {
        return false;
      }

      final eventData = eventDoc.data()!;
      List<String> coHosts = List<String>.from(eventData['coHosts'] ?? []);

      return coHosts.contains(userId);
    } catch (e) {
      Logger.debug('Error checking if user is co-host: $e');
      return false;
    }
  }

  // Saved Events functionality
  Future<bool> addToFavorites({
    required String userId,
    required String eventId,
  }) async {
    try {
      // Get current user data
      final userDoc = await _firestore
          .collection(CustomerModel.firebaseKey)
          .doc(userId)
          .get();

      if (!userDoc.exists) {
        Logger.debug('User not found: $userId');
        return false;
      }

      final userData = userDoc.data()!;
      List<String> favorites = List<String>.from(userData['favorites'] ?? []);

      // Check if event is already saved
      if (favorites.contains(eventId)) {
        Logger.debug('Event already saved: $eventId');
        return true; // Already saved, consider it successful
      }

      // Add event to saved events
      favorites.add(eventId);

      // Update user document
      await _firestore.collection(CustomerModel.firebaseKey).doc(userId).update(
        {'favorites': favorites},
      );

      Logger.debug('Event added to saved events: $eventId for user: $userId');
      return true;
    } catch (e) {
      Logger.debug('Error adding event to saved events: $e');
      return false;
    }
  }

  Future<bool> removeFromFavorites({
    required String userId,
    required String eventId,
  }) async {
    try {
      // Get current user data
      final userDoc = await _firestore
          .collection(CustomerModel.firebaseKey)
          .doc(userId)
          .get();

      if (!userDoc.exists) {
        Logger.debug('User not found: $userId');
        return false;
      }

      final userData = userDoc.data()!;
      List<String> favorites = List<String>.from(userData['favorites'] ?? []);

      // Check if event is in saved events
      if (!favorites.contains(eventId)) {
        Logger.debug('Event not in saved events: $eventId');
        return true; // Not in saved events, consider it successful
      }

      // Remove event from saved events
      favorites.remove(eventId);

      // Update user document
      await _firestore.collection(CustomerModel.firebaseKey).doc(userId).update(
        {'favorites': favorites},
      );

      Logger.debug(
        'Event removed from saved events: $eventId for user: $userId',
      );
      return true;
    } catch (e) {
      Logger.debug('Error removing event from saved events: $e');
      return false;
    }
  }

  Future<bool> isEventFavorited({
    required String userId,
    required String eventId,
  }) async {
    try {
      // Get current user data
      final userDoc = await _firestore
          .collection(CustomerModel.firebaseKey)
          .doc(userId)
          .get();

      if (!userDoc.exists) {
        Logger.debug('User not found: $userId');
        return false;
      }

      final userData = userDoc.data()!;
      List<String> favorites = List<String>.from(userData['favorites'] ?? []);

      return favorites.contains(eventId);
    } catch (e) {
      Logger.debug('Error checking if event is saved: $e');
      return false;
    }
  }

  Future<List<EventModel>> getFavoritedEvents({
    required String userId,
    int? limit,
  }) async {
    try {
      // Get current user data with timeout
      final userDoc = await _firestore
          .collection(CustomerModel.firebaseKey)
          .doc(userId)
          .get()
          .timeout(const Duration(seconds: 2));

      if (!userDoc.exists) {
        Logger.debug('User not found: $userId');
        return [];
      }

      final userData = userDoc.data()!;
      List<String> favoriteEventIds = List<String>.from(
        userData['favorites'] ?? [],
      );

      if (favoriteEventIds.isEmpty) {
        return [];
      }

      // PERFORMANCE: Apply limit before fetching
      if (limit != null && favoriteEventIds.length > limit) {
        favoriteEventIds = favoriteEventIds.sublist(0, limit);
      }

      Logger.debug(
        'Fetching ${favoriteEventIds.length} saved events using batch query',
      );

      // PERFORMANCE OPTIMIZATION: Use whereIn batch query instead of individual fetches
      // Firestore whereIn supports up to 10 items per query, so batch in chunks of 10
      final List<EventModel> allEvents = [];
      
      for (int i = 0; i < favoriteEventIds.length; i += 10) {
        final batchIds = favoriteEventIds.skip(i).take(10).toList();
        
        try {
          final querySnapshot = await _firestore
              .collection(EventModel.firebaseKey)
              .where(FieldPath.documentId, whereIn: batchIds)
              .get()
              .timeout(const Duration(seconds: 5));

          // Parse all events from this batch
          for (final doc in querySnapshot.docs) {
            try {
              final eventData = doc.data();
              eventData['id'] = eventData['id'] ?? doc.id;
              final event = EventModel.fromJson(eventData);
              allEvents.add(event);
            } catch (e) {
              Logger.error('Error parsing event ${doc.id}: $e', e);
            }
          }
        } catch (e) {
          Logger.warning('Batch query timeout for batch starting at $i: $e');
        }
      }

      Logger.debug('✅ Saved events count: ${allEvents.length}');
      return allEvents;
    } catch (e) {
      Logger.debug('Error getting saved events: $e');
      return [];
    }
  }

  // ====== Private Event Access Request Workflow ======
  Future<void> requestEventAccess({
    required String eventId,
    String? message,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await _firestore
        .collection(EventModel.firebaseKey)
        .doc(eventId)
        .collection('AccessRequests')
        .doc(uid)
        .set({
          'userId': uid,
          'message': message ?? '',
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> approveEventAccess({
    required String eventId,
    required String userId,
  }) async {
    final eventRef = _firestore.collection(EventModel.firebaseKey).doc(eventId);
    await eventRef
        .update({
          'accessList': FieldValue.arrayUnion([userId]),
        })
        .catchError((_) {});

    await eventRef.collection('AccessRequests').doc(userId).set({
      'status': 'approved',
      'reviewedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> declineEventAccess({
    required String eventId,
    required String userId,
    String? reason,
  }) async {
    final eventRef = _firestore.collection(EventModel.firebaseKey).doc(eventId);
    await eventRef.collection('AccessRequests').doc(userId).set({
      'status': 'declined',
      'reason': reason ?? '',
      'reviewedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ====== End Private Event Access Request Workflow ======

  Future<void> submitAppFeedback({
    String? userId,
    required int rating,
    String? comment,
    required bool isAnonymous,
    String? name,
    String? email,
    String? contactNumber,
  }) async {
    try {
      final feedbackData = {
        'userId': isAnonymous ? null : userId,
        'rating': rating,
        'comment': comment,
        'timestamp': Timestamp.now(),
        'isAnonymous': isAnonymous,
        'name': name,
        'email': email,
        'contactNumber': contactNumber,
      };

      await _firestore
          .collection(AppFeedbackModel.firebaseKey)
          .add(feedbackData);

      Logger.debug('App feedback submitted successfully');
    } catch (e) {
      Logger.debug('Error submitting app feedback: $e');
      rethrow;
    }
  }
}
