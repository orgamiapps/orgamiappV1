import 'dart:async';
import 'package:attendus/Services/event_lifecycle_store.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/screens/MyProfile/my_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/discovery_fixture.dart';
import 'support/load_discovery_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDiscoveryFonts);

  testWidgets(
    'Profile keeps partial selection, shows uncertain commit, and retries same receipt',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = DiscoveryFixture();
      await fixture.install();
      final previousUser = CustomerController.logeInCustomer;
      CustomerController.logeInCustomer = CustomerModel(
        uid: 'map-widget-owner',
        name: 'Preview Member',
        email: '',
        createdAt: DateTime(2026),
      );
      final previousStore = EventLifecycleStore.instance;
      final store = EventLifecycleStore(
        watch: (_) => const Stream.empty(),
        currentUserId: () => 'map-widget-owner',
        userChanges: const Stream.empty(),
        observeAppLifecycle: false,
      );
      EventLifecycleStore.instance = store;
      addTearDown(() {
        CustomerController.logeInCustomer = previousUser;
        EventLifecycleStore.instance = previousStore;
        store.dispose();
      });
      fixture.firestore.collectionDocuments['Events'] = [
        for (final id in [
          'bulk-empty',
          'bulk-populated',
          'bulk-uncertain',
          'bulk-waiting',
        ])
          {
            ...discoveryEventFixture,
            'id': id,
            'title': id,
            'customerUid': 'map-widget-owner',
          },
      ];
      final uncertainRequests = <String>[];
      fixture.functions.handler = (name, args) async {
        final id = args['eventId'];
        if (name == 'getEventCapabilitiesV1') {
          return {
            'removalEligibility': {
              'canDelete': id != 'bulk-populated',
              'eventRevision': 3,
            },
          };
        }
        if (name == 'deleteEmptyEventV1') {
          if (id == 'bulk-uncertain') {
            uncertainRequests.add(args['requestId'] as String);
            if (uncertainRequests.length <= 2) {
              // The source listener can deliver the commit before the HTTP reply.
              store.applyConfirmed(
                eventIds: ['bulk-uncertain'],
                status: EventLifecycleStatus.deleted,
              );
              throw TimeoutException('response lost');
            }
          }
          return {
            'status': 'deleted',
            'affectedEventIds': [id],
          };
        }
        return <String, dynamic>{};
      };
      Future<void> settle() async {
        for (var i = 0; i < 25; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.pumpWidget(
        fixture.app(body: const MyProfileScreen(showBackButton: false)),
      );
      await settle();
      await tester.ensureVisible(find.text('Organizer workspace'));
      await tester.tap(find.text('Organizer workspace'));
      await settle();
      expect(find.text('Cancelled events'), findsOneWidget);
      await tester.ensureVisible(find.text('Select'));
      await tester.tap(find.text('Select'));
      await settle();
      await tester.ensureVisible(find.text('Select All'));
      await tester.tap(find.text('Select All'));
      await settle();
      await tester.ensureVisible(find.text('Delete 4 Events'));
      await tester.tap(find.text('Delete 4 Events'));
      await settle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
      await settle();
      final result = find.byKey(const ValueKey('profile-event-removal-result'));
      expect(result, findsOneWidget);
      expect(
        find.descendant(
          of: result,
          matching: find.textContaining('1 event deleted.'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: result,
          matching: find.textContaining('1 deletion is unconfirmed.'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: result,
          matching: find.textContaining('1 event was not attempted.'),
        ),
        findsOneWidget,
      );
      expect(find.text('bulk-empty'), findsNothing);
      expect(find.text('bulk-uncertain'), findsNothing);
      expect(find.text('bulk-populated'), findsOneWidget);
      expect(find.text('bulk-waiting'), findsOneWidget);
      expect(
        find.text('2 of 2 selected • 1 awaiting confirmation'),
        findsOneWidget,
      );
      expect(uncertainRequests, hasLength(2));
      await Scrollable.ensureVisible(
        tester.element(find.text('Retry unconfirmed deletion')),
        alignment: 0.5,
      );
      await tester.pump();
      await tester.tap(find.text('Retry unconfirmed deletion'));
      await settle();
      expect(uncertainRequests, hasLength(3));
      expect(uncertainRequests.toSet(), hasLength(1));
      expect(
        find.descendant(
          of: result,
          matching: find.textContaining('2 events deleted.'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('deletion is unconfirmed'), findsNothing);
      expect(find.text('Review bulk-populated'), findsOneWidget);
      expect(find.text('2 of 2 selected'), findsOneWidget);
      expect(
        fixture.functions.requests.where(
          (r) =>
              r.$1 == 'deleteEmptyEventV1' &&
              r.$2['eventId'] == 'bulk-populated',
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 30));
    },
  );
}
