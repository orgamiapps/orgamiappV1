import 'package:flutter_test/flutter_test.dart';
import 'package:attendus/Services/onnx_nlp_service.dart';

void main() {
  group('ONNX NLP Service Tests', () {
    late OnnxNlpService nlpService;

    setUpAll(() async {
      nlpService = OnnxNlpService.instance;
      await nlpService.initialize();
    });

    test('Parse "find a book club near me"', () async {
      final result = await nlpService.parseQuery('find a book club near me');
      
      expect(result, isNotNull);
      expect(result['categories'], contains('book_club'));
      expect(result['nearMe'], isTrue);
      expect(result['radiusKm'], greaterThan(0));
      expect(result['keywords'], contains('book'));
      expect(result['keywords'], contains('club'));
    });

    test('Parse "find a concert this weekend"', () async {
      final result = await nlpService.parseQuery('find a concert this weekend');
      
      expect(result, isNotNull);
      expect(result['categories'], contains('music'));
      expect(result['keywords'], contains('concert'));
      
      final dateRange = result['dateRange'] as Map<String, String>;
      expect(dateRange, isNotEmpty);
      expect(dateRange.containsKey('start'), isTrue);
      expect(dateRange.containsKey('end'), isTrue);
      
      // Verify it's actually this weekend
      final start = DateTime.parse(dateRange['start']!);
      final end = DateTime.parse(dateRange['end']!);
      final now = DateTime.now();
      
      // Calculate next Saturday
      final daysToSaturday = 6 - now.weekday;
      final saturday = now.add(Duration(days: daysToSaturday));
      
      // Check dates are within weekend range
      expect(start.weekday, equals(6)); // Saturday
      expect(end.difference(start).inDays, equals(2)); // 2 day span
    });

    test('Parse "tech workshop tomorrow"', () async {
      final result = await nlpService.parseQuery('tech workshop tomorrow');
      
      expect(result, isNotNull);
      expect(result['categories'], contains('tech'));
      expect(result['categories'], contains('workshop'));
      expect(result['keywords'], contains('tech'));
      expect(result['keywords'], contains('workshop'));
      
      final dateRange = result['dateRange'] as Map<String, String>;
      expect(dateRange, isNotEmpty);
      
      // Verify it's tomorrow
      final start = DateTime.parse(dateRange['start']!);
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      expect(start.day, equals(tomorrow.day));
      expect(start.month, equals(tomorrow.month));
    });

    test('Parse "food festival within 10km"', () async {
      final result = await nlpService.parseQuery('food festival within 10km');
      
      expect(result, isNotNull);
      expect(result['categories'], contains('food'));
      expect(result['keywords'], contains('food'));
      expect(result['keywords'], contains('festival'));
      expect(result['radiusKm'], equals(10.0));
    });

    test('Parse "art exhibition in 5 miles"', () async {
      final result = await nlpService.parseQuery('art exhibition in 5 miles');
      
      expect(result, isNotNull);
      expect(result['categories'], contains('art'));
      expect(result['keywords'], contains('art'));
      expect(result['keywords'], contains('exhibition'));
      // 5 miles = ~8km
      expect(result['radiusKm'], closeTo(8.0, 0.5));
    });

    test('Parse "networking event today"', () async {
      final result = await nlpService.parseQuery('networking event today');
      
      expect(result, isNotNull);
      expect(result['categories'], contains('networking'));
      expect(result['keywords'], contains('networking'));
      
      final dateRange = result['dateRange'] as Map<String, String>;
      expect(dateRange, isNotEmpty);
      
      // Verify it's today
      final start = DateTime.parse(dateRange['start']!);
      final today = DateTime.now();
      expect(start.day, equals(today.day));
      expect(start.month, equals(today.month));
    });

    test('Parse "sports events next week"', () async {
      final result = await nlpService.parseQuery('sports events next week');
      
      expect(result, isNotNull);
      expect(result['categories'], contains('sports'));
      expect(result['keywords'], contains('sports'));
      
      final dateRange = result['dateRange'] as Map<String, String>;
      expect(dateRange, isNotEmpty);
      
      // Verify it's next week
      final start = DateTime.parse(dateRange['start']!);
      final nextWeek = DateTime.now().add(const Duration(days: 7));
      expect(start.isAfter(DateTime.now()), isTrue);
      expect(start.isBefore(DateTime.now().add(const Duration(days: 14))), isTrue);
    });

    test('Parse complex query "find a music or party event near me this week"', () async {
      final result = await nlpService.parseQuery('find a music or party event near me this week');
      
      expect(result, isNotNull);
      
      // Should detect multiple categories
      final categories = result['categories'] as List<String>;
      expect(categories.any((c) => c == 'music' || c == 'party'), isTrue);
      
      // Should detect location intent
      expect(result['nearMe'], isTrue);
      expect(result['radiusKm'], greaterThan(0));
      
      // Should detect time range
      final dateRange = result['dateRange'] as Map<String, String>;
      expect(dateRange, isNotEmpty);
    });

    test('Parse ambiguous query "something fun"', () async {
      final result = await nlpService.parseQuery('something fun');
      
      expect(result, isNotNull);
      expect(result['keywords'], contains('fun'));
      // Should have low confidence for ambiguous queries
      expect(result['confidence'], lessThan(50.0));
    });

    test('SQLite event caching', () async {
      final testEvents = [
        {
          'id': 'test1',
          'title': 'Book Club Meeting',
          'description': 'Monthly book discussion',
          'category': 'book_club',
          'location': {'lat': 37.7749, 'lng': -122.4194, 'name': 'SF Library'},
          'startDate': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
          'endDate': DateTime.now().add(const Duration(days: 1, hours: 2)).toIso8601String(),
          'organizer': 'SF Readers',
        },
        {
          'id': 'test2',
          'title': 'Tech Talk',
          'description': 'AI and ML workshop',
          'category': 'tech',
          'location': {'lat': 37.7749, 'lng': -122.4194, 'name': 'Tech Hub'},
          'startDate': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
          'endDate': DateTime.now().add(const Duration(days: 2, hours: 3)).toIso8601String(),
          'organizer': 'Tech Community',
        },
      ];

      // Cache events
      await nlpService.cacheEvents(testEvents);

      // Query cached events
      final intent = {
        'categories': ['book_club'],
        'keywords': ['book'],
        'nearMe': true,
        'radiusKm': 10.0,
        'dateRange': {},
      };

      final results = await nlpService.queryEvents(
        intent: intent,
        userLat: 37.7749,
        userLng: -122.4194,
        limit: 10,
      );

      expect(results, isNotEmpty);
      expect(results.first['title'], equals('Book Club Meeting'));
    });

    test('Confidence scoring', () async {
      // Clear, specific query should have high confidence
      final clearResult = await nlpService.parseQuery('find a book club event near me tomorrow');
      expect(clearResult['confidence'], greaterThan(60.0));

      // Vague query should have low confidence
      final vagueResult = await nlpService.parseQuery('something');
      expect(vagueResult['confidence'], lessThan(40.0));
    });

    test('Extract keywords filtering stop words', () async {
      final result = await nlpService.parseQuery('find the best music event in the city');
      
      final keywords = result['keywords'] as List<String>;
      // Should filter out stop words like "the", "in"
      expect(keywords.contains('the'), isFalse);
      expect(keywords.contains('in'), isFalse);
      // Should keep meaningful words
      expect(keywords.contains('best'), isTrue);
      expect(keywords.contains('music'), isTrue);
      expect(keywords.contains('city'), isTrue);
    });
  });
}
