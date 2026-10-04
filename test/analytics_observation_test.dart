import 'package:attendus/firebase/ai_analytics_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final helper = AIAnalyticsHelper();
  test(
    'recommendations do not fabricate causal lift or calibrated confidence',
    () async {
      for (final hour in ['10:00', '18:00']) {
        final recommendations = await helper.generateOptimizations(
          {'totalAttendees': 100, 'repeatAttendees': 10, 'dropoutRate': 40},
          {'peakHour': hour, 'confidence': 0.99},
          {'overallSentiment': 'negative'},
        );
        expect(recommendations, isNotEmpty);
        for (final recommendation in recommendations) {
          expect(recommendation['description'], isNot(contains('%')));
          expect(recommendation['confidence'], isNull);
          expect(recommendation['confidenceAvailable'], isFalse);
          expect(recommendation['impact'], 'Not estimated');
        }
      }
    },
  );
  test(
    'peak concentration is an observed share rather than predictive confidence',
    () async {
      final peak = await helper.analyzePeakHours({'10:00': 8, '11:00': 2});
      expect(peak['peakCount'], 8);
      expect(peak['totalSignIns'], 10);
      expect(peak['observedShare'], 0.8);
      expect(peak['confidence'], isNull);
      expect(peak['confidenceAvailable'], isFalse);
    },
  );
  test(
    'sentiment reads real comment schema and reports sampled text count',
    () async {
      final sentiment = await helper.analyzeSentiment([
        {'comment': 'great'},
        {'text': 'bad'},
        {'comment': ''},
        {'unrelated': 'great'},
      ]);
      expect(sentiment['feedbackSampleSize'], 2);
      expect(sentiment['positiveCount'], 1);
      expect(sentiment['negativeCount'], 1);
      expect(sentiment['positiveRatio'], 0.5);
      expect(sentiment['confidence'], isNull);
      expect(sentiment['method'], 'keyword_counts');
    },
  );
  test(
    'absent feedback is unavailable rather than measured neutral sentiment',
    () async {
      for (final comments in <List<Map<String, dynamic>>>[
        [],
        [
          {'comment': ' '},
        ],
        [{}],
      ]) {
        final sentiment = await helper.analyzeSentiment(comments);
        expect(sentiment['overallSentiment'], 'unavailable');
        expect(sentiment['neutralRatio'], 0);
        expect(sentiment['feedbackSampleSize'], 0);
      }
    },
  );
  test(
    'forecast answer does not recycle historical invented confidence',
    () async {
      final insights = AIInsights(
        peakHoursAnalysis: {},
        sentimentAnalysis: {},
        optimizationPredictions: [],
        dropoutAnalysis: {},
        repeatAttendeeAnalysis: {},
        lastUpdated: DateTime(2026),
        forecast: {'nextMonth': 999, 'confidence': 0.95},
      );
      final answer = await helper.answerQuestion(
        'Forecast next month',
        insights,
      );
      expect(answer, contains('unavailable'));
      expect(answer, isNot(contains('999')));
      expect(answer, isNot(contains('95%')));
    },
  );
  test(
    'confidence rendering rejects unsupported missing and invalid numbers',
    () {
      for (final analysis in <Map<String, dynamic>>[
        {},
        {'confidence': 0.8},
        {'confidence': null, 'confidenceAvailable': false},
        {'confidence': double.nan, 'confidenceAvailable': true},
        {'confidence': 2, 'confidenceAvailable': true},
      ]) {
        expect(analyticsConfidenceLabel(analysis), 'Unavailable');
      }
      expect(
        analyticsConfidenceLabel({
          'confidence': 0,
          'confidenceAvailable': true,
        }),
        '0.0%',
      );
    },
  );
  test('insights retain server method and sample metadata', () {
    final insights = AIInsights.fromMap({
      'lastUpdated': Timestamp.fromDate(DateTime(2026)),
      'method': 'descriptive_heuristics',
      'isPredictiveModel': false,
      'feedbackSampleSize': 3,
    });
    expect(insights.toMap()['method'], 'descriptive_heuristics');
    expect(insights.toMap()['isPredictiveModel'], false);
    expect(insights.toMap()['feedbackSampleSize'], 3);
  });
}
