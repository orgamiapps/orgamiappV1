import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/screens/MyProfile/my_profile_screen.dart';
import 'package:attendus/screens/MyProfile/my_registrations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/discovery_fixture.dart';
import 'support/load_discovery_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDiscoveryFonts);

  testWidgets(
    'Profile activity opens unified registrations and scrolls to Saved and Created',
    (tester) async {
      tester.view.physicalSize = const Size(390, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = DiscoveryFixture();
      await fixture.install();
      final previous = CustomerController.logeInCustomer;
      CustomerController.logeInCustomer = CustomerModel(
        uid: 'map-widget-owner',
        name: 'Preview Member',
        email: '',
        createdAt: DateTime(2026),
      );
      addTearDown(() => CustomerController.logeInCustomer = previous);
      Future<void> settle() async {
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.pumpWidget(
        fixture.app(body: const MyProfileScreen(showBackButton: false)),
      );
      await settle();
      final activity = find.byKey(const ValueKey('profile-activity-links'));
      expect(activity, findsOneWidget);
      await tester.ensureVisible(find.text('Registrations and tickets'));
      await tester.tap(find.text('Registrations and tickets'));
      await settle();
      expect(find.byType(MyRegistrationsScreen), findsOneWidget);
      expect(
        fixture.functions.requests.any((r) => r.$1 == 'listMyAdmissionsV1'),
        true,
      );
      await tester.pageBack();
      await settle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 1500));
      await settle();
      await tester.ensureVisible(find.text('Saved events'));
      await tester.tap(find.text('Saved events'));
      await settle();
      expect(
        tester.widget<Text>(find.text('Saved (0)')).style?.fontWeight,
        FontWeight.w600,
      );
      final saved = tester.getRect(find.text('Saved (0)').last);
      expect(saved.top, greaterThan(0));
      expect(
        saved.bottom,
        lessThan(tester.getTopLeft(find.byType(NavigationBar)).dy),
      );
      // The shortcut also scrolls when the destination tab was already selected.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 1500));
      await settle();
      await tester.ensureVisible(find.text('Saved events'));
      await tester.tap(find.text('Saved events'));
      await settle();
      expect(tester.getRect(find.text('Saved (0)').last).bottom, lessThan(660));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 1500));
      await settle();
      await tester.ensureVisible(find.text('Organizer workspace'));
      await tester.tap(find.text('Organizer workspace'));
      await settle();
      expect(
        tester.widget<Text>(find.text('Created (0)')).style?.fontWeight,
        FontWeight.w600,
      );
      expect(
        tester.getRect(find.text('Created (0)').last).bottom,
        lessThan(660),
      );
      expect(find.text('My Tickets', skipOffstage: false), findsOneWidget);
      expect(
        find.text('My Attendus pass', skipOffstage: false),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 30));
    },
  );
}
