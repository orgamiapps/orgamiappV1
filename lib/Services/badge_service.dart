import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:orgami/models/badge_model.dart';
import 'package:orgami/models/customer_model.dart';
import 'package:orgami/firebase/firebase_firestore_helper.dart';

class BadgeService {
  static final BadgeService _instance = BadgeService._internal();
  factory BadgeService() => _instance;
  BadgeService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Create or update a user's badge with current statistics
  Future<BadgeModel> createOrUpdateUserBadge(String userId) async {
    try {
      // Get user data
      final userDoc = await _firestore.collection('Customers').doc(userId).get();
      if (!userDoc.exists) {
        throw Exception('User not found');
      }
      
      final userData = CustomerModel.fromFirestore(userDoc);
      
      // Calculate statistics
      final stats = await _calculateUserStatistics(userId);
      
      // Create badge model
      final badge = BadgeModel(
        userId: userId,
        userName: userData.name,
        userEmail: userData.email,
        eventsCreated: stats['eventsCreated'] ?? 0,
        eventsAttended: stats['eventsAttended'] ?? 0,
        memberSince: userData.createdAt,
        profileImageUrl: userData.profilePictureUrl,
        lastUpdated: DateTime.now(),
        totalTicketsIssued: stats['totalTicketsIssued'] ?? 0,
        totalAttendeeCount: stats['totalAttendeeCount'] ?? 0,
        averageEventRating: stats['averageEventRating'] ?? 0.0,
        categories: stats['categories'] ?? [],
        consecutiveMonthsActive: stats['consecutiveMonthsActive'] ?? 0,
      );
      
      // Calculate points and level
      badge.totalPoints = badge.calculateTotalPoints();
      badge.badgeLevel = badge.calculateBadgeLevel();
      
      // Save to Firestore
      await _firestore
          .collection(BadgeModel.firebaseKey)
          .doc(userId)
          .set(badge.toMap());
      
      return badge;
    } catch (e) {
      throw Exception('Failed to create/update badge: $e');
    }
  }

  /// Get user's badge from Firestore
  Future<BadgeModel?> getUserBadge(String userId) async {
    try {
      final doc = await _firestore
          .collection(BadgeModel.firebaseKey)
          .doc(userId)
          .get();
      
      if (!doc.exists) {
        // Create badge if it doesn't exist
        return await createOrUpdateUserBadge(userId);
      }
      
      return BadgeModel.fromFirestore(doc);
    } catch (e) {
      throw Exception('Failed to get user badge: $e');
    }
  }

  /// Calculate comprehensive user statistics
  Future<Map<String, dynamic>> _calculateUserStatistics(String userId) async {
    try {
      final stats = <String, dynamic>{};
      
      // Get events created by user
      final createdEvents = await FirebaseFirestoreHelper()
          .getEventsCreatedByUser(userId);
      stats['eventsCreated'] = createdEvents.length;
      
      // Get events attended by user
      final attendedEvents = await FirebaseFirestoreHelper()
          .getEventsAttendedByUser(userId);
      stats['eventsAttended'] = attendedEvents.length;
      
      // Calculate total tickets issued from user's events
      int totalTickets = 0;
      int totalAttendees = 0;
      final Set<String> categories = <String>{};
      double totalRatings = 0;
      int ratedEvents = 0;
      
      for (final event in createdEvents) {
        totalTickets += event.issuedTickets;
        
        // Get attendees count for this event
        final attendees = await _getEventAttendeesCount(event.id);
        totalAttendees += attendees;
        
        // Collect categories
        categories.addAll(event.categories);
        
        // Get event rating (placeholder - you might have a rating system)
        final rating = await _getEventAverageRating(event.id);
        if (rating > 0) {
          totalRatings += rating;
          ratedEvents++;
        }
      }
      
      stats['totalTicketsIssued'] = totalTickets;
      stats['totalAttendeeCount'] = totalAttendees;
      stats['categories'] = categories.toList();
      stats['averageEventRating'] = ratedEvents > 0 ? totalRatings / ratedEvents : 0.0;
      
      // Calculate consecutive months active
      stats['consecutiveMonthsActive'] = await _calculateConsecutiveMonthsActive(userId);
      
      return stats;
    } catch (e) {
      throw Exception('Failed to calculate user statistics: $e');
    }
  }

  /// Get count of attendees for a specific event
  Future<int> _getEventAttendeesCount(String eventId) async {
    try {
      final snapshot = await _firestore
          .collection('Attendance')
          .where('eventId', isEqualTo: eventId)
          .get();
      return snapshot.docs.length;
    } catch (e) {
      return 0;
    }
  }

  /// Get average rating for an event (placeholder implementation)
  Future<double> _getEventAverageRating(String eventId) async {
    try {
      // This would connect to your feedback/rating system
      final snapshot = await _firestore
          .collection('EventFeedback')
          .where('eventId', isEqualTo: eventId)
          .get();
      
      if (snapshot.docs.isEmpty) return 0.0;
      
      double totalRating = 0;
      int validRatings = 0;
      
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data['rating'] != null) {
          totalRating += data['rating'].toDouble();
          validRatings++;
        }
      }
      
      return validRatings > 0 ? totalRating / validRatings : 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  /// Calculate consecutive months the user has been active
  Future<int> _calculateConsecutiveMonthsActive(String userId) async {
    try {
      final now = DateTime.now();
      int consecutiveMonths = 0;
      
      // Check each month backwards from current month
      for (int i = 0; i < 12; i++) {
        final checkDate = DateTime(now.year, now.month - i, 1);
        final nextMonth = DateTime(now.year, now.month - i + 1, 1);
        
        // Check if user had any activity in this month
        final hasActivity = await _hasActivityInMonth(userId, checkDate, nextMonth);
        
        if (hasActivity) {
          consecutiveMonths++;
        } else {
          break; // Break consecutive streak
        }
      }
      
      return consecutiveMonths;
    } catch (e) {
      return 0;
    }
  }

  /// Check if user had any activity (created/attended events) in a specific month
  Future<bool> _hasActivityInMonth(String userId, DateTime startDate, DateTime endDate) async {
    try {
      // Check for created events
      final createdSnapshot = await _firestore
          .collection('Events')
          .where('customerUid', isEqualTo: userId)
          .where('eventGenerateTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('eventGenerateTime', isLessThan: Timestamp.fromDate(endDate))
          .limit(1)
          .get();
      
      if (createdSnapshot.docs.isNotEmpty) return true;
      
      // Check for attended events
      final attendedSnapshot = await _firestore
          .collection('Attendance')
          .where('customerUid', isEqualTo: userId)
          .where('attendanceDateTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('attendanceDateTime', isLessThan: Timestamp.fromDate(endDate))
          .limit(1)
          .get();
      
      return attendedSnapshot.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Get leaderboard of top badges
  Future<List<BadgeModel>> getBadgeLeaderboard({int limit = 10}) async {
    try {
      final snapshot = await _firestore
          .collection(BadgeModel.firebaseKey)
          .orderBy('totalPoints', descending: true)
          .limit(limit)
          .get();
      
      return snapshot.docs
          .map((doc) => BadgeModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      throw Exception('Failed to get badge leaderboard: $e');
    }
  }

  /// Update badge when user performs an action
  Future<void> updateBadgeForActivity(String userId, String activity) async {
    try {
      // Refresh badge statistics
      await createOrUpdateUserBadge(userId);
    } catch (e) {
      // Silently fail to avoid disrupting user experience
      print('Failed to update badge for activity: $e');
    }
  }
}