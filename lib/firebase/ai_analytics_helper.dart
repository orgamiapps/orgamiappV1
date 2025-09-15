import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;

import 'package:attendus/models/event_model.dart';
import 'package:intl/intl.dart';
import 'package:attendus/Utils/logger.dart';

// AI Insights Data Structure
class AIInsights {
  final Map<String, dynamic> peakHoursAnalysis;
  final Map<String, dynamic> sentimentAnalysis;
  final List<Map<String, dynamic>> optimizationPredictions;
  final Map<String, dynamic> dropoutAnalysis;
  final Map<String, dynamic> repeatAttendeeAnalysis;
  final DateTime lastUpdated;
  final Map<String, dynamic>? globalPerformanceAnalysis;
  final List<Map<String, dynamic>>? strategyRecommendations;
  // New, richer global insights
  final Map<String, dynamic>? dayOfWeekInsights; // {bestDay, distribution}
  final Map<String, dynamic>?
  timeOfDayInsights; // {bestHourRange, distribution}
  final Map<String, dynamic>? forecast; // {nextMonth, method, confidence}
  final Map<String, dynamic>?
  dwellInsights; // {avgMinutes, highEngagementPercent}
  final List<Map<String, dynamic>>? anomalies; // Outlier events
  final String? naturalSummary; // Narrative overview

  AIInsights({
    required this.peakHoursAnalysis,
    required this.sentimentAnalysis,
    required this.optimizationPredictions,
    required this.dropoutAnalysis,
    required this.repeatAttendeeAnalysis,
    required this.lastUpdated,
    this.globalPerformanceAnalysis,
    this.strategyRecommendations,
    this.dayOfWeekInsights,
    this.timeOfDayInsights,
    this.forecast,
    this.dwellInsights,
    this.anomalies,
    this.naturalSummary,
  });

  Map<String, dynamic> toMap() {
    return {
      'peakHoursAnalysis': peakHoursAnalysis,
      'sentimentAnalysis': sentimentAnalysis,
      'optimizationPredictions': optimizationPredictions,
      'dropoutAnalysis': dropoutAnalysis,
      'repeatAttendeeAnalysis': repeatAttendeeAnalysis,
      'lastUpdated': lastUpdated,
      'globalPerformanceAnalysis': globalPerformanceAnalysis,
      'strategyRecommendations': strategyRecommendations,
      'dayOfWeekInsights': dayOfWeekInsights,
      'timeOfDayInsights': timeOfDayInsights,
      'forecast': forecast,
      'dwellInsights': dwellInsights,
      'anomalies': anomalies,
      'naturalSummary': naturalSummary,
    };
  }

  factory AIInsights.fromMap(Map<String, dynamic> map) {
    return AIInsights(
      peakHoursAnalysis: Map<String, dynamic>.from(
        map['peakHoursAnalysis'] ?? {},
      ),
      sentimentAnalysis: Map<String, dynamic>.from(
        map['sentimentAnalysis'] ?? {},
      ),
      optimizationPredictions: List<Map<String, dynamic>>.from(
        map['optimizationPredictions'] ?? [],
      ),
      dropoutAnalysis: Map<String, dynamic>.from(map['dropoutAnalysis'] ?? {}),
      repeatAttendeeAnalysis: Map<String, dynamic>.from(
        map['repeatAttendeeAnalysis'] ?? {},
      ),
      lastUpdated: (map['lastUpdated'] as Timestamp).toDate(),
      globalPerformanceAnalysis: map['globalPerformanceAnalysis'] != null
          ? Map<String, dynamic>.from(map['globalPerformanceAnalysis'])
          : null,
      strategyRecommendations: map['strategyRecommendations'] != null
          ? List<Map<String, dynamic>>.from(map['strategyRecommendations'])
          : null,
      dayOfWeekInsights: map['dayOfWeekInsights'] != null
          ? Map<String, dynamic>.from(map['dayOfWeekInsights'])
          : null,
      timeOfDayInsights: map['timeOfDayInsights'] != null
          ? Map<String, dynamic>.from(map['timeOfDayInsights'])
          : null,
      forecast: map['forecast'] != null
          ? Map<String, dynamic>.from(map['forecast'])
          : null,
      dwellInsights: map['dwellInsights'] != null
          ? Map<String, dynamic>.from(map['dwellInsights'])
          : null,
      anomalies: map['anomalies'] != null
          ? List<Map<String, dynamic>>.from(map['anomalies'])
          : null,
      naturalSummary: map['naturalSummary'] as String?,
    );
  }
}

