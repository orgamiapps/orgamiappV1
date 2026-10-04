import 'package:attendus/Services/event_search_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'public search runs without native model, assets, or SQLite plugins',
    () async {
      var calls = 0;
      final search = EventSearchService(
        search: (query, latitude, longitude) async {
          calls++;
          expect(query, 'tech workshop tomorrow');
          expect(latitude, isNull);
          return [];
        },
        locate: () =>
            throw StateError('Non-local search must not read location'),
      );
      expect(await search.search('tech workshop tomorrow'), isEmpty);
      expect(calls, 1);
    },
  );

  test('unavailable location still reaches the public event query', () async {
    var calls = 0;
    final search = EventSearchService(
      search: (query, latitude, longitude) async {
        calls++;
        expect(latitude, isNull);
        expect(longitude, isNull);
        return [];
      },
      locate: () async =>
          throw MissingPluginException('Web geolocation denied'),
    );
    expect(await search.search('find music near me'), isEmpty);
    expect(calls, 1);
  });

  test('query failures remain distinguishable from empty results', () async {
    final failure = StateError('offline');
    final search = EventSearchService(search: (_, _, _) async => throw failure);
    await expectLater(search.search('music'), throwsA(same(failure)));
  });
}
