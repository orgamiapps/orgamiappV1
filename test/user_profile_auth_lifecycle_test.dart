import 'dart:async';

import 'package:attendus/Services/event_lifecycle_store.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/screens/MyProfile/user_profile_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/discovery_fixture.dart';
import 'support/load_discovery_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDiscoveryFonts);

  testWidgets(
    'profile clears old account data and replaces a pending load after account switch',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = DiscoveryFixture();
      await fixture.install();
      final previousCustomer = CustomerController.logeInCustomer;
      final previousStore = EventLifecycleStore.instance;
      final store = EventLifecycleStore(
        currentUserId: () => FirebaseAuth.instance.currentUser?.uid,
        watch: (id) => Stream.value(
          EventLifecycleSnapshot(
            exists: true,
            fromCache: false,
            data: {...discoveryEventFixture, 'id': id},
          ),
        ),
        observeAppLifecycle: false,
      );
      EventLifecycleStore.instance = store;
      addTearDown(() {
        CustomerController.logeInCustomer = previousCustomer;
        EventLifecycleStore.instance = previousStore;
        store.dispose();
      });

      CustomerModel customer(String uid) => CustomerModel(
        uid: uid,
        name: uid,
        email: '',
        createdAt: DateTime(2026),
      );
      Map<String, dynamic> event(String id, String title) => {
        ...discoveryEventFixture,
        'id': id,
        'customerUid': 'profile-owner',
        'title': title,
      };
      CustomerController.logeInCustomer = customer('map-widget-owner');
      final oldLoad = Completer<List<Map<String, dynamic>>>();
      final thirdLoad = Completer<List<Map<String, dynamic>>>();
      var eventReads = 0;
      fixture.firestore.collectionGet = (path) async {
        if (path != 'Events') return [];
        eventReads++;
        if (eventReads == 1) return oldLoad.future;
        if (eventReads == 3) return thirdLoad.future;
        return [event('new-visible', 'New account visible event')];
      };
      Future<void> flush() async {
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.pumpWidget(
        fixture.app(body: UserProfileScreen(user: customer('profile-owner'))),
      );
      await flush();
      expect(find.text('Loading profile...'), findsOneWidget);
      expect(eventReads, 1);

      CustomerController.logeInCustomer = customer('viewer-b');
      fixture.auth.changeUser('viewer-b');
      await flush();
      expect(store.sessionGeneration, 1);
      expect(eventReads, 2);
      expect(find.text('Loading profile...'), findsNothing);
      expect(find.text('New account visible event'), findsOneWidget);

      oldLoad.complete([event('old-secret', 'Old account private event')]);
      await flush();
      expect(find.text('Old account private event'), findsNothing);
      expect(find.text('New account visible event'), findsOneWidget);
      expect(eventReads, 2);

      CustomerController.logeInCustomer = customer('viewer-c');
      fixture.auth.changeUser('viewer-c');
      await flush();
      expect(find.text('New account visible event'), findsNothing);
      expect(find.text('Loading profile...'), findsOneWidget);
      thirdLoad.complete([event('third-visible', 'Third account event')]);
      await flush();
      expect(find.text('Loading profile...'), findsNothing);
      expect(find.text('Third account event'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