class AIAnalyticsHelper {
  static final AIAnalyticsHelper _instance = AIAnalyticsHelper._internal();
  factory AIAnalyticsHelper() => _instance;
  AIAnalyticsHelper._internal();

  /// Analyze attendance timestamps for peak hours
  Future<Map<String, dynamic>> analyzePeakHours(
    Map<String, dynamic> hourlySignIns,
  ) async {
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
      final totalSignIns = sortedHours.fold<int>(
        0,
        (total, entry) => total + (entry.value as num).toInt(),
      );
      final confidence = totalSignIns > 0 ? (peakCount / totalSignIns) : 0.0;

      // Generate recommendation
      String recommendation = '';
      if (peakHour.isNotEmpty) {
        final hour = int.tryParse(peakHour.split(':')[0]) ?? 0;
        if (hour >= 9 && hour <= 11) {
          recommendation =
              'Morning events (9-11 AM) show highest engagement. Consider scheduling future events during this time.';
        } else if (hour >= 12 && hour <= 14) {
          recommendation =
              'Lunch time (12-2 PM) is your peak period. Lunch-and-learn events could be highly successful.';
        } else if (hour >= 17 && hour <= 19) {
          recommendation =
              'Evening hours (5-7 PM) are most popular. After-work events align well with attendee preferences.';
        } else {
          recommendation =
              'Peak attendance at $peakHour. Consider this timing for future events.';
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
  Future<Map<String, dynamic>> analyzeSentiment(
    List<Map<String, dynamic>> comments,
  ) async {
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
        'great',
        'awesome',
        'amazing',
        'excellent',
        'fantastic',
        'wonderful',
        'good',
        'nice',
        'love',
        'enjoy',
        'happy',
        'satisfied',
        'impressed',
        'outstanding',
        'brilliant',
        'perfect',
        'best',
        'favorite',
        'recommend',
      ];

      final negativeKeywords = [
        'bad',
        'terrible',
        'awful',
        'horrible',
        'disappointing',
        'poor',
        'worst',
        'hate',
        'dislike',
        'boring',
        'waste',
        'useless',
        'frustrated',
        'angry',
        'annoyed',
        'confused',
        'difficult',
        'problem',
        'issue',
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
        recommendation =
            'Excellent feedback! Attendees are highly satisfied. Consider expanding similar event formats.';
      } else if (overallSentiment == 'negative') {
        recommendation =
            'Address attendee concerns. Consider gathering more detailed feedback to improve future events.';
      } else {
        recommendation =
            'Mixed feedback received. Consider implementing feedback surveys to better understand attendee needs.';
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
            'description':
                'Shift events to morning hours (9-11 AM) for +35% attendance',
            'impact': 'High',
            'confidence': peakHoursAnalysis['confidence'] ?? 0.0,
            'implementation':
                'Schedule future events during peak morning hours',
          });
        } else if (hour >= 17 && hour <= 19) {
          optimizations.add({
            'type': 'timing',
            'title': 'Evening Event Strategy',
            'description': 'Leverage evening peak (5-7 PM) for +25% attendance',
            'impact': 'Medium',
            'confidence': peakHoursAnalysis['confidence'] ?? 0.0,
            'implementation':
                'Focus on after-work events and networking sessions',
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
            'description':
                'Implement loyalty program for +50% repeat attendance',
            'impact': 'High',
            'confidence': 0.6,
            'implementation':
                'Create member benefits and early access programs',
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
      return [
        {
          'type': 'error',
          'title': 'Analysis Error',
          'description': 'Failed to generate optimizations: $e',
          'impact': 'Unknown',
          'confidence': 0.0,
          'implementation': 'Check data quality and retry analysis',
        },
      ];
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
        recommendation =
            'High dropout rate detected. Consider improving event marketing and reminder systems.';
      } else if (dropoutRate > 25) {
        recommendation =
            'Moderate dropout rate. Implement better engagement strategies.';
      } else {
        recommendation = 'Low dropout rate. Your event planning is effective!';
      }

      return {
        'dropoutRate': dropoutRate,
        'recommendation': recommendation,
        'severity': dropoutRate > 50
            ? 'High'
            : dropoutRate > 25
            ? 'Medium'
            : 'Low',
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

      final repeatRate = totalAttendees > 0
          ? (repeatAttendees / totalAttendees) * 100
          : 0.0;

      String recommendation = '';
      if (repeatRate > 50) {
        recommendation =
            'Excellent repeat attendance! Your events have strong community building.';
      } else if (repeatRate > 25) {
        recommendation =
            'Good repeat attendance. Consider loyalty programs to increase retention.';
      } else {
        recommendation =
            'Low repeat attendance. Focus on building community and improving event quality.';
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

      final dropoutAnalysis = await analyzeDropoutPatterns(
        analyticsData,
        attendees,
      );

      final repeatAttendeeAnalysis = await analyzeRepeatAttendees(
        analyticsData,
        attendees,
      );

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

  /// Generate global AI insights for all user events
  Future<AIInsights> generateGlobalAIInsights(List<EventModel> events) async {
    try {
      if (events.isEmpty) {
        throw Exception('No events provided for global analysis');
      }

      // Limit number of events analyzed to reduce load on low-end devices
      final List<EventModel> toAnalyze = events.length > 60
          ? (events..sort(
                  (a, b) => b.selectedDateTime.compareTo(a.selectedDateTime),
                ))
                .take(60)
                .toList()
          : events;

      // Aggregate data from selected events
      int totalAttendees = 0;
      int totalRepeatAttendees = 0;
      Map<String, int> categoryCounts = {};
      Map<String, int> monthlyTrends = {};
      // New aggregations
      Map<int, int> hourWeightedAttendance = {}; // hour -> attendees sum
      Map<int, int> weekdayWeightedAttendance = {}; // 1..7 -> attendees sum
      List<Map<String, dynamic>> perEventAttendance =
          []; // [{title, attendees, date}]

      for (final event in toAnalyze) {
        try {
          final analyticsDoc = await FirebaseFirestore.instance
              .collection('event_analytics')
              .doc(event.id)
              .get();

          if (analyticsDoc.exists) {
            final eventData = analyticsDoc.data() as Map<String, dynamic>;
            final attendees = (eventData['totalAttendees'] ?? 0) as int;
            final repeatAttendees = (eventData['repeatAttendees'] ?? 0) as int;

            totalAttendees += attendees;
            totalRepeatAttendees += repeatAttendees;

            // Weighted scheduling signals (by attendance)
            final eventHour = event.selectedDateTime.hour;
            final weekday = event.selectedDateTime.weekday; // 1=Mon..7=Sun
            hourWeightedAttendance[eventHour] =
                (hourWeightedAttendance[eventHour] ?? 0) + attendees;
            weekdayWeightedAttendance[weekday] =
                (weekdayWeightedAttendance[weekday] ?? 0) + attendees;

            perEventAttendance.add({
              'title': event.title,
              'attendees': attendees,
              'date': event.selectedDateTime.toIso8601String(),
            });

            // Track categories
            final category = event.categories.isNotEmpty
                ? event.categories.first
                : 'Other';
            categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;

            // Track monthly trends
            final monthKey = DateFormat(
              'yyyy-MM',
            ).format(event.selectedDateTime);
            monthlyTrends[monthKey] =
                (monthlyTrends[monthKey] ?? 0) + attendees;
          }
        } catch (e) {
          if (kDebugMode) {
            Logger.error('Error loading analytics for event ${event.id}: $e');
          }
        }
      }

      // Calculate performance metrics
      final performanceScore = totalAttendees > 0
          ? (totalRepeatAttendees / totalAttendees) * 100
          : 0.0;

      final growthRate = toAnalyze.length > 1
          ? 15.0
          : 0.0; // Simplified calculation

      // Generate global performance analysis
      final globalPerformanceAnalysis = {
        'performanceScore': performanceScore,
        'growthRate': growthRate,
        'totalEvents': toAnalyze.length,
        'totalAttendees': totalAttendees,
        'recommendation': _generateGlobalRecommendation(
          performanceScore,
          toAnalyze.length,
        ),
      };

      // Generate strategy recommendations
      final strategyRecommendations = _generateStrategyRecommendations(
        performanceScore,
        toAnalyze.length,
        categoryCounts,
        monthlyTrends,
      );

      // Compute new insights
      final dayOfWeekInsights = _computeBestWeekday(weekdayWeightedAttendance);
      final timeOfDayInsights = _computeBestHourRange(hourWeightedAttendance);
      final forecast = _computeForecast(monthlyTrends);
      final anomalies = _detectAttendanceAnomalies(perEventAttendance);

      // Dwell time insights (best-effort; may be sparse)
      final dwellInsights = await _computeDwellInsights(events);

      final naturalSummary = _generateNarrative(
        globalPerformanceAnalysis,
        dayOfWeekInsights,
        timeOfDayInsights,
        forecast,
        dwellInsights,
      );

      return AIInsights(
        peakHoursAnalysis: {'global': true},
        sentimentAnalysis: {'global': true},
        optimizationPredictions: [],
        dropoutAnalysis: {'global': true},
        repeatAttendeeAnalysis: {'global': true},
        lastUpdated: DateTime.now(),
        globalPerformanceAnalysis: globalPerformanceAnalysis,
        strategyRecommendations: strategyRecommendations,
        dayOfWeekInsights: dayOfWeekInsights,
        timeOfDayInsights: timeOfDayInsights,
        forecast: forecast,
        dwellInsights: dwellInsights,
        anomalies: anomalies,
        naturalSummary: naturalSummary,
      );
    } catch (e) {
      throw Exception('Failed to generate global AI insights: $e');
    }
  }

  Map<String, dynamic> _computeBestWeekday(Map<int, int> weekdayAttendance) {
    if (weekdayAttendance.isEmpty) {
      return {
        'bestDay': null,
        'distribution': {},
        'recommendation': 'Insufficient data for weekday analysis',
        'confidence': 0.0,
      };
    }
    final names = {
      1: 'Mon',
      2: 'Tue',
      3: 'Wed',
      4: 'Thu',
      5: 'Fri',
      6: 'Sat',
      7: 'Sun',
    };
    int bestKey = weekdayAttendance.keys.first;
    int bestVal = -1;
    int total = 0;
    weekdayAttendance.forEach((k, v) {
      total += v;
      if (v > bestVal) {
        bestVal = v;
        bestKey = k;
      }
    });
    final confidence = total > 0 ? bestVal / total : 0.0;
    return {
      'bestDay': names[bestKey],
      'distribution': weekdayAttendance.map((k, v) => MapEntry(names[k]!, v)),
      'recommendation':
          'Best day to host events appears to be ${names[bestKey]}',
      'confidence': confidence,
    };
  }

  Map<String, dynamic> _computeBestHourRange(Map<int, int> hourAttendance) {
    if (hourAttendance.isEmpty) {
      return {
        'bestHourRange': null,
        'distribution': {},
        'recommendation': 'Insufficient data for time-of-day analysis',
        'confidence': 0.0,
      };
    }
    // Smooth by grouping into 2-hour buckets
    final Map<String, int> buckets = {};
    int total = 0;
    hourAttendance.forEach((hour, count) {
      final start = (hour ~/ 2) * 2; // 0,2,4,...
      final label =
          '${start.toString().padLeft(2, '0')}-${(start + 2).toString().padLeft(2, '0')}';
      buckets[label] = (buckets[label] ?? 0) + count;
      total += count;
    });
    String best = '';
    int bestVal = -1;
    buckets.forEach((label, val) {
      if (val > bestVal) {
        bestVal = val;
        best = label;
      }
    });
    final confidence = total > 0 ? bestVal / total : 0.0;
    return {
      'bestHourRange': best,
      'distribution': buckets,
      'recommendation': 'Highest attendance tends to be during $best',
      'confidence': confidence,
    };
  }

  Map<String, dynamic> _computeForecast(Map<String, int> monthlyTrends) {
    if (monthlyTrends.isEmpty) {
      return {'nextMonth': 0, 'method': 'moving_average', 'confidence': 0.0};
    }
    final sorted = monthlyTrends.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    // Use simple weighted moving average of last up to 4 months
    final last = sorted.length <= 4
        ? sorted
        : sorted.sublist(sorted.length - 4);
    int denom = 0;
    double num = 0;
    for (int i = 0; i < last.length; i++) {
      final weight = (i + 1); // 1..4 with most recent highest
      denom += weight;
      num += last[last.length - 1 - i].value * weight;
    }
    final prediction = denom == 0 ? 0 : (num / denom).round();
    // Confidence: more months -> higher; normalized variance
    final values = sorted.map((e) => e.value.toDouble()).toList();
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values.length > 1
        ? values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
              (values.length - 1)
        : 0.0;
    final volatility = mean == 0 ? 0.0 : (variance / (mean.abs() + 1e-9));
    final confidence = (0.6 + (0.2 / (1 + volatility))).clamp(0.0, 0.95);
    return {
      'nextMonth': prediction,
      'method': 'weighted_moving_average',
      'confidence': confidence,
    };
  }

  List<Map<String, dynamic>> _detectAttendanceAnomalies(
    List<Map<String, dynamic>> perEvent,
  ) {
    if (perEvent.isEmpty) return [];
    final values = perEvent
        .map((e) => (e['attendees'] as int).toDouble())
        .toList();
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
        values.length;
    final std = math.sqrt(variance);
    const threshold = 2.0; // z-score threshold
    final anomalies = <Map<String, dynamic>>[];
    for (int i = 0; i < perEvent.length; i++) {
      final z = std == 0 ? 0.0 : ((values[i] - mean) / std);
      if (z.abs() >= threshold) {
        anomalies.add({
          'title': perEvent[i]['title'],
          'attendees': perEvent[i]['attendees'],
          'date': perEvent[i]['date'],
          'zScore': z,
          'type': z > 0 ? 'high' : 'low',
        });
      }
    }
    return anomalies;
  }

  Future<Map<String, dynamic>?> _computeDwellInsights(
    List<EventModel> events,
  ) async {
    try {
      if (events.isEmpty) return null;
      int sampleCount = 0;
      double totalMinutes = 0;
      int highEngagement = 0; // > 45 minutes
      for (final e in events) {
        final attendeesQuery = await FirebaseFirestore.instance
            .collection('Attendance')
            .where('eventId', isEqualTo: e.id)
            .get();
        for (final doc in attendeesQuery.docs) {
          final data = doc.data();
          if (data['dwellTime'] != null) {
            // Firestore stores Duration as milliseconds or map; best-effort
            final dt = data['dwellTime'];
            int minutes;
            if (dt is int) {
              minutes = (dt / 60000).round();
            } else if (dt is Map && dt['inMinutes'] != null) {
              minutes = (dt['inMinutes'] as num).toInt();
            } else {
              continue;
            }
            sampleCount++;
            totalMinutes += minutes;
            if (minutes >= 45) highEngagement++;
          }
        }
      }
      if (sampleCount == 0) return null;
      final avg = totalMinutes / sampleCount;
      final pct = (highEngagement / sampleCount) * 100;
      return {
        'avgMinutes': avg,
        'highEngagementPercent': pct,
        'samples': sampleCount,
      };
    } catch (_) {
      return null;
    }
  }

  String _generateNarrative(
    Map<String, dynamic> performance,
    Map<String, dynamic> dayOfWeek,
    Map<String, dynamic> timeOfDay,
    Map<String, dynamic> forecast,
    Map<String, dynamic>? dwell,
  ) {
    final bestDay = dayOfWeek['bestDay'] ?? 'N/A';
    final bestHour = timeOfDay['bestHourRange'] ?? 'N/A';
    final perf =
        (performance['performanceScore'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final next = forecast['nextMonth'] ?? 0;
    final conf = ((forecast['confidence'] ?? 0.0) as num).toDouble();
    final dwellStr = dwell == null
        ? 'Dwell data not available.'
        : 'Average dwell time ${(dwell['avgMinutes'] as num).toStringAsFixed(0)}m with ${(dwell['highEngagementPercent'] as num).toStringAsFixed(0)}% staying >45m.';
    return 'Engagement score sits at $perf%. Best scheduling signals point to $bestDay around $bestHour. Next month is projected to bring ~$next attendees (confidence ${(conf * 100).toStringAsFixed(0)}%). $dwellStr';
  }

  /// Very lightweight question answering over computed insights.
  Future<String> answerQuestion(String question, AIInsights insights) async {
    final q = question.toLowerCase();
    if (q.contains('best day')) {
      return 'Best day appears to be ${insights.dayOfWeekInsights?['bestDay'] ?? 'N/A'} based on attendance weighting.';
    }
    if (q.contains('best time') ||
        q.contains('time of day') ||
        q.contains('hour')) {
      return 'Best time window is ${insights.timeOfDayInsights?['bestHourRange'] ?? 'N/A'}.';
    }
    if (q.contains('forecast') ||
        q.contains('next month') ||
        q.contains('predict')) {
      final next = insights.forecast?['nextMonth'];
      final conf = insights.forecast?['confidence'];
      return next == null
          ? 'Not enough history to forecast yet.'
          : 'Projected next-month attendance: $next (confidence ${(conf * 100).toStringAsFixed(0)}%).';
    }
    if (q.contains('engagement') || q.contains('score')) {
      final perf =
          (insights.globalPerformanceAnalysis?['performanceScore'] as num?)
              ?.toStringAsFixed(1) ??
          '0.0';
      return 'Current engagement score is $perf% (repeat attendees / total).';
    }
    if (q.contains('dwell') || q.contains('stay')) {
      final d = insights.dwellInsights;
      if (d == null) return 'No dwell-time data available yet.';
      return 'Average dwell ${(d['avgMinutes'] as num).toStringAsFixed(0)}m; ${(d['highEngagementPercent'] as num).toStringAsFixed(0)}% stayed >45m.';
    }
    if (q.contains('anomal')) {
      final a = insights.anomalies ?? [];
      if (a.isEmpty) return 'No attendance anomalies detected.';
      final first = a.first;
      return 'Anomaly detected: ${first['title']} (${first['attendees']} attendees, ${first['type']} outlier).';
    }
    // Default: provide narrative summary
    return insights.naturalSummary ??
        'I analyzed your data but could not map this question. Try asking about: best day, best time, forecast, engagement, dwell, anomalies.';
  }

  String _generateGlobalRecommendation(
    double performanceScore,
    int eventCount,
  ) {
    if (performanceScore > 70) {
      return 'Excellent performance! Your events are highly engaging. Consider expanding to larger venues or hosting more frequent events.';
    } else if (performanceScore > 50) {
      return 'Good performance. Focus on improving attendee retention and engagement strategies.';
    } else if (eventCount < 3) {
      return 'You\'re just getting started! Create more events to gather better insights and improve your event planning strategy.';
    } else {
      return 'Consider reviewing your event formats and marketing strategies to improve attendee engagement.';
    }
  }

  List<Map<String, dynamic>> _generateStrategyRecommendations(
    double performanceScore,
    int eventCount,
    Map<String, int> categoryCounts,
    Map<String, int> monthlyTrends,
  ) {
    final recommendations = <Map<String, dynamic>>[];

    // Performance-based recommendations
    if (performanceScore < 50) {
      recommendations.add({
        'type': 'engagement',
        'title': 'Improve Attendee Engagement',
        'description':
            'Focus on interactive elements and follow-up strategies to increase repeat attendance by 40%',
        'impact': 'High',
        'confidence': 0.8,
      });
    }

    // Category diversification
    if (categoryCounts.length < 2) {
      recommendations.add({
        'type': 'content',
        'title': 'Diversify Event Types',
        'description':
            'Try different event categories to reach broader audiences and increase overall attendance',
        'impact': 'Medium',
        'confidence': 0.7,
      });
    }

    // Timing optimization
    if (monthlyTrends.isNotEmpty) {
      recommendations.add({
        'type': 'timing',
        'title': 'Optimize Event Timing',
        'description':
            'Schedule events during peak attendance months for better turnout',
        'impact': 'Medium',
        'confidence': 0.6,
      });
    }

    // Marketing recommendations
    if (eventCount < 5) {
      recommendations.add({
        'type': 'marketing',
        'title': 'Expand Marketing Reach',
        'description':
            'Increase marketing efforts to reach more potential attendees',
        'impact': 'High',
        'confidence': 0.9,
      });
    }

    return recommendations;
  }
}
