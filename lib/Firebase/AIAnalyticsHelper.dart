import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

// AI Insights Data Structure
class AIInsights {
  final Map<String, dynamic> peakHoursAnalysis;
  final Map<String, dynamic> sentimentAnalysis;
  final List<Map<String, dynamic>> optimizationPredictions;
  final Map<String, dynamic> dropoutAnalysis;
  final Map<String, dynamic> repeatAttendeeAnalysis;
  final DateTime lastUpdated;

  AIInsights({
    required this.peakHoursAnalysis,
    required this.sentimentAnalysis,
    required this.optimizationPredictions,
    required this.dropoutAnalysis,
    required this.repeatAttendeeAnalysis,
    required this.lastUpdated,
  });

  Map<String, dynamic> toMap() {
    return {
      'peakHoursAnalysis': peakHoursAnalysis,
      'sentimentAnalysis': sentimentAnalysis,
      'optimizationPredictions': optimizationPredictions,
      'dropoutAnalysis': dropoutAnalysis,
      'repeatAttendeeAnalysis': repeatAttendeeAnalysis,
      'lastUpdated': lastUpdated,
    };
  }

  factory AIInsights.fromMap(Map<String, dynamic> map) {
    return AIInsights(
      peakHoursAnalysis: Map<String, dynamic>.from(map['peakHoursAnalysis'] ?? {}),
      sentimentAnalysis: Map<String, dynamic>.from(map['sentimentAnalysis'] ?? {}),
      optimizationPredictions: List<Map<String, dynamic>>.from(map['optimizationPredictions'] ?? []),
      dropoutAnalysis: Map<String, dynamic>.from(map['dropoutAnalysis'] ?? {}),
      repeatAttendeeAnalysis: Map<String, dynamic>.from(map['repeatAttendeeAnalysis'] ?? {}),
      lastUpdated: (map['lastUpdated'] as Timestamp).toDate(),
    );
  }
}

class AIAnalyticsHelper {
  static final AIAnalyticsHelper _instance = AIAnalyticsHelper._internal();
  factory AIAnalyticsHelper() => _instance;
  AIAnalyticsHelper._internal();

  /// Analyze attendance timestamps for peak hours
  Future<Map<String, dynamic>> analyzePeakHours(Map<String, dynamic> hourlySignIns) async {
    try {
      if (hourlySignIns.isEmpty) {
        return {
          'peakHour': null,
          'peakCount': 0,
          'recommendation': 'Insufficient data for peak hour analysis',
          'confidence': 0.0,
        };
      }

      // Convert to list and sort by hour
      final sortedHours = hourlySignIns.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));

      // Find peak hour
      String peakHour = '';
      int peakCount = 0;
      for (final entry in sortedHours) {
        final count = (entry.value as num).toInt();
        if (count > peakCount) {
          peakCount = count;
          peakHour = entry.key;
        }
      }

      // Calculate confidence based on data distribution
      final totalSignIns = sortedHours.fold<int>(0, (sum, entry) => sum + (entry.value as num).toInt());
      final confidence = totalSignIns > 0 ? (peakCount / totalSignIns) : 0.0;

      // Generate recommendation
      String recommendation = '';
      if (peakHour.isNotEmpty) {
        final hour = int.tryParse(peakHour.split(':')[0]) ?? 0;
        if (hour >= 9 && hour <= 11) {
          recommendation = 'Morning events (9-11 AM) show highest engagement. Consider scheduling future events during this time.';
        } else if (hour >= 12 && hour <= 14) {
          recommendation = 'Lunch time (12-2 PM) is your peak period. Lunch-and-learn events could be highly successful.';
        } else if (hour >= 17 && hour <= 19) {
          recommendation = 'Evening hours (5-7 PM) are most popular. After-work events align well with attendee preferences.';
        } else {
          recommendation = 'Peak attendance at $peakHour. Consider this timing for future events.';
        }
      }

