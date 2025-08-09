import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/badge_model.dart';
import '../models/customer_model.dart';
import '../models/event_model.dart';
import '../models/attendance_model.dart';

class BadgeService {
  static final BadgeService _instance = BadgeService._internal();
  factory BadgeService() => _instance;
  BadgeService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Generate or update badge for a user
  Future<UserBadgeModel?> generateUserBadge(String userId) async {
    try {
      debugPrint('Generating badge for user: $userId');

      // Get user information
      final userDoc = await _firestore
          .collection(CustomerModel.firebaseKey)
          .doc(userId)
          .get();

      if (!userDoc.exists) {
        debugPrint('User not found: $userId');
        return null;
      }

      final userData = CustomerModel.fromFirestore(userDoc);
      
      // Calculate user statistics
      final stats = await _calculateUserStatistics(userId);
      
      // Create badge model
      final badge = UserBadgeModel.createFromUserData(
        uid: userId,
        userName: userData.name,
        email: userData.email,
        profileImageUrl: userData.profilePictureUrl,
        occupation: userData.occupation,
        location: userData.location,
        memberSince: userData.createdAt,
        eventsCreated: stats['eventsCreated'] ?? 0,
        eventsAttended: stats['eventsAttended'] ?? 0,
        totalDwellHours: stats['totalDwellHours'] ?? 0.0,
      );

      // Save badge to Firestore
      await _saveBadgeToFirestore(badge);
      
      debugPrint('Badge generated successfully for ${userData.name}');
      return badge;

    } catch (e) {
      debugPrint('Error generating badge: $e');
      return null;
    }
  }

  /// Calculate comprehensive user statistics
  Future<Map<String, dynamic>> _calculateUserStatistics(String userId) async {
    try {
      debugPrint('Calculating statistics for user: $userId');

      // Get events created by user
      final createdEventsQuery = await _firestore
          .collection(EventModel.firebaseKey)
          .where('customerUid', isEqualTo: userId)
          .get();

      final eventsCreated = createdEventsQuery.docs.length;
      debugPrint('Events created: $eventsCreated');

      // Get events attended by user
      final attendanceQuery = await _firestore
          .collection(AttendanceModel.firebaseKey)
          .where('customerUid', isEqualTo: userId)
          .get();

      final eventsAttended = attendanceQuery.docs.length;
      debugPrint('Events attended: $eventsAttended');

      // Calculate total dwell time
      double totalDwellHours = 0.0;
      for (final doc in attendanceQuery.docs) {
        final attendance = AttendanceModel.fromJson(doc);
        if (attendance.dwellTime != null) {
          totalDwellHours += attendance.dwellTime!.inMinutes / 60.0;
        }
      }
      
      debugPrint('Total dwell hours: $totalDwellHours');

      // Get unique events attended (to avoid counting multiple check-ins)
      final uniqueEventIds = <String>{};
      for (final doc in attendanceQuery.docs) {
        final attendance = AttendanceModel.fromJson(doc);
        uniqueEventIds.add(attendance.eventId);
      }
      final uniqueEventsAttended = uniqueEventIds.length;

      return {
        'eventsCreated': eventsCreated,
        'eventsAttended': uniqueEventsAttended,
        'totalDwellHours': totalDwellHours,
        'totalAttendanceRecords': eventsAttended,
      };

    } catch (e) {
      debugPrint('Error calculating statistics: $e');
      return {
        'eventsCreated': 0,
        'eventsAttended': 0,
        'totalDwellHours': 0.0,
        'totalAttendanceRecords': 0,
      };
    }
  }

  /// Save badge to Firestore
  Future<void> _saveBadgeToFirestore(UserBadgeModel badge) async {
    try {
      await _firestore
          .collection(UserBadgeModel.firebaseKey)
          .doc(badge.uid)
          .set(badge.toMap(), SetOptions(merge: true));
      
      debugPrint('Badge saved to Firestore for ${badge.userName}');
    } catch (e) {
      debugPrint('Error saving badge to Firestore: $e');
      rethrow;
    }
  }

