import 'dart:async';

import 'package:attendus/Services/event_lifecycle_store.dart';
import 'package:attendus/Services/subscription_service.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/screens/MyProfile/my_profile_screen.dart';
import 'package:attendus/screens/MyProfile/my_registrations_screen.dart';
import 'package:attendus/screens/MyProfile/my_tickets_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/discovery_fixture.dart';
import 'support/load_discovery_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDiscoveryFonts);
  late DiscoveryFixture fixture;
  late EventLifecycleStore previousStore;
  late EventLifecycleStore lifecycle;
  late StreamController<EventLifecycleSnapshot> changes;
  CustomerModel? previousCustomer;
  final event = {...discoveryEventFixture, 'customerUid': 'map-widget-owner'};
  final eventId = event['id'] as String;

  setUp(() async {
    fixture = DiscoveryFixture();
    await fixture.install();
    fixture.firestore.collectionDocuments['Events'] = [event];
    previousCustomer = CustomerController.logeInCustomer;
    CustomerController.logeInCustomer = CustomerModel(
      uid: 'map-widget-owner',
      name: 'Preview Member',
      email: '',
      createdAt: DateTime(2026),
    );
    previousStore = EventLifecycleStore.instance;
    changes = StreamController<EventLifecycleSnapshot>.broadcast(sync: true);
    lifecycle = EventLifecycleStore(
      watch: (_) => changes.stream,
      currentUserId: () => 'map-widget-owner',
      userChanges: const Stream.empty(),
      observeAppLifecycle: false,
    );
    EventLifecycleStore.instance = lifecycle;
  });

  tearDown(() async {
    EventLifecycleStore.instance = previousStore;
    lifecycle.dispose();
    await changes.close();
    CustomerController.logeInCustomer = previousCustomer;
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> mount(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(780, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider<SubscriptionService>.value(
        value: SubscriptionService(),
        child: fixture.app(body: screen),
      ),
    );
    await settle(tester);
  }

  void remoteCancellation() => changes.add(
    EventLifecycleSnapshot(
      exists: true,
      fromCache: false,
      data: {...event, 'status': 'cancelled', 'eventRevision': 2},
    ),
  );

  Future<void> clean(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
  }

  testWidgets(
    'organizer list moves cancellation to history and removes deletion',
    (tester) async {
      await mount(tester, const MyProfileScreen(showBackButton: false));
      expect(find.text('Created (1)'), findsOneWidget);
      remoteCancellation();
      await settle(tester);
      expect(find.text('Created (0)'), findsOneWidget);
      expect(find.text('Community garden evening'), findsNothing);
      await tester.ensureVisible(find.text('Cancelled events'));
      await tester.tap(find.byType(SwitchListTile).last);
      await settle(tester);
      expect(find.text('Created (1)'), findsOneWidget);
      expect(find.text('Community garden evening'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      lifecycle.applyConfirmed(
        eventIds: [eventId],
        status: EventLifecycleStatus.deleted,
      );
      await settle(tester);
      expect(find.text('Community garden evening'), findsNothing);
      expect(find.text('No cancelled events'), findsOneWidget);
      await clean(tester);
    },
  );

  testWidgets('registration record updates cancellation without disappearing', (
    tester,
  ) async {
    fixture.functions.handler = (name, _) async => name == 'listMyAdmissionsV1'
        ? {
            'admissions': [
              {
                'eventId': eventId,
                'title': 'Community garden evening',
                'status': 'confirmed',
                'registrationId': 'registration-1',
                'start': '2030-10-19T21:00:00Z',
                'timeZone': 'America/New_York',
              },
            ],
          }
        : <String, dynamic>{};
    await mount(tester, const MyRegistrationsScreen());
    expect(find.text('Community garden evening'), findsOneWidget);
    remoteCancellation();
    await settle(tester);
    expect(find.text('Community garden evening'), findsOneWidget);
    expect(
      find.textContaining('Cancelled event · RSVP · confirmed'),
      findsOneWidget,
    );
    await clean(tester);
  });

  testWidgets('cancelled ticket leaves Active but retains a labelled record', (
    tester,
  ) async {
    fixture.firestore.collectionDocuments['Tickets'] = [
      {
        'id': 'ticket-1',
        'eventId': eventId,
        'eventTitle': 'Community garden evening',
        'eventImageUrl': '',
        'eventLocation': 'Riverside Park',
        'eventDateTime': Timestamp.fromDate(DateTime(2030, 10, 19)),
        'customerUid': 'map-widget-owner',
        'customerName': 'Preview Member',
        'ticketCode': 'TESTPASS',
        'issuedDateTime': Timestamp.fromDate(DateTime(2030, 10, 1)),
      },
    ];
    await mount(tester, const MyTicketsScreen());
    expect(find.text('Community garden evening'), findsOneWidget);
    remoteCancellation();
    await settle(tester);
    expect(find.text('Community garden evening'), findsOneWidget);
    expect(find.text('Cancelled'), findsOneWidget);
    await tester.tap(find.text('Community garden evening'));
    await settle(tester);
    expect(find.text('Cancelled event'), findsOneWidget);
    expect(find.text('My event pass'), findsNothing);
    expect(
      find.textContaining('Check-in is no longer available'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await settle(tester);
    await tester.tap(find.text('Active', skipOffstage: false).first);
    await settle(tester);
    expect(find.text('Community garden evening'), findsNothing);
    expect(find.text('No active tickets'), findsOneWidget);
    await clean(tester);
  });
}
