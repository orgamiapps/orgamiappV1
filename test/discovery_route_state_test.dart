import 'dart:async';

import 'package:attendus/models/discovery_route_state.dart';
import 'package:attendus/Services/discovery_history_coordinator.dart';
import 'package:attendus/Services/discovery_history_port.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryHistory implements DiscoveryHistoryPort {
  MemoryHistory(this.onRestore);
  final void Function(Uri, double) onRestore;
  final entries = <(Uri, double)>[(Uri(path: '/'), 0)];
  int index = 0;
  @override
  Uri get currentUri => entries[index].$1;
  @override
  double get scroll => entries[index].$2;
  @override
  bool get available => true;
  @override
  void dispose() {}
  @override
  void write(Uri uri, double offset, {required bool push}) {
    if (push) {
      entries.removeRange(index + 1, entries.length);
      entries.add((uri, offset));
      index++;
    } else {
      entries[index] = (uri, offset);
    }
  }

  void back() {
    index--;
    onRestore(currentUri, scroll);
  }

  void forward() {
    index++;
    onRestore(currentUri, scroll);
  }
}

void main() {
  for (final scenario in ['unready', 'late', 'disposed', 'detached']) {
    testWidgets(
      'history restoration handles an attached viewport that is $scenario',
      (tester) async {
        final scroll = ScrollController();
        var ready = false;
        late StateSetter rebuild;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return Scrollable(
                  controller: scroll,
                  viewportBuilder: (context, offset) => ready
                      ? Viewport(
                          offset: offset,
                          slivers: [
                            SliverFixedExtentList(
                              itemExtent: 80,
                              delegate: SliverChildBuilderDelegate(
                                (context, index) => Text('$index'),
                                childCount: 50,
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                );
              },
            ),
          ),
        );
        expect(scroll.hasClients, isTrue);
        expect(scroll.position.hasContentDimensions, isFalse);
        final state = DiscoveryRouteState({'q': 'saved'});
        late MemoryHistory history;
        final coordinator = DiscoveryHistoryCoordinator(
          snapshot: () => state,
          restore: (_) async {},
          scrollController: () => scroll,
          isActive: () => true,
          createBackend: (restore, _) {
            history = MemoryHistory(restore);
            history.entries[0] = (state.uri, 240);
            return history;
          },
        );
        Object? failure;
        var completed = false;
        final initialized = coordinator.initialize().then<void>(
          (_) => completed = true,
          onError: (Object error) {
            failure = error;
            completed = true;
          },
        );
        await tester.pump();
        if (scenario == 'disposed') coordinator.dispose();
        if (scenario == 'late' || scenario == 'disposed') {
          rebuild(() => ready = true);
        }
        if (scenario == 'detached') {
          await tester.pumpWidget(const SizedBox());
        }
        for (var frame = 0; frame < 8; frame++) {
          await tester.pump();
        }
        expect(completed, isTrue, reason: 'Restoration has a bounded wait');
        await initialized;
        expect(failure, isNull);
        if (scenario == 'detached') {
          expect(scroll.hasClients, isFalse);
        } else {
          expect(scroll.offset, scenario == 'late' ? 240 : 0);
        }
        expect(
          history.scroll,
          240,
          reason: 'Unready layout cannot erase history',
        );
        if (scenario != 'disposed') coordinator.dispose();
        expect(history.scroll, 240, reason: 'Disposal preserves saved history');
        await tester.pumpWidget(const SizedBox());
        scroll.dispose();
      },
    );
  }
  testWidgets('a superseded restoration cannot overwrite a newer entry', (
    tester,
  ) async {
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          controller: scroll,
          children: List.generate(
            50,
            (i) => SizedBox(height: 80, child: Text('$i')),
          ),
        ),
      ),
    );
    final firstRestore = Completer<void>();
    late MemoryHistory history;
    final coordinator = DiscoveryHistoryCoordinator(
      snapshot: () => DiscoveryRouteState({'q': 'unused'}),
      restore: (route) async {
        if (route['q'] == 'first') await firstRestore.future;
      },
      scrollController: () => scroll,
      isActive: () => true,
      createBackend: (restore, _) {
        history = MemoryHistory(restore);
        history.entries[0] = (DiscoveryRouteState({'q': 'first'}).uri, 240);
        return history;
      },
    );
    final first = coordinator.initialize();
    history.entries[0] = (DiscoveryRouteState({'q': 'second'}).uri, 480);
    final second = coordinator.initialize();
    await tester.pump();
    await second;
    expect(scroll.offset, 480);
    firstRestore.complete();
    await tester.pump();
    await first;
    expect(scroll.offset, 480);
    expect(history.currentUri.queryParameters['q'], 'second');
    expect(history.scroll, 480);
    coordinator.dispose();
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });
  test('canonical filters round trip independent of query order', () {
    final state = DiscoveryRouteState.fromUri(
      Uri.parse(
        '/app/discover?online=true&q=music%20%26%20food&categories=Music,Arts,Music&date=weekend&free=1',
      ),
    );
    expect(
      state.uri.toString(),
      '/app/discover?categories=Arts%2CMusic&date=weekend&free=1&online=1&q=music+%26+food',
    );
    expect(DiscoveryRouteState.fromUri(state.uri).values, state.values);
  });
  test('invalid values and credentials cannot enter canonical URLs', () {
    final state = DiscoveryRouteState({
      'q': 'x' * 200,
      'lat': 'NaN',
      'lng': '180',
      'radius': '900000',
      'date': 'tomorrow',
      'token': 'secret',
      'sort': 'injected',
    });
    expect(state['q']!.length, 160);
    expect(state.values.keys, ['q']);
    final location = DiscoveryRouteState({
      'lat': '34.123456',
      'lng': '-77.123456',
    });
    expect(location['lat'], '34.12');
    expect(location['lng'], '-77.12');
    expect(
      DiscoveryRouteState({
        'lat': '34',
        'lng': '-77',
        'nationwide': '1',
      }).values,
      {'nationwide': '1'},
    );
  });
  testWidgets('Back and Forward retain independent filter and scroll entries', (
    tester,
  ) async {
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          controller: scroll,
          children: List.generate(
            50,
            (i) => SizedBox(height: 80, child: Text('$i')),
          ),
        ),
      ),
    );
    var current = DiscoveryRouteState({'q': 'first'});
    var active = true;
    late MemoryHistory history;
    final coordinator = DiscoveryHistoryCoordinator(
      snapshot: () => current,
      restore: (value) async {
        current = value;
      },
      scrollController: () => scroll,
      isActive: () => active,
      createBackend: (restore, _) => history = MemoryHistory(restore),
    );
    await coordinator.initialize();
    scroll.jumpTo(240);
    coordinator.saveScroll();
    current = DiscoveryRouteState({'q': 'second', 'free': '1'});
    coordinator.flush();
    scroll.jumpTo(480);
    coordinator.saveScroll();
    history.back();
    await tester.pump();
    await tester.pump();
    expect(current['q'], 'first');
    expect(scroll.offset, 240);
    history.forward();
    await tester.pump();
    await tester.pump();
    expect(current['q'], 'second');
    expect(scroll.offset, 480);
    active = false;
    current = DiscoveryRouteState({'q': 'hidden'});
    coordinator.flush();
    expect(history.currentUri.queryParameters['q'], 'second');
    active = true;
    scroll.jumpTo(720);
    coordinator.scheduleScroll();
    coordinator.dispose();
    expect(
      history.scroll,
      720,
      reason: 'Disposal persists the final visible scroll position',
    );
    await tester.pump(const Duration(seconds: 1));
    expect(
      history.scroll,
      720,
      reason: 'A pending scroll timer cannot overwrite disposal',
    );
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });
}