  /// Get existing badge for user
  Future<UserBadgeModel?> getUserBadge(String userId) async {
    try {
      final doc = await _firestore
          .collection(UserBadgeModel.firebaseKey)
          .doc(userId)
          .get();

      if (!doc.exists) {
        debugPrint('Badge not found for user: $userId');
        return null;
      }

      return UserBadgeModel.fromFirestore(doc);
    } catch (e) {
      debugPrint('Error getting user badge: $e');
      return null;
    }
  }

  /// Get or generate badge for user
  Future<UserBadgeModel?> getOrGenerateBadge(String userId) async {
    try {
      // Try to get existing badge
      UserBadgeModel? badge = await getUserBadge(userId);
      
      if (badge != null) {
        // Check if badge needs updating (older than 24 hours)
        final now = DateTime.now();
        final daysSinceUpdate = now.difference(badge.lastUpdated).inDays;
        
        if (daysSinceUpdate >= 1) {
          debugPrint('Badge needs updating, regenerating...');
          badge = await generateUserBadge(userId);
        }
      } else {
        // Generate new badge
        debugPrint('No existing badge found, generating new one...');
        badge = await generateUserBadge(userId);
      }
      
      return badge;
    } catch (e) {
      debugPrint('Error in getOrGenerateBadge: $e');
      return null;
    }
  }

  /// Update badge statistics after user activity
  Future<void> updateBadgeAfterActivity(String userId, String activityType) async {
    try {
      debugPrint('Updating badge after activity: $activityType for user: $userId');
      
      // Simply regenerate the badge with current stats
      await generateUserBadge(userId);
      
    } catch (e) {
      debugPrint('Error updating badge after activity: $e');
    }
  }

  /// Get leaderboard data
  Future<List<UserBadgeModel>> getLeaderboard({int limit = 10}) async {
    try {
      final query = await _firestore
          .collection(UserBadgeModel.firebaseKey)
          .orderBy('eventsCreated', descending: true)
          .limit(limit)
          .get();

      return query.docs.map((doc) => UserBadgeModel.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('Error getting leaderboard: $e');
      return [];
    }
  }

  /// Delete user badge
  Future<void> deleteBadge(String userId) async {
    try {
      await _firestore
          .collection(UserBadgeModel.firebaseKey)
          .doc(userId)
          .delete();
      
      debugPrint('Badge deleted for user: $userId');
    } catch (e) {
      debugPrint('Error deleting badge: $e');
      rethrow;
    }
  }

  /// Bulk update badges for all users (admin function)
  Future<void> bulkUpdateAllBadges() async {
    try {
      debugPrint('Starting bulk badge update...');
      
      // Get all users
      final usersQuery = await _firestore
          .collection(CustomerModel.firebaseKey)
          .get();

      for (final userDoc in usersQuery.docs) {
        try {
          await generateUserBadge(userDoc.id);
          debugPrint('Updated badge for user: ${userDoc.id}');
        } catch (e) {
          debugPrint('Error updating badge for user ${userDoc.id}: $e');
          continue;
        }
      }
      
      debugPrint('Bulk badge update completed');
    } catch (e) {
      debugPrint('Error in bulk badge update: $e');
      rethrow;
    }
  }

  /// Get badge statistics summary
  Future<Map<String, dynamic>> getBadgeStatistics() async {
    try {
      final query = await _firestore
          .collection(UserBadgeModel.firebaseKey)
          .get();

      final badges = query.docs.map((doc) => UserBadgeModel.fromFirestore(doc)).toList();
      
      final levelCounts = <String, int>{};
      var totalEventsCreated = 0;
      var totalEventsAttended = 0;
      var totalDwellHours = 0.0;

      for (final badge in badges) {
        levelCounts[badge.badgeLevel] = (levelCounts[badge.badgeLevel] ?? 0) + 1;
        totalEventsCreated += badge.eventsCreated;
        totalEventsAttended += badge.eventsAttended;
        totalDwellHours += badge.totalDwellHours;
      }

      return {
        'totalBadges': badges.length,
        'levelDistribution': levelCounts,
        'totalEventsCreated': totalEventsCreated,
        'totalEventsAttended': totalEventsAttended,
        'totalDwellHours': totalDwellHours,
        'averageEventsPerUser': badges.isNotEmpty ? totalEventsCreated / badges.length : 0,
      };
    } catch (e) {
      debugPrint('Error getting badge statistics: $e');
      return {};
    }
  }
}
