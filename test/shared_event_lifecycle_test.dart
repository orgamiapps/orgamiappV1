import 'dart:async';
import 'package:attendus/Services/event_lifecycle_store.dart';
import 'package:attendus/screens/Events/shared_event_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/discovery_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DiscoveryFixture fixture;
  late EventLifecycleStore previous;
  late EventLifecycleStore store;
  setUp(() async {
    fixture = DiscoveryFixture();
    await fixture.install();
    previous = EventLifecycleStore.instance;
    store = EventLifecycleStore(
      watch: (_) => const Stream.empty(),
      currentUserId: () => 'map-widget-owner',
      userChanges: const Stream.empty(),
      observeAppLifecycle: false,
    );
    EventLifecycleStore.instance = store;
  });
  tearDown(() {
    EventLifecycleStore.instance = previous;
    store.dispose();
  });
  Future<void> initialize() async {}
  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Widget screen(String id) => MaterialApp(
    home: SharedEventScreen.test(eventId: id, initializeSession: initialize),
  );

  testWidgets(
    'old A capability result cannot mark B unavailable after widget reuse',
    (tester) async {
      final aCapabilities = Completer<Map<String, dynamic>>();
      final bDocument = Completer<Map<String, dynamic>?>();
      fixture.firestore.documentGet = (path, options) async {
        if (path == 'Events/a') {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          );
        }
        if (path == 'Events/b') return bDocument.future;
        return null;
      };
      fixture.functions.handler = (name, args) async {
        expect(name, 'getEventCapabilitiesV1');
        expect(args['eventId'], 'a');
        return aCapabilities.future;
      };
      await tester.pumpWidget(screen('a'));
      await flush(tester);
      expect(fixture.functions.requests, hasLength(1));
      await tester.pumpWidget(screen('b'));
      await flush(tester);
      aCapabilities.completeError(
        FirebaseFunctionsException(
          code: 'not-found',
          message: 'Event not found.',
        ),
      );
      await flush(tester);
      expect(find.text('Opening event…'), findsOneWidget);
      expect(store.stateFor('b').status, EventLifecycleStatus.unknown);
      expect(store.stateFor('a').status, EventLifecycleStatus.unknown);
      bDocument.complete(null);
      await flush(tester);
      expect(find.text('Event unavailable'), findsOneWidget);
      expect(store.stateFor('b').status, EventLifecycleStatus.deleted);
      final reads = fixture.firestore.documentReads
          .where((r) => r.$1.startsWith('Events/'))
          .toList();
      expect(reads.map((r) => r.$1), ['Events/a', 'Events/b']);
      expect(reads.every((r) => r.$2.source == Source.server), true);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline shared load cannot display cached private event for new session',
    (tester) async {
      fixture.firestore.documentGet = (path, options) async {
        if (options.source == Source.server) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'unavailable',
          );
        }
        return {
          ...discoveryEventFixture,
          'id': 'private',
          'title': 'Private cached secret',
          'private': true,
        };
      };
      await tester.pumpWidget(screen('private'));
      await flush(tester);
      expect(find.text('Could not open event'), findsOneWidget);
      expect(find.text('Private cached secret'), findsNothing);
      expect(find.text('This event requires access'), findsNothing);
      expect(store.stateFor('private').status, EventLifecycleStatus.unknown);
      expect(fixture.firestore.documentReads.single.$2.source, Source.server);
      expect(tester.takeException(), isNull);
    },
  );
}
