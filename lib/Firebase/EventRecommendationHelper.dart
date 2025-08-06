import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Models/CustomerModel.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Firebase/EngagementPredictor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

class EventRecommendationHelper {
  static const double LOCATION_WEIGHT = 0.25;
  static const double PERSONALIZATION_WEIGHT = 0.35;
  static const double POPULARITY_WEIGHT = 0.20;
  static const double RECENCY_WEIGHT = 0.10;
  static const double FEATURED_WEIGHT = 0.10;

  // Cache for user preferences and location
  static Map<String, dynamic>? _userPreferencesCache;
  static Position? _userLocationCache;
  static DateTime? _lastCacheUpdate;

  /// Get personalized event recommendations
  static Future<List<EventModel>> getPersonalizedRecommendations({
    required String searchQuery,
    List<String>? categories,
    int limit = 50,
  }) async {
    try {
      // Get current user
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return await _getBasicRecommendations(searchQuery, categories, limit);
      }

      // Fetch events from Firestore
      List<EventModel> events = await _fetchEventsFromFirestore(
        searchQuery,
        categories,
      );

      if (events.isEmpty) {
        return [];
      }

      // Get user preferences and location
      Map<String, dynamic> userPreferences = await _getUserPreferences(
        user.uid,
      );
      Position? userLocation = await _getUserLocation();

      // Calculate personalized scores
      List<EventScore> scoredEvents = [];

      for (EventModel event in events) {
        double score = await _calculatePersonalizedScore(
          event: event,
          userPreferences: userPreferences,
          userLocation: userLocation,
        );

        scoredEvents.add(EventScore(event: event, score: score));
      }

      // Sort by score (descending) and return top events
      scoredEvents.sort((a, b) => b.score.compareTo(a.score));

      return scoredEvents
          .take(limit)
          .map((scoredEvent) => scoredEvent.event)
          .toList();
    } catch (e) {
      print('Error in getPersonalizedRecommendations: $e');
      return await _getBasicRecommendations(searchQuery, categories, limit);
    }
  }

  /// Fetch events from Firestore based on search query and categories
  static Future<List<EventModel>> _fetchEventsFromFirestore(
    String searchQuery,
    List<String>? categories,
  ) async {
    try {
      // Create a Timestamp for the comparison (3 hours ago)
      final threeHoursAgo = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(hours: 3)),
      );

      print(
        'DEBUG: EventRecommendationHelper - Loading events with cutoff time: ${threeHoursAgo.toDate()}',
      );

      Query query = FirebaseFirestore.instance
          .collection(EventModel.firebaseKey)
          .where('private', isEqualTo: false)
          .where('selectedDateTime', isGreaterThan: threeHoursAgo);

      // Apply search filter if provided
      if (searchQuery.isNotEmpty) {
        // Note: Firestore doesn't support full-text search, so we'll filter in memory
        // In a production app, consider using Algolia or similar for better search
      }

      // Apply category filter if provided
      if (categories != null && categories.isNotEmpty) {
        query = query.where('categories', arrayContainsAny: categories);
      }

      QuerySnapshot snapshot = await query.get();

      print(
        'DEBUG: EventRecommendationHelper - Found ${snapshot.docs.length} events from Firestore query',
      );

      List<EventModel> events = snapshot.docs
          .map((doc) => EventModel.fromJson(doc.data() as Map<String, dynamic>))
          .toList();

      // Additional client-side filtering to ensure no past events slip through
      // Filter out events that ended more than 2 hours ago
      final beforeFilterCount = events.length;
      events = events.where((event) {
        final eventEndTime = event.selectedDateTime.add(
          Duration(hours: event.eventDuration),
        );
        final cutoffTime = DateTime.now().subtract(const Duration(hours: 2));
        final shouldInclude = eventEndTime.isAfter(cutoffTime);

        if (!shouldInclude) {
          print(
            'DEBUG: EventRecommendationHelper - Filtering out past event: ${event.title} (${event.selectedDateTime}) - End time: $eventEndTime, Cutoff: $cutoffTime',
          );
        }

        return shouldInclude;
      }).toList();

      print(
        'DEBUG: EventRecommendationHelper - After client-side filtering: ${events.length} events (filtered out ${beforeFilterCount - events.length})',
      );

      // Apply search filter in memory if needed
      if (searchQuery.isNotEmpty) {
        events = events
            .where(
              (event) =>
                  event.title.toLowerCase().contains(
                    searchQuery.toLowerCase(),
                  ) ||
                  event.description.toLowerCase().contains(
                    searchQuery.toLowerCase(),
                  ),
            )
            .toList();
      }

      return events;
    } catch (e) {
      print('Error fetching events from Firestore: $e');
      return [];
    }
  }

  /// Calculate personalized score for an event
  static Future<double> _calculatePersonalizedScore({
    required EventModel event,
    required Map<String, dynamic> userPreferences,
    Position? userLocation,
  }) async {
    double locationScore = await _calculateLocationScore(event, userLocation);
    double personalizationScore = _calculatePersonalizationScore(
      event,
      userPreferences,
    );
    double popularityScore = _calculatePopularityScore(event);
    double recencyScore = _calculateRecencyScore(event);
    double featuredScore = _calculateFeaturedScore(event);

    // Calculate base weighted score
    double baseScore =
        (locationScore * LOCATION_WEIGHT) +
        (personalizationScore * PERSONALIZATION_WEIGHT) +
        (popularityScore * POPULARITY_WEIGHT) +
        (recencyScore * RECENCY_WEIGHT) +
        (featuredScore * FEATURED_WEIGHT);

    // Apply ML-based engagement prediction boost
    double engagementScore = await EngagementPredictor.predictEngagementScore(
      event,
    );
    double finalScore = EngagementPredictor.applyEngagementBoost(
      baseScore,
      engagementScore,
    );

    return finalScore;
  }

  /// Calculate location-based score (inverse distance)
  static Future<double> _calculateLocationScore(
    EventModel event,
    Position? userLocation,
  ) async {
    if (userLocation == null || event.latitude == 0 || event.longitude == 0) {
      return 0.5; // Neutral score if location data unavailable
    }

    try {
      double distance = Geolocator.distanceBetween(
        userLocation.latitude,
        userLocation.longitude,
        event.latitude,
        event.longitude,
      );

      // Convert distance to score (closer = higher score)
      // Max distance considered: 100km, min score: 0.1, max score: 1.0
      const double maxDistance = 100000; // 100km in meters
      double normalizedDistance = distance / maxDistance;
      double score = 1.0 - normalizedDistance;

      // Ensure minimum score
      return max(0.1, score);
    } catch (e) {
      print('Error calculating location score: $e');
      return 0.5;
    }
  }

  /// Calculate personalization score based on user preferences
  static double _calculatePersonalizationScore(
    EventModel event,
    Map<String, dynamic> userPreferences,
  ) {
    double score = 0.0;

    // Category preference matching
    List<String> userPreferredCategories =
        userPreferences['preferredCategories'] ?? [];
    if (userPreferredCategories.isNotEmpty) {
      int matchingCategories = event.categories
          .where((category) => userPreferredCategories.contains(category))
          .length;
      score += (matchingCategories / userPreferredCategories.length) * 0.4;
    }

    // Past attendance pattern
    List<String> userPastEventIds = userPreferences['pastEventIds'] ?? [];
    List<String> userPastCategories = userPreferences['pastCategories'] ?? [];

    // Check if user attended similar events
    int similarPastEvents = userPastCategories
        .where((category) => event.categories.contains(category))
        .length;
    score += (similarPastEvents / max(userPastCategories.length, 1)) * 0.3;

    // Time preference matching
    String? userTimePreference = userPreferences['timePreference'];
    if (userTimePreference != null) {
      int eventHour = event.selectedDateTime.hour;
      bool matchesTimePreference = _matchesTimePreference(
        eventHour,
        userTimePreference,
      );
      score += matchesTimePreference ? 0.2 : 0.0;
    }

    // Day of week preference
    String? userDayPreference = userPreferences['dayPreference'];
    if (userDayPreference != null) {
      String eventDay = _getDayOfWeek(event.selectedDateTime);
      bool matchesDayPreference = userDayPreference == eventDay;
      score += matchesDayPreference ? 0.1 : 0.0;
    }

    return min(1.0, score);
  }

  /// Calculate popularity score based on attendees and ratings
  static double _calculatePopularityScore(EventModel event) {
    double score = 0.0;

    // Ticket sales ratio (if tickets enabled)
    if (event.ticketsEnabled && event.maxTickets > 0) {
      double salesRatio = event.issuedTickets / event.maxTickets;
      score += salesRatio * 0.5;
    }

    // Featured status boost
    if (event.isFeatured) {
      score += 0.3;
    }

    // Recency boost (newer events get slight boost)
    int daysSinceCreation = DateTime.now()
        .difference(event.eventGenerateTime)
        .inDays;
    if (daysSinceCreation <= 7) {
      score += 0.2;
    }

    return min(1.0, score);
  }

  /// Calculate recency score (upcoming events priority)
  static double _calculateRecencyScore(EventModel event) {
    int daysUntilEvent = event.selectedDateTime
        .difference(DateTime.now())
        .inDays;

    // Events happening soon get higher scores
    if (daysUntilEvent <= 1) return 1.0;
    if (daysUntilEvent <= 3) return 0.9;
    if (daysUntilEvent <= 7) return 0.8;
    if (daysUntilEvent <= 14) return 0.7;
    if (daysUntilEvent <= 30) return 0.6;

    return 0.5; // Default score for events further in the future
  }

  /// Calculate featured score
  static double _calculateFeaturedScore(EventModel event) {
    if (!event.isFeatured) return 0.0;

    // Check if feature is still active
    if (event.featureEndDate != null &&
        DateTime.now().isAfter(event.featureEndDate!)) {
      return 0.0;
    }

    return 1.0;
  }

  /// Get user preferences from Firestore
  static Future<Map<String, dynamic>> _getUserPreferences(String userId) async {
    // Check cache first
    if (_userPreferencesCache != null &&
        _lastCacheUpdate != null &&
        DateTime.now().difference(_lastCacheUpdate!).inMinutes < 30) {
      return _userPreferencesCache!;
    }

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection(CustomerModel.firebaseKey)
          .doc(userId)
          .get();

      if (!userDoc.exists) {
        return {};
      }

      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

      // Get user's past events
      QuerySnapshot pastEvents = await FirebaseFirestore.instance
          .collection('EventAttendance')
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'attended')
          .get();

      List<String> pastEventIds = pastEvents.docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .map((data) => data['eventId'] as String)
          .toList();

      // Get categories from past events
      List<String> pastCategories = [];
      if (pastEventIds.isNotEmpty) {
        QuerySnapshot pastEventDocs = await FirebaseFirestore.instance
            .collection(EventModel.firebaseKey)
            .where(FieldPath.documentId, whereIn: pastEventIds.take(10))
            .get();

        for (var doc in pastEventDocs.docs) {
          EventModel event = EventModel.fromJson(
            doc.data() as Map<String, dynamic>,
          );
          pastCategories.addAll(event.categories);
        }
      }

      // Analyze time preferences from past events
      String? timePreference = _analyzeTimePreference(pastEvents.docs);
      String? dayPreference = _analyzeDayPreference(pastEvents.docs);

      Map<String, dynamic> preferences = {
        'preferredCategories': _getMostFrequentCategories(pastCategories),
        'pastEventIds': pastEventIds,
        'pastCategories': pastCategories,
        'timePreference': timePreference,
        'dayPreference': dayPreference,
      };

      // Cache the results
      _userPreferencesCache = preferences;
      _lastCacheUpdate = DateTime.now();

      return preferences;
    } catch (e) {
      print('Error getting user preferences: $e');
      return {};
    }
  }

  /// Get user's current location
  static Future<Position?> _getUserLocation() async {
    // Check cache first
    if (_userLocationCache != null &&
        _lastCacheUpdate != null &&
        DateTime.now().difference(_lastCacheUpdate!).inMinutes < 30) {
      return _userLocationCache;
    }

    try {
      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Cache the location
      _userLocationCache = position;
      _lastCacheUpdate = DateTime.now();

      return position;
    } catch (e) {
      print('Error getting user location: $e');
      return null;
    }
  }

  /// Get basic recommendations without personalization
  static Future<List<EventModel>> _getBasicRecommendations(
    String searchQuery,
    List<String>? categories,
    int limit,
  ) async {
    try {
      List<EventModel> events = await _fetchEventsFromFirestore(
        searchQuery,
        categories,
      );

      // Sort by featured status and date
      events.sort((a, b) {
        // Featured events first
        if (a.isFeatured && !b.isFeatured) return -1;
        if (!a.isFeatured && b.isFeatured) return 1;

        // Then by date (upcoming first)
        return a.selectedDateTime.compareTo(b.selectedDateTime);
      });

      return events.take(limit).toList();
    } catch (e) {
      print('Error getting basic recommendations: $e');
      return [];
    }
  }

  /// Helper methods for preference analysis
  static List<String> _getMostFrequentCategories(List<String> categories) {
    Map<String, int> frequency = {};
    for (String category in categories) {
      frequency[category] = (frequency[category] ?? 0) + 1;
    }

    List<MapEntry<String, int>> sorted = frequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(3).map((entry) => entry.key).toList();
  }

  static String? _analyzeTimePreference(
    List<QueryDocumentSnapshot> pastEvents,
  ) {
    if (pastEvents.isEmpty) return null;

    Map<String, int> timeSlots = {};
    for (var doc in pastEvents) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      if (data['eventDateTime'] != null) {
        DateTime eventTime = (data['eventDateTime'] as Timestamp).toDate();
        String timeSlot = _getTimeSlot(eventTime.hour);
        timeSlots[timeSlot] = (timeSlots[timeSlot] ?? 0) + 1;
      }
    }

    if (timeSlots.isEmpty) return null;

    return timeSlots.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  static String? _analyzeDayPreference(List<QueryDocumentSnapshot> pastEvents) {
    if (pastEvents.isEmpty) return null;

    Map<String, int> days = {};
    for (var doc in pastEvents) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      if (data['eventDateTime'] != null) {
        DateTime eventTime = (data['eventDateTime'] as Timestamp).toDate();
        String day = _getDayOfWeek(eventTime);
        days[day] = (days[day] ?? 0) + 1;
      }
    }

    if (days.isEmpty) return null;

    return days.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  static String _getTimeSlot(int hour) {
    if (hour >= 6 && hour < 12) return 'morning';
    if (hour >= 12 && hour < 17) return 'afternoon';
    if (hour >= 17 && hour < 21) return 'evening';
    return 'night';
  }

  static String _getDayOfWeek(DateTime date) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return days[date.weekday - 1];
  }

  static bool _matchesTimePreference(int eventHour, String timePreference) {
    String eventTimeSlot = _getTimeSlot(eventHour);
    return eventTimeSlot == timePreference;
  }

  /// Clear cache (useful for testing or when user preferences change)
  static void clearCache() {
    _userPreferencesCache = null;
    _userLocationCache = null;
    _lastCacheUpdate = null;
  }
}

/// Helper class to hold event and its score
class EventScore {
  final EventModel event;
  final double score;

  EventScore({required this.event, required this.score});
}
