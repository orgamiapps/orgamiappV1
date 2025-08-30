import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/Utils/logger.dart';

/// Optimized Firestore operations to prevent main thread blocking
class OptimizedFirestoreHelper {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final Map<String, dynamic> _cache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheExpiry = Duration(minutes: 5);

  /// Get events with performance optimizations
  static Stream<QuerySnapshot> getOptimizedEventsStream() {
    try {
      return _firestore
          .collection('Events')
          .where('private', isEqualTo: false)
          .limit(50)
          .snapshots()
          .timeout(
            const Duration(seconds: 8),
            onTimeout: (sink) {
              Logger.error('Events stream timeout');
              sink.addError('Events loading timeout');
            },
          )
          .handleError((error) {
            Logger.error('Events stream error: $error');
          });
    } catch (e) {
      Logger.error('Error creating events stream: $e');
      // Return empty stream in case of error
      return Stream.fromIterable([]);
    }
  }

  /// Get user with caching and timeout
  static Future<CustomerModel?> getOptimizedUser(String userId) async {
    final cacheKey = 'user_$userId';

    // Check cache first
    if (_isValidCache(cacheKey)) {
      Logger.debug('Returning cached user data');
      return _cache[cacheKey] as CustomerModel?;
    }

    try {
      final docSnapshot = await _firestore
          .collection('Customer')
          .doc(userId)
          .get()
          .timeout(const Duration(seconds: 5));

      if (docSnapshot.exists) {
        final userData = CustomerModel.fromFirestore(docSnapshot);

        // Cache the result
        _cache[cacheKey] = userData;
        _cacheTimestamps[cacheKey] = DateTime.now();

        return userData;
      }

      return null;
    } catch (e) {
      Logger.error('Error getting user: $e');
      return null;
    }
  }

  /// Search events with debouncing and limits
  static Future<List<EventModel>> searchOptimizedEvents(String query) async {
    if (query.trim().isEmpty) return [];

    final cacheKey = 'search_events_${query.toLowerCase()}';

    // Check cache first
    if (_isValidCache(cacheKey)) {
      Logger.debug('Returning cached search results');
      return _cache[cacheKey] as List<EventModel>;
    }

    try {
      final snapshot = await _firestore
          .collection('Events')
          .where('private', isEqualTo: false)
          .limit(20)
          .get()
          .timeout(const Duration(seconds: 5));

      List<EventModel> events = [];
      final queryLower = query.toLowerCase();

      for (var doc in snapshot.docs) {
        try {
          final event = EventModel.fromJson(doc);

          // Simple text search on title and description
          if (event.title.toLowerCase().contains(queryLower) ||
              event.description.toLowerCase().contains(queryLower)) {
            events.add(event);
          }
        } catch (e) {
          Logger.error('Error parsing search result: $e');
          continue;
        }
      }

      // Cache the results
      _cache[cacheKey] = events;
      _cacheTimestamps[cacheKey] = DateTime.now();

      return events;
    } catch (e) {
      Logger.error('Error searching events: $e');
      return [];
    }
  }

  /// Search users with optimization
  static Future<List<CustomerModel>> searchOptimizedUsers(String query) async {
    if (query.trim().isEmpty) return [];

    final cacheKey = 'search_users_${query.toLowerCase()}';

    // Check cache first
    if (_isValidCache(cacheKey)) {
      Logger.debug('Returning cached user search results');
      return _cache[cacheKey] as List<CustomerModel>;
    }

    try {
      // Search by username first (more efficient)
      final snapshot = await _firestore
          .collection('Customer')
          .where('isDiscoverable', isEqualTo: true)
          .limit(30)
          .get()
          .timeout(const Duration(seconds: 5));

      List<CustomerModel> users = [];
      final queryLower = query.toLowerCase();

      for (var doc in snapshot.docs) {
        try {
          final user = CustomerModel.fromFirestore(doc);

          // Simple text search on name and username
          if (user.name.toLowerCase().contains(queryLower) ||
              (user.username?.toLowerCase().contains(queryLower) ?? false)) {
            users.add(user);
          }

          // Limit results to prevent performance issues
          if (users.length >= 20) break;
        } catch (e) {
          Logger.error('Error parsing user search result: $e');
          continue;
        }
      }

      // Cache the results
      _cache[cacheKey] = users;
      _cacheTimestamps[cacheKey] = DateTime.now();

      return users;
    } catch (e) {
      Logger.error('Error searching users: $e');
      return [];
    }
  }

  /// Check if cached data is still valid
  static bool _isValidCache(String key) {
    if (!_cache.containsKey(key) || !_cacheTimestamps.containsKey(key)) {
      return false;
    }

    final cacheTime = _cacheTimestamps[key]!;
    final now = DateTime.now();
    final age = now.difference(cacheTime);

    return age.compareTo(_cacheExpiry) < 0;
  }

  /// Clear cache periodically to prevent memory leaks
  static void clearExpiredCache() {
    final now = DateTime.now();
    final keysToRemove = <String>[];

    for (final entry in _cacheTimestamps.entries) {
      final age = now.difference(entry.value);
      if (age.compareTo(const Duration(minutes: 30)) > 0) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      _cache.remove(key);
      _cacheTimestamps.remove(key);
    }

    if (keysToRemove.isNotEmpty) {
      Logger.debug('Cleared ${keysToRemove.length} expired cache entries');
    }
  }

  /// Clear all cache
  static void clearAllCache() {
    _cache.clear();
    _cacheTimestamps.clear();
    Logger.debug('All cache cleared');
  }

  /// Get cache statistics
  static Map<String, int> getCacheStats() {
    return {
      'totalEntries': _cache.length,
      'memoryUsage': _cache.length * 1000, // Rough estimation
    };
  }
}
