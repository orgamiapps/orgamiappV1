import 'package:attendus/Services/account_access_service.dart';
import 'package:attendus/Services/pending_auth_intent_service.dart';
import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/Utils/route_names.dart';
import 'package:attendus/screens/Authentication/login_screen.dart';
import 'package:attendus/screens/Authentication/create_account/create_account_screen.dart';
import 'package:attendus/widgets/account_required_sheet.dart';
import 'package:attendus/widgets/attendus_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget guestApp({bool guest = true, double scale = 1}) => MaterialApp(
  theme: AttendUsTheme.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Builder(
    builder: (context) => AttendUsScaffold(
      title: 'Discover',
      selectedIndex: 0,
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
        ),
      ],
      onDestinationSelected: (_) {},
      onLoginPressed: guest ? () => showGuestAuthSheet(context: context) : null,
      onNotificationsPressed: () {},
      body: const Center(child: Text('Discover events')),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in [320.0, 390.0, 768.0, 1280.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('guest header fits at $width and text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(guestApp(scale: scale));
        final login = find.widgetWithText(ElevatedButton, 'Log in');
        expect(login, findsOneWidget);
        expect(find.byTooltip('Notifications'), findsOneWidget);
        expect(tester.getSize(login).height, greaterThanOrEqualTo(48));
        expect(
          tester.getRect(login).right,
          lessThanOrEqualTo(
            tester.getRect(find.byTooltip('Notifications')).left,
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(login);
        await tester.pumpAndSettle();
        expect(find.text('Join the Attendus community'), findsOneWidget);
        expect(find.text('Create account'), findsOneWidget);
        if (scale == 1) {
          expect(
            tester.getSize(find.byType(BottomSheet)).height,
            lessThan(600),
          );
        }
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
      });
    }
  }

  testWidgets('guest action disappears and returns with account state', (
    tester,
  ) async {
    await tester.pumpWidget(guestApp());
    expect(find.text('Log in'), findsOneWidget);
    await tester.pumpWidget(guestApp(guest: false));
    expect(find.text('Log in'), findsNothing);
    expect(find.byTooltip('Notifications'), findsOneWidget);
    await tester.pumpWidget(guestApp());
    expect(find.text('Log in'), findsOneWidget);
  });

  testWidgets('keyboard opens the header modal', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(guestApp());
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Join the Attendus community'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'repeated header requests show one modal; dismissal preserves intent',
    (tester) async {
      await PendingAuthIntentService.rememberSaveEvent('saved-event');
      await tester.pumpWidget(guestApp());
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Log in'),
      );
      button.onPressed!();
      button.onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('Join the Attendus community'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      final intent = await PendingAuthIntentService.consume();
      expect(intent!.action, PendingAuthAction.saveEvent);
      expect(intent.eventId, 'saved-event');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Log in'));
      await tester.pumpAndSettle();
      expect(find.text('Join the Attendus community'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
    },
  );

  for (final createAccount in [false, true]) {
    testWidgets(
      'header auth choice create=$createAccount replaces stale intent with Home',
      (tester) async {
        await PendingAuthIntentService.rememberSharedEvent('old-event');
        await tester.pumpWidget(guestApp());
        await tester.tap(find.widgetWithText(ElevatedButton, 'Log in'));
        await tester.pumpAndSettle();
        await tester.tap(
          createAccount
              ? find.widgetWithText(ElevatedButton, 'Create account')
              : find.widgetWithText(OutlinedButton, 'Log in'),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(createAccount ? CreateAccountScreen : LoginScreen),
          findsOneWidget,
        );
        final intent = await PendingAuthIntentService.consume();
        expect(intent!.action, PendingAuthAction.dashboardTab);
        expect(intent.dashboardTab, RouteNames.homeTab);
        expect(intent.eventId, isNull);
        expect(await PendingAuthIntentService.consume(), isNull);
        final context = tester.element(
          find.byType(createAccount ? CreateAccountScreen : LoginScreen),
        );
        Navigator.of(context).pop();
        await tester.pumpAndSettle();
        expect(find.text('Discover events'), findsOneWidget);
        await tester.tap(find.widgetWithText(ElevatedButton, 'Log in'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
      },
    );
  }

  for (final scenario in ['groups', 'shared', 'save']) {
    testWidgets('locked $scenario auth retains its destination', (
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
                  feature: AccountFeature.groups,
                  sharedEventId: scenario == 'shared' ? 'shared-event' : null,
                  saveEventId: scenario == 'save' ? 'save-event' : null,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Log in'));
      await tester.pumpAndSettle();
      final intent = await PendingAuthIntentService.consume();
      if (scenario == 'groups') {
        expect(intent!.dashboardTab, RouteNames.groupsTab);
      } else {
        expect(
          intent!.action,
          scenario == 'shared'
              ? PendingAuthAction.sharedEvent
              : PendingAuthAction.saveEvent,
        );
        expect(intent.eventId, '$scenario-event');
      }
      expect(find.byType(LoginScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(LoginScreen))).pop();
      await tester.pumpAndSettle();
    });
  }
}
