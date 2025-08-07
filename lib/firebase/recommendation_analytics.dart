import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:orgami/Utils/logger.dart';

class RecommendationAnalytics {
  /// Track when recommendations are shown to a user
  static Future<void> trackRecommendationsShown({
    required List<String> eventIds,
    required String searchQuery,
    List<String>? categories,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('RecommendationAnalytics')
          .add({
            'userId': user.uid,
            'eventIds': eventIds,
            'searchQuery': searchQuery,
            'categories': categories ?? [],
            'timestamp': FieldValue.serverTimestamp(),
            'type': 'recommendations_shown',
          });
    } catch (e) {
      Logger.error('Error tracking recommendations shown: $e');
    }
  }

  /// Track when a user interacts with a recommended event
  static Future<void> trackRecommendationInteraction({
    required String eventId,
    required String interactionType,
    required int position, // Position in recommendation list
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('RecommendationAnalytics')
          .add({
            'userId': user.uid,
            'eventId': eventId,
            'interactionType': interactionType,
            'position': position,
            'timestamp': FieldValue.serverTimestamp(),
            'type': 'recommendation_interaction',
          });
    } catch (e) {
      Logger.error('Error tracking recommendation interaction: $e');
    }
  }

  /// Track recommendation performance metrics
  static Future<void> trackRecommendationPerformance({
    required String eventId,
    required double recommendationScore,
    required String interactionType,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('RecommendationPerformance')
          .add({
            'userId': user.uid,
            'eventId': eventId,
            'recommendationScore': recommendationScore,
            'interactionType': interactionType,
            'timestamp': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      Logger.error('Error tracking recommendation performance: $e');
    }
  }

  /// Get recommendation performance insights
  static Future<Map<String, dynamic>> getRecommendationInsights() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return {};

      // Get recent recommendation interactions
      QuerySnapshot interactions = await FirebaseFirestore.instance
          .collection('RecommendationAnalytics')
          .where('userId', isEqualTo: user.uid)
          .where('type', isEqualTo: 'recommendation_interaction')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();

      // Get performance data
      QuerySnapshot performance = await FirebaseFirestore.instance
          .collection('RecommendationPerformance')
          .where('userId', isEqualTo: user.uid)
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();

      Map<String, dynamic> insights = {
        'totalInteractions': interactions.docs.length,
        'interactionTypes': <String, int>{},
        'averageScore': 0.0,
        'topCategories': <String, int>{},
        'engagementRate': 0.0,
      };

      // Analyze interaction types
      for (var doc in interactions.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        String interactionType = data['interactionType'] ?? 'unknown';
        insights['interactionTypes'][interactionType] =
            (insights['interactionTypes'][interactionType] ?? 0) + 1;
      }

      // Calculate average recommendation score
      if (performance.docs.isNotEmpty) {
        double totalScore = 0.0;
        for (var doc in performance.docs) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          totalScore += data['recommendationScore'] ?? 0.0;
        }
        insights['averageScore'] = totalScore / performance.docs.length;
      }

      // Calculate engagement rate (interactions / total recommendations shown)
      QuerySnapshot recommendationsShown = await FirebaseFirestore.instance
          .collection('RecommendationAnalytics')
          .where('userId', isEqualTo: user.uid)
          .where('type', isEqualTo: 'recommendations_shown')
          .get();

      int totalRecommendations = 0;
      for (var doc in recommendationsShown.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        List<String> eventIds = List<String>.from(data['eventIds'] ?? []);
        totalRecommendations += eventIds.length;
      }

      if (totalRecommendations > 0) {
        insights['engagementRate'] =
            interactions.docs.length / totalRecommendations;
      }

      return insights;
    } catch (e) {
      Logger.error('Error getting recommendation insights: $e');
      return {};
    }
  }

  /// Track user feedback on recommendations
  static Future<void> trackRecommendationFeedback({
    required String eventId,
    required String feedbackType, // 'like', 'dislike', 'not_interested'
    String? reason,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('RecommendationFeedback')
          .add({
            'userId': user.uid,
            'eventId': eventId,
            'feedbackType': feedbackType,
            'reason': reason,
            'timestamp': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      Logger.error('Error tracking recommendation feedback: $e');
    }
  }
}
