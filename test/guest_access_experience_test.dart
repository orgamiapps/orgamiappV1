import 'dart:async';

import 'package:attendus/Services/account_access_service.dart';
import 'package:attendus/Services/guest_attendance_service.dart';
import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/widgets/account_required_sheet.dart';
import 'package:attendus/widgets/attendus_scaffold.dart';
import 'package:attendus/widgets/deferred_premium_event_creation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('guest full-name validation rejects unsafe or incomplete values', () {
    expect(GuestAttendanceService.validateFullName(''), isNotNull);
    expect(GuestAttendanceService.validateFullName('A'), isNotNull);
    expect(GuestAttendanceService.validateFullName('<script>'), isNotNull);
    expect(GuestAttendanceService.validateFullName('Jordan Lee'), isNull);
    expect(GuestAttendanceService.validateFullName("Renée O'Neil"), isNull);
  });

  testWidgets('locked navigation renders a lock marker on mobile', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AttendUsTheme.light,
        home: AttendUsScaffold(
          title: 'Discover',
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          destinations: const [
            AttendUsNavDestination(
              label: 'Home',
              icon: Icons.home_outlined,
              selectedIcon: Icons.home,
            ),
            AttendUsNavDestination(
              label: 'Groups',
              icon: Icons.groups_outlined,
              selectedIcon: Icons.groups,
              requiresAccount: true,
            ),
          ],
          body: const SizedBox.shrink(),
        ),
      ),
    );

    expect(find.byIcon(Icons.lock), findsOneWidget);
  });

  testWidgets('account-required sheet offers both auth choices', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AttendUsTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAccountRequiredSheet(
                context: context,
                feature: AccountFeature.messages,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in to message'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets(
    'pending event creation resumes after its deferred library loads',
    (tester) async {
      var loaded = false;
      final deferredLoad = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: DeferredPremiumEventCreation(
            loadLibraryOverride: () async {
              await deferredLoad.future;
              loaded = true;
            },
            builderOverride: (_) =>
                const Scaffold(body: Text('Event creation resumed')),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      deferredLoad.complete();
      await tester.pumpAndSettle();

      expect(loaded, isTrue);
      expect(find.text('Event creation resumed'), findsOneWidget);
    },
  );
}