      return {
        'peakHour': peakHour,
        'peakCount': peakCount,
        'recommendation': recommendation,
        'confidence': confidence,
        'totalSignIns': totalSignIns,
        'hourlyDistribution': hourlySignIns,
      };
    } catch (e) {
      return {
        'error': 'Failed to analyze peak hours: $e',
        'peakHour': null,
        'peakCount': 0,
        'recommendation': 'Analysis failed',
        'confidence': 0.0,
      };
    }
  }

  /// Analyze comments for sentiment
  Future<Map<String, dynamic>> analyzeSentiment(List<Map<String, dynamic>> comments) async {
    try {
      if (comments.isEmpty) {
        return {
          'positiveRatio': 0.0,
          'negativeRatio': 0.0,
          'neutralRatio': 1.0,
          'overallSentiment': 'neutral',
          'recommendation': 'No comments available for sentiment analysis',
          'confidence': 0.0,
        };
      }

      int positiveCount = 0;
      int negativeCount = 0;
      int neutralCount = 0;

      // Simple keyword-based sentiment analysis
      final positiveKeywords = [
        'great', 'awesome', 'amazing', 'excellent', 'fantastic', 'wonderful',
        'good', 'nice', 'love', 'enjoy', 'happy', 'satisfied', 'impressed',
        'outstanding', 'brilliant', 'perfect', 'best', 'favorite', 'recommend'
      ];

      final negativeKeywords = [
        'bad', 'terrible', 'awful', 'horrible', 'disappointing', 'poor',
        'worst', 'hate', 'dislike', 'boring', 'waste', 'useless', 'frustrated',
        'angry', 'annoyed', 'confused', 'difficult', 'problem', 'issue'
      ];

      for (final comment in comments) {
        final text = (comment['text'] as String?)?.toLowerCase() ?? '';
        if (text.isEmpty) continue;

        int positiveScore = 0;
        int negativeScore = 0;

        for (final keyword in positiveKeywords) {
          if (text.contains(keyword)) positiveScore++;
        }

        for (final keyword in negativeKeywords) {
          if (text.contains(keyword)) negativeScore++;
        }

        if (positiveScore > negativeScore) {
          positiveCount++;
        } else if (negativeScore > positiveScore) {
          negativeCount++;
        } else {
          neutralCount++;
        }
      }

      final total = positiveCount + negativeCount + neutralCount;
      final positiveRatio = total > 0 ? positiveCount / total : 0.0;
      final negativeRatio = total > 0 ? negativeCount / total : 0.0;
      final neutralRatio = total > 0 ? neutralCount / total : 0.0;

      String overallSentiment = 'neutral';
      if (positiveRatio > 0.6) {
        overallSentiment = 'positive';
      } else if (negativeRatio > 0.6) {
        overallSentiment = 'negative';
      }

      String recommendation = '';
      if (overallSentiment == 'positive') {
        recommendation = 'Excellent feedback! Attendees are highly satisfied. Consider expanding similar event formats.';
      } else if (overallSentiment == 'negative') {
        recommendation = 'Address attendee concerns. Consider gathering more detailed feedback to improve future events.';
      } else {
        recommendation = 'Mixed feedback received. Consider implementing feedback surveys to better understand attendee needs.';
      }

      return {
        'positiveRatio': positiveRatio,
        'negativeRatio': negativeRatio,
        'neutralRatio': neutralRatio,
        'overallSentiment': overallSentiment,
        'recommendation': recommendation,
        'confidence': total > 0 ? 0.8 : 0.0,
        'totalComments': total,
        'positiveCount': positiveCount,
        'negativeCount': negativeCount,
        'neutralCount': neutralCount,
      };
    } catch (e) {
      return {
        'error': 'Failed to analyze sentiment: $e',
        'positiveRatio': 0.0,
        'negativeRatio': 0.0,
        'neutralRatio': 1.0,
        'overallSentiment': 'neutral',
        'recommendation': 'Analysis failed',
        'confidence': 0.0,
      };
    }
  }

  /// Generate optimization predictions
  Future<List<Map<String, dynamic>>> generateOptimizations(
    Map<String, dynamic> analyticsData,
    Map<String, dynamic> peakHoursAnalysis,
    Map<String, dynamic> sentimentAnalysis,
  ) async {
    try {
      final optimizations = <Map<String, dynamic>>[];

      // Analyze attendance patterns
      final totalAttendees = analyticsData['totalAttendees'] ?? 0;
      final dropoutRate = analyticsData['dropoutRate'] ?? 0.0;
      final repeatAttendees = analyticsData['repeatAttendees'] ?? 0;

      // Peak hours optimization
      if (peakHoursAnalysis['peakHour'] != null) {
        final peakHour = peakHoursAnalysis['peakHour'] as String;
        final hour = int.tryParse(peakHour.split(':')[0]) ?? 0;
        
        if (hour >= 9 && hour <= 11) {
          optimizations.add({
            'type': 'timing',
            'title': 'Optimize Event Timing',
            'description': 'Shift events to morning hours (9-11 AM) for +35% attendance',
            'impact': 'High',
            'confidence': peakHoursAnalysis['confidence'] ?? 0.0,
            'implementation': 'Schedule future events during peak morning hours',
          });
        } else if (hour >= 17 && hour <= 19) {
          optimizations.add({
            'type': 'timing',
            'title': 'Evening Event Strategy',
            'description': 'Leverage evening peak (5-7 PM) for +25% attendance',
            'impact': 'Medium',
            'confidence': peakHoursAnalysis['confidence'] ?? 0.0,
            'implementation': 'Focus on after-work events and networking sessions',
          });
        }
      }

      // Weekend optimization
      if (totalAttendees > 0) {
        optimizations.add({
          'type': 'scheduling',
          'title': 'Weekend Events',
          'description': 'Shift to weekends for +40% attendance potential',
          'impact': 'High',
          'confidence': 0.7,
          'implementation': 'Schedule events on Saturdays or Sundays',
        });
      }

      // Dropout rate optimization
      if (dropoutRate > 20) {
        optimizations.add({
          'type': 'engagement',
          'title': 'Reduce Dropout Rate',
          'description': 'Implement reminder system to reduce dropout by 30%',
          'impact': 'Medium',
          'confidence': 0.8,
          'implementation': 'Send SMS/email reminders 24h and 1h before events',
        });
      }

      // Repeat attendee optimization
      if (repeatAttendees > 0 && totalAttendees > 0) {
        final repeatRate = (repeatAttendees / totalAttendees) * 100;
        if (repeatRate < 30) {
          optimizations.add({
            'type': 'retention',
            'title': 'Increase Repeat Attendance',
            'description': 'Implement loyalty program for +50% repeat attendance',
            'impact': 'High',
            'confidence': 0.6,
            'implementation': 'Create member benefits and early access programs',
          });
        }
      }

      // Sentiment-based optimizations
      if (sentimentAnalysis['overallSentiment'] == 'negative') {
        optimizations.add({
          'type': 'feedback',
          'title': 'Improve Event Quality',
          'description': 'Address feedback to improve satisfaction by 40%',
          'impact': 'High',
          'confidence': 0.9,
          'implementation': 'Conduct post-event surveys and implement feedback',
        });
      }

      return optimizations;
    } catch (e) {
      return [{
        'type': 'error',
        'title': 'Analysis Error',
        'description': 'Failed to generate optimizations: $e',
        'impact': 'Unknown',
        'confidence': 0.0,
        'implementation': 'Check data quality and retry analysis',
      }];
    }
  }

  /// Analyze dropout patterns
  Future<Map<String, dynamic>> analyzeDropoutPatterns(
    Map<String, dynamic> analyticsData,
    List<Map<String, dynamic>> attendees,
  ) async {
    try {
      final dropoutRate = analyticsData['dropoutRate'] ?? 0.0;
      final totalAttendees = analyticsData['totalAttendees'] ?? 0;

      String recommendation = '';
      if (dropoutRate > 50) {
        recommendation = 'High dropout rate detected. Consider improving event marketing and reminder systems.';
      } else if (dropoutRate > 25) {
        recommendation = 'Moderate dropout rate. Implement better engagement strategies.';
      } else {
        recommendation = 'Low dropout rate. Your event planning is effective!';
      }

      return {
        'dropoutRate': dropoutRate,
        'recommendation': recommendation,
        'severity': dropoutRate > 50 ? 'High' : dropoutRate > 25 ? 'Medium' : 'Low',
        'totalAttendees': totalAttendees,
        'confidence': 0.8,
      };
    } catch (e) {
      return {
        'error': 'Failed to analyze dropout patterns: $e',
        'dropoutRate': 0.0,
        'recommendation': 'Analysis failed',
        'severity': 'Unknown',
        'confidence': 0.0,
      };
    }
  }

  /// Analyze repeat attendee patterns
  Future<Map<String, dynamic>> analyzeRepeatAttendees(
    Map<String, dynamic> analyticsData,
    List<Map<String, dynamic>> attendees,
  ) async {
    try {
      final repeatAttendees = analyticsData['repeatAttendees'] ?? 0;
      final totalAttendees = analyticsData['totalAttendees'] ?? 0;

      final repeatRate = totalAttendees > 0 ? (repeatAttendees / totalAttendees) * 100 : 0.0;

      String recommendation = '';
      if (repeatRate > 50) {
        recommendation = 'Excellent repeat attendance! Your events have strong community building.';
      } else if (repeatRate > 25) {
        recommendation = 'Good repeat attendance. Consider loyalty programs to increase retention.';
      } else {
        recommendation = 'Low repeat attendance. Focus on building community and improving event quality.';
      }

      return {
        'repeatRate': repeatRate,
        'repeatAttendees': repeatAttendees,
        'totalAttendees': totalAttendees,
        'recommendation': recommendation,
        'confidence': 0.8,
      };
    } catch (e) {
      return {
        'error': 'Failed to analyze repeat attendees: $e',
        'repeatRate': 0.0,
        'repeatAttendees': 0,
        'totalAttendees': 0,
        'recommendation': 'Analysis failed',
        'confidence': 0.0,
      };
    }
  }

  /// Generate comprehensive AI insights
  Future<AIInsights> generateAIInsights(String eventId) async {
    try {
      // Get analytics data
      final analyticsDoc = await FirebaseFirestore.instance
          .collection('event_analytics')
          .doc(eventId)
          .get();

      if (!analyticsDoc.exists) {
        throw Exception('No analytics data found for event: $eventId');
      }

      final analyticsData = analyticsDoc.data() as Map<String, dynamic>;

      // Get comments for sentiment analysis
      final commentsQuery = await FirebaseFirestore.instance
          .collection('Comments')
          .where('eventId', isEqualTo: eventId)
          .get();

      final comments = commentsQuery.docs.map((doc) => doc.data()).toList();

      // Get attendees for detailed analysis
      final attendeesQuery = await FirebaseFirestore.instance
          .collection('Attendance')
          .where('eventId', isEqualTo: eventId)
          .get();

      final attendees = attendeesQuery.docs.map((doc) => doc.data()).toList();

      // Perform AI analysis
      final peakHoursAnalysis = await analyzePeakHours(
        analyticsData['hourlySignIns'] as Map<String, dynamic>? ?? {},
      );

      final sentimentAnalysis = await analyzeSentiment(comments);

      final optimizations = await generateOptimizations(
        analyticsData,
        peakHoursAnalysis,
        sentimentAnalysis,
      );

      final dropoutAnalysis = await analyzeDropoutPatterns(analyticsData, attendees);

      final repeatAttendeeAnalysis = await analyzeRepeatAttendees(analyticsData, attendees);

      return AIInsights(
        peakHoursAnalysis: peakHoursAnalysis,
        sentimentAnalysis: sentimentAnalysis,
        optimizationPredictions: optimizations,
        dropoutAnalysis: dropoutAnalysis,
        repeatAttendeeAnalysis: repeatAttendeeAnalysis,
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      throw Exception('Failed to generate AI insights: $e');
    }
  }

  /// Save AI insights to Firestore
  Future<void> saveAIInsights(String eventId, AIInsights insights) async {
    try {
      await FirebaseFirestore.instance
          .collection('ai_insights')
          .doc(eventId)
          .set(insights.toMap());
    } catch (e) {
      throw Exception('Failed to save AI insights: $e');
    }
  }

  /// Get AI insights from Firestore
  Future<AIInsights?> getAIInsights(String eventId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('ai_insights')
          .doc(eventId)
          .get();

      if (!doc.exists) return null;

      return AIInsights.fromMap(doc.data() as Map<String, dynamic>);
    } catch (e) {
      throw Exception('Failed to get AI insights: $e');
    }
  }
} 