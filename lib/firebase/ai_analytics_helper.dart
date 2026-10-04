import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;

import 'package:attendus/models/event_model.dart';
import 'package:intl/intl.dart';
import 'package:attendus/Utils/logger.dart';

String analyticsConfidenceLabel(Map<String, dynamic> analysis) {
  final value = analysis['confidence'];
  if (analysis['confidenceAvailable'] != true ||
      value is! num ||
      !value.isFinite ||
      value < 0 ||
      value > 1) {
    return 'Unavailable';
  }
  return '${(value * 100).toStringAsFixed(1)}%';
}

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
  final String method;
  final bool isPredictiveModel;
  final int feedbackSampleSize;

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
    this.method = 'descriptive_heuristics',
    this.isPredictiveModel = false,
    this.feedbackSampleSize = 0,
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
      'method': method,
      'isPredictiveModel': isPredictiveModel,
      'feedbackSampleSize': feedbackSampleSize,
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
      method: map['method']?.toString() ?? 'descriptive_heuristics',
      isPredictiveModel: map['isPredictiveModel'] == true,
      feedbackSampleSize: (map['feedbackSampleSize'] as num?)?.toInt() ?? 0,
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
          'confidence': null,
          'confidenceAvailable': false,
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

      // Observed share is descriptive; it is not predictive confidence.
      final totalSignIns = sortedHours.fold<int>(
        0,
        (total, entry) => total + (entry.value as num).toInt(),
      );
      final observedShare = totalSignIns > 0
          ? (peakCount / totalSignIns)
          : null;

      // Generate recommendation
      String recommendation = '';
      if (peakHour.isNotEmpty) {
        final hour = int.tryParse(peakHour.split(':')[0]) ?? 0;
        if (hour >= 9 && hour <= 11) {
          recommendation =
              'The most recorded check-ins occurred in the morning (9-11 AM). This does not estimate the effect of changing future schedules.';
        } else if (hour >= 12 && hour <= 14) {
          recommendation =
              'The most recorded check-ins occurred at lunch time (12-2 PM). Compare event schedules before drawing conclusions.';
        } else if (hour >= 17 && hour <= 19) {
          recommendation =
              'The most recorded check-ins occurred in the evening (5-7 PM). This is an observed count, not a measure of attendee preferences.';
        } else {
          recommendation = 'The most recorded check-ins occurred at $peakHour.';
        }
      }

      return {
        'peakHour': peakHour,
        'peakCount': peakCount,
        'recommendation': recommendation,
        'observedShare': observedShare,
        'confidence': null,
        'confidenceAvailable': false,
        'totalSignIns': totalSignIns,
        'hourlyDistribution': hourlySignIns,
      };
    } catch (e) {
      return {
        'error': 'Failed to analyze peak hours: $e',
        'peakHour': null,
        'peakCount': 0,
        'recommendation': 'Analysis failed',
        'confidence': null,
        'confidenceAvailable': false,
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
          'neutralRatio': 0.0,
          'overallSentiment': 'unavailable',
          'feedbackSampleSize': 0,
          'recommendation': 'No comments available for sentiment analysis',
          'confidence': null,
          'confidenceAvailable': false,
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
        final text =
            (comment['comment'] ?? comment['text'])
                ?.toString()
                .trim()
                .toLowerCase() ??
            '';
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

      String overallSentiment = total == 0 ? 'unavailable' : 'neutral';
      if (positiveRatio > 0.6) {
        overallSentiment = 'positive';
      } else if (negativeRatio > 0.6) {
        overallSentiment = 'negative';
      }

      String recommendation = '';
      if (overallSentiment == 'positive') {
        recommendation =
            'Positive keywords appeared more often in the sampled comments. Review the comments for context; keyword matching does not measure satisfaction.';
      } else if (overallSentiment == 'negative') {
        recommendation =
            'Negative keywords appeared more often in the sampled comments. Review the original comments before choosing a response.';
      } else {
        recommendation = total == 0
            ? 'No text comments available for analysis.'
            : 'Keyword matches were mixed or absent. Review the original comments for context.';
      }

      return {
        'positiveRatio': positiveRatio,
        'negativeRatio': negativeRatio,
        'neutralRatio': neutralRatio,
        'overallSentiment': overallSentiment,
        'recommendation': recommendation,
        'confidence': null,
        'confidenceAvailable': false,
        'totalComments': total,
        'feedbackSampleSize': total,
        'method': 'keyword_counts',
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
        'confidence': null,
        'confidenceAvailable': false,
      };
    }
  }

  /// Suggest experiments from observed data without estimating their impact.
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
                'Recorded check-ins peaked in the morning. Compare similar events before testing a schedule change.',
            'impact': 'Not estimated',
            'confidence': null,
            'confidenceAvailable': false,
            'implementation':
                'Schedule future events during peak morning hours',
          });
        } else if (hour >= 17 && hour <= 19) {
          optimizations.add({
            'type': 'timing',
            'title': 'Evening Event Strategy',
            'description':
                'Recorded check-ins peaked in the evening. Compare similar events before testing a schedule change.',
            'impact': 'Not estimated',
            'confidence': null,
            'confidenceAvailable': false,
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
          'description':
              'Compare weekday and weekend events with similar formats. These records do not estimate a scheduling benefit.',
          'impact': 'Not estimated',
          'confidence': null,
          'confidenceAvailable': false,
          'implementation':
              'Review attendance alongside event schedules and capacity.',
        });
      }

      // Dropout rate optimization
      if (dropoutRate > 20) {
        optimizations.add({
          'type': 'engagement',
          'title': 'Reduce Dropout Rate',
          'description':
              'Review registration and attendance differences. Reminder impact has not been estimated.',
          'impact': 'Not estimated',
          'confidence': null,
          'confidenceAvailable': false,
          'implementation':
              'Send email and in-app reminders 24h and 1h before events',
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
                'Review repeat attendance and ask attendees what would encourage them to return.',
            'impact': 'Not estimated',
            'confidence': null,
            'confidenceAvailable': false,
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
          'description':
              'Review negative keyword matches in context and ask attendees for specific feedback.',
          'impact': 'Not estimated',
          'confidence': null,
          'confidenceAvailable': false,
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
          'confidence': null,
          'confidenceAvailable': false,
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
        'confidence': null,
        'confidenceAvailable': false,
      };
    } catch (e) {
      return {
        'error': 'Failed to analyze dropout patterns: $e',
        'dropoutRate': 0.0,
        'recommendation': 'Analysis failed',
        'severity': 'Unknown',
        'confidence': null,
        'confidenceAvailable': false,
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
        'confidence': null,
        'confidenceAvailable': false,
      };
    } catch (e) {
      return {
        'error': 'Failed to analyze repeat attendees: $e',
        'repeatRate': 0.0,
        'repeatAttendees': 0,
        'totalAttendees': 0,
        'recommendation': 'Analysis failed',
        'confidence': null,
        'confidenceAvailable': false,
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
        feedbackSampleSize:
            (sentimentAnalysis['feedbackSampleSize'] as num?)?.toInt() ?? 0,
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
          ? (List<EventModel>.from(events)..sort(
                  (a, b) => b.selectedDateTime.compareTo(a.selectedDateTime),
                ))
                .take(60)
                .toList()
          : events;

      // Aggregate data from selected events
      int totalAttendees = 0;
      int totalRepeatAttendees = 0;
      int coveredEvents = 0;
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
            if (eventData['totalAttendees'] is! num ||
                eventData['repeatAttendees'] is! num) {
              continue;
            }
            final attendees = (eventData['totalAttendees'] as num).toInt();
            final repeatAttendees = (eventData['repeatAttendees'] as num)
                .toInt();
            coveredEvents++;

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

      if (coveredEvents == 0) {
        throw StateError('Analytics are unavailable for these events.');
      }
      // Calculate performance metrics only from available records.
      final performanceScore = totalAttendees > 0
          ? (totalRepeatAttendees / totalAttendees) * 100
          : 0.0;

      // Generate global performance analysis
      final globalPerformanceAnalysis = {
        'performanceScore': performanceScore,
        'growthRate': null,
        'growthRateAvailable': false,
        'coveredEvents': coveredEvents,
        'requestedEvents': toAnalyze.length,
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
        'confidence': null,
        'confidenceAvailable': false,
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
    final observedShare = total > 0 ? bestVal / total : null;
    return {
      'bestDay': names[bestKey],
      'distribution': weekdayAttendance.map((k, v) => MapEntry(names[k]!, v)),
      'recommendation':
          'The largest observed attendance total was on ${names[bestKey]}.',
      'observedShare': observedShare,
      'confidence': null,
      'confidenceAvailable': false,
    };
  }

  Map<String, dynamic> _computeBestHourRange(Map<int, int> hourCounts) {
    if (hourCounts.isEmpty) {
      return {
        'bestHourRange': null,
        'distribution': {},
        'recommendation': 'Insufficient data for time-of-day analysis',
        'confidence': null,
        'confidenceAvailable': false,
      };
    }
    // Smooth by grouping into 2-hour buckets
    final Map<String, int> buckets = {};
    int total = 0;
    hourCounts.forEach((hour, attendeeCount) {
      final start = (hour ~/ 2) * 2; // 0,2,4,...
      final label =
          '${start.toString().padLeft(2, '0')}-${(start + 2).toString().padLeft(2, '0')}';
      buckets[label] = (buckets[label] ?? 0) + attendeeCount;
      total += attendeeCount;
    });
    String best = '';
    int bestVal = -1;
    buckets.forEach((label, val) {
      if (val > bestVal) {
        bestVal = val;
        best = label;
      }
    });
    final observedShare = total > 0 ? bestVal / total : null;
    return {
      'bestHourRange': best,
      'distribution': buckets,
      'recommendation':
          'The largest observed attendance total was during $best.',
      'observedShare': observedShare,
      'confidence': null,
      'confidenceAvailable': false,
    };
  }

  Map<String, dynamic> _computeForecast(Map<String, int> monthlyTrends) => {
    'nextMonth': null,
    'method': 'unavailable',
    'confidence': null,
    'confidenceAvailable': false,
    'observedMonths': monthlyTrends.length,
  };

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
    final dwellStr = dwell == null
        ? 'Dwell data not available.'
        : 'Average dwell time ${(dwell['avgMinutes'] as num).toStringAsFixed(0)}m with ${(dwell['highEngagementPercent'] as num).toStringAsFixed(0)}% staying >45m.';
    return 'Observed repeat attendance is $perf% of recorded attendance. The largest attendance totals were on $bestDay around $bestHour. Coverage: ${performance['coveredEvents']} of ${performance['requestedEvents']} requested events. Forecasts and causal effects are unavailable. $dwellStr';
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
      return 'Attendance forecasts and predictive confidence are unavailable. These insights summarize observed records only.';
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
            'Review interactive elements and follow-up strategies as experiments; any attendance benefit is not estimated',
        'impact': 'Not estimated',
        'confidence': null,
        'confidenceAvailable': false,
      });
    }

    // Category diversification
    if (categoryCounts.length < 2) {
      recommendations.add({
        'type': 'content',
        'title': 'Diversify Event Types',
        'description':
            'Try different event categories to reach broader audiences and increase overall attendance',
        'impact': 'Not estimated',
        'confidence': null,
        'confidenceAvailable': false,
      });
    }

    // Timing optimization
    if (monthlyTrends.isNotEmpty) {
      recommendations.add({
        'type': 'timing',
        'title': 'Optimize Event Timing',
        'description':
            'Schedule events during peak attendance months for better turnout',
        'impact': 'Not estimated',
        'confidence': null,
        'confidenceAvailable': false,
      });
    }

    // Marketing recommendations
    if (eventCount < 5) {
      recommendations.add({
        'type': 'marketing',
        'title': 'Expand Marketing Reach',
        'description':
            'Increase marketing efforts to reach more potential attendees',
        'impact': 'Not estimated',
        'confidence': null,
        'confidenceAvailable': false,
      });
    }

    return recommendations;
  }
}
