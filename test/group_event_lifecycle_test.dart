import 'package:attendus/Services/event_lifecycle_store.dart';
import 'package:attendus/screens/Groups/manage_feed_posts_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/discovery_fixture.dart';
import 'support/load_discovery_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDiscoveryFonts);

  for (final status in [
    EventLifecycleStatus.deleted,
    EventLifecycleStatus.cancelled,
  ]) {
    testWidgets('group queue removes $status before query delivery', (
      tester,
    ) async {
      final fixture = DiscoveryFixture();
      await fixture.install();
      fixture.firestore.collectionDocuments['Events'] = [
        {
          ...discoveryEventFixture,
          'organizationId': 'test-group',
          'selectedDateTime': Timestamp.fromDate(DateTime(2030)),
          'eventGenerateTime': Timestamp.fromDate(DateTime(2029)),
        },
      ];
      final previousStore = EventLifecycleStore.instance;
      final store = EventLifecycleStore(
        watch: (_) => const Stream.empty(),
        currentUserId: () => 'map-widget-owner',
        userChanges: const Stream.empty(),
        observeAppLifecycle: false,
      );
      EventLifecycleStore.instance = store;
      addTearDown(() {
        EventLifecycleStore.instance = previousStore;
        store.dispose();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: ManageFeedPostsScreen(organizationId: 'test-group'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Community garden evening'), findsOneWidget);

      store.applyConfirmed(
        eventIds: [discoveryEventFixture['id'] as String],
        status: status,
      );
      await tester.pumpAndSettle();
      expect(find.text('Community garden evening'), findsNothing);
      expect(find.text('No matching content'), findsOneWidget);
      // The source query still contains the old active record.
      expect(
        fixture.firestore.collectionDocuments['Events']!.single['status'],
        'active',
      );
    });
  }
}
