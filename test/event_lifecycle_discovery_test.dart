import 'dart:async';

import 'package:attendus/Services/event_lifecycle_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/discovery_fixture.dart';
import 'support/load_discovery_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDiscoveryFonts);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<(DiscoveryFixture, StreamController<EventLifecycleSnapshot>)> mount(
    WidgetTester tester, {
    Completer<Map<String, dynamic>>? pendingFeed,
  }) async {
    final fixture = DiscoveryFixture();
    await fixture.install(guest: true);
    final previous = EventLifecycleStore.instance;
    final source = StreamController<EventLifecycleSnapshot>.broadcast();
    final store = EventLifecycleStore(
      currentUserId: () => 'online-guest',
      userChanges: const Stream.empty(),
      observeAppLifecycle: false,
      watch: (_) => source.stream,
    );
    EventLifecycleStore.instance = store;
    fixture.functions.handler = (name, data) async {
      if (!name.startsWith('searchDiscoveryEvents')) {
        return <String, dynamic>{};
      }
      return pendingFeed?.future ??
          {
            'feedVersion': 1,
            'events': [discoveryEventFixture],
          };
    };
    await tester.pumpWidget(fixture.app());
    await settle(tester);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      EventLifecycleStore.instance = previous;
      await source.close();
      await tester.pump(const Duration(seconds: 1));
    });
    return (fixture, source);
  }

  testWidgets('another online session cancellation removes Discover cards', (
    tester,
  ) async {
    final (_, source) = await mount(tester);
    expect(find.text('Community garden evening'), findsWidgets);
    source.add(
      EventLifecycleSnapshot(
        exists: true,
        fromCache: false,
        data: {...discoveryEventFixture, 'status': 'cancelled'},
      ),
    );
    await settle(tester);
    expect(find.text('Community garden evening'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server deletion removes recommendation and feed together', (
    tester,
  ) async {
    final (_, source) = await mount(tester);
    expect(find.text('Community garden evening'), findsWidgets);
    source.add(const EventLifecycleSnapshot(exists: false, fromCache: false));
    await settle(tester);
    expect(find.text('Community garden evening'), findsNothing);
  });

  testWidgets('late callable response cannot resurrect confirmed deletion', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    await mount(tester, pendingFeed: pending);
    EventLifecycleStore.instance.applyConfirmed(
      eventIds: ['compact-discovery-event'],
      status: EventLifecycleStatus.deleted,
    );
    pending.complete({
      'feedVersion': 1,
      'events': [discoveryEventFixture],
    });
    await settle(tester);
    expect(find.text('Community garden evening'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
