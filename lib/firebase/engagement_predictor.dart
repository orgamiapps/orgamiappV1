import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/models/event_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:attendus/Utils/logger.dart';

class EngagementPredictor {
  static const double engagementBoostWeight = 0.15;

  /// Predict engagement score for an event based on user behavior patterns
  static Future<double> predictEngagementScore(EventModel event) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return 0.5; // Neutral score for anonymous users

      // Get user's engagement history
      Map<String, dynamic> engagementHistory = await _getUserEngagementHistory(
        user.uid,
      );

      // Calculate engagement score based on multiple factors
      double categoryEngagement = _calculateCategoryEngagement(
        event,
        engagementHistory,
      );
      double timeEngagement = _calculateTimeEngagement(
        event,
        engagementHistory,
      );
      double locationEngagement = _calculateLocationEngagement(
        event,
        engagementHistory,
      );
      double socialEngagement = _calculateSocialEngagement(
        event,
        engagementHistory,
      );

      // Weighted average of engagement factors
      double engagementScore =
          (categoryEngagement * 0.4) +
          (timeEngagement * 0.25) +
          (locationEngagement * 0.2) +
          (socialEngagement * 0.15);

      return engagementScore;
    } catch (e) {
      Logger.error('Error predicting engagement: $e');
      return 0.5; // Neutral score on error
    }
  }

  /// Get user's engagement history from Firestore
  static Future<Map<String, dynamic>> _getUserEngagementHistory(
    String userId,
  ) async {
    try {
      // Get past event interactions
      QuerySnapshot interactions = await FirebaseFirestore.instance
          .collection('EventInteractions')
          .where('userId', isEqualTo: userId)
          .get();

      Map<String, dynamic> history = {
        'categoryInteractions': <String, int>{},
        'timeInteractions': <String, int>{},
        'locationInteractions': <String, int>{},
        'socialInteractions': <String, int>{},
        'totalInteractions': 0,
      };

      for (var doc in interactions.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        String eventId = data['eventId'];
        // String interactionType = data['interactionType'] ?? 'view'; // Unused variable

        // Get event details
        DocumentSnapshot eventDoc = await FirebaseFirestore.instance
            .collection(EventModel.firebaseKey)
            .doc(eventId)
            .get();

        if (eventDoc.exists) {
          EventModel event = EventModel.fromJson(
            eventDoc.data() as Map<String, dynamic>,
          );

          // Track category interactions
          for (String category in event.categories) {
            history['categoryInteractions'][category] =
                (history['categoryInteractions'][category] ?? 0) + 1;
          }

          // Track time interactions (time of day)
          String timeSlot = _getTimeSlot(event.selectedDateTime.hour);
          history['timeInteractions'][timeSlot] =
              (history['timeInteractions'][timeSlot] ?? 0) + 1;

          // Track location interactions (distance-based)
          String locationZone = _getLocationZone(
            event.latitude,
            event.longitude,
          );
          history['locationInteractions'][locationZone] =
              (history['locationInteractions'][locationZone] ?? 0) + 1;

          // Track social interactions (events with more attendees)
          String socialLevel = _getSocialLevel(
            event.issuedTickets,
            event.maxTickets,
          );
          history['socialInteractions'][socialLevel] =
              (history['socialInteractions'][socialLevel] ?? 0) + 1;

          history['totalInteractions']++;
        }
      }

      return history;
    } catch (e) {
      Logger.error('Error getting engagement history: $e');
      return {
        'categoryInteractions': <String, int>{},
        'timeInteractions': <String, int>{},
        'locationInteractions': <String, int>{},
        'socialInteractions': <String, int>{},
        'totalInteractions': 0,
      };
    }
  }

  /// Calculate category engagement score
  static double _calculateCategoryEngagement(
    EventModel event,
    Map<String, dynamic> history,
  ) {
    if (history['totalInteractions'] == 0) return 0.5;

    int totalCategoryInteractions = 0;
    int matchingCategoryInteractions = 0;

    for (String category in event.categories) {
      int interactions = history['categoryInteractions'][category] ?? 0;
      totalCategoryInteractions += interactions;
      matchingCategoryInteractions += interactions;
    }

    if (totalCategoryInteractions == 0) return 0.5;

    return matchingCategoryInteractions / totalCategoryInteractions;
  }

  /// Calculate time engagement score
  static double _calculateTimeEngagement(
    EventModel event,
    Map<String, dynamic> history,
  ) {
    if (history['totalInteractions'] == 0) return 0.5;

    String eventTimeSlot = _getTimeSlot(event.selectedDateTime.hour);
    int timeInteractions = history['timeInteractions'][eventTimeSlot] ?? 0;

    return timeInteractions / history['totalInteractions'];
  }

  /// Calculate location engagement score
  static double _calculateLocationEngagement(
    EventModel event,
    Map<String, dynamic> history,
  ) {
    if (history['totalInteractions'] == 0) return 0.5;

    String eventLocationZone = _getLocationZone(
      event.latitude,
      event.longitude,
    );
    int locationInteractions =
        history['locationInteractions'][eventLocationZone] ?? 0;

    return locationInteractions / history['totalInteractions'];
  }

  /// Calculate social engagement score
  static double _calculateSocialEngagement(
    EventModel event,
    Map<String, dynamic> history,
  ) {
    if (history['totalInteractions'] == 0) return 0.5;

    String eventSocialLevel = _getSocialLevel(
      event.issuedTickets,
      event.maxTickets,
    );
    int socialInteractions =
        history['socialInteractions'][eventSocialLevel] ?? 0;

    return socialInteractions / history['totalInteractions'];
  }

  /// Get time slot for engagement analysis
  static String _getTimeSlot(int hour) {
    if (hour >= 6 && hour < 12) return 'morning';
    if (hour >= 12 && hour < 17) return 'afternoon';
    if (hour >= 17 && hour < 21) return 'evening';
    return 'night';
  }

  /// Get location zone for engagement analysis
  static String _getLocationZone(double latitude, double longitude) {
    // Simplified location zones based on coordinates
    // In a real app, you might use geohashing or city-based zones
    if (latitude == 0 || longitude == 0) return 'unknown';

    // Simple zone calculation (this is a simplified approach)
    final int latZone = (latitude * 10).round();
    final int lonZone = (longitude * 10).round();
    return 'zone_${latZone}_$lonZone';
  }

  /// Get social level based on ticket sales
  static String _getSocialLevel(int issuedTickets, int maxTickets) {
    if (maxTickets == 0) return 'unknown';

    double ratio = issuedTickets / maxTickets;
    if (ratio >= 0.8) return 'high';
    if (ratio >= 0.5) return 'medium';
    return 'low';
  }

  /// Apply engagement boost to event score
  static double applyEngagementBoost(double baseScore, double engagementScore) {
    return baseScore + (engagementScore * engagementBoostWeight);
  }

  /// Track user interaction with an event
  static Future<void> trackInteraction(
    String eventId,
    String interactionType,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance.collection('EventInteractions').add({
        'userId': user.uid,
        'eventId': eventId,
        'interactionType': interactionType,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      Logger.error('Error tracking interaction: $e');
    }
  }
}
