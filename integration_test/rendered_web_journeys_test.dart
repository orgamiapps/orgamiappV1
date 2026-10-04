import 'dart:async';
import 'package:attendus/main.dart' as application;
import 'package:attendus/Services/auth_service.dart';
import 'package:attendus/Services/creation_limit_service.dart';
import 'package:attendus/Services/firebase_initializer.dart';
import 'package:attendus/Services/guest_mode_service.dart';
import 'package:attendus/Services/subscription_service.dart';
import 'package:attendus/Utils/theme_provider.dart';
import 'package:attendus/firebase_options.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/models/event_wizard_model.dart';
import 'package:attendus/screens/Authentication/login_screen.dart';
import 'package:attendus/screens/Events/Attendance/check_in_console_screen.dart';
import 'package:attendus/screens/Events/event_creation_wizard_screen.dart';
import 'package:attendus/screens/Home/account_details_screen.dart';
import 'package:attendus/widgets/auth_gate.dart';
import 'package:attendus/widgets/public_registration_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'fixture_harness.dart';

Future<void> until(
  WidgetTester tester,
  bool Function() ready,
  String description, {
  int seconds = 90,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  if (!ready()) {
    await IntegrationTestWidgetsFlutterBinding.ensureInitialized().takeScreenshot(
      'failure-${description.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-')}',
    );
  }
  expect(
    ready(),
    isTrue,
    reason:
        '$description\nVisible text: ${find.byType(Text).evaluate().map((element) => (element.widget as Text).data ?? '').join(' | ')}',
  );
}

Future<void> tapText(WidgetTester tester, String text) async {
  final matches = find.text(text);
  await until(
    tester,
    () => matches.evaluate().isNotEmpty,
    'Expected action $text',
  );
  final finder = matches.last;
  await tester.ensureVisible(finder);
  // Scrolling updates the viewport before the next layout. Hit-test the
  // rendered button only after its new position has been painted.
  await tester.pump();
  final paintedTarget = finder.hitTestable();
  expect(
    paintedTarget,
    findsOneWidget,
    reason: 'Action $text must be hit-testable after scrolling',
  );
  await tester.tap(paintedTarget);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> showApplication(WidgetTester tester, Widget home) async {
  expect(DefaultFirebaseOptions.environment, 'emulator');
  await FirebaseInitializer.initializeOnce();
  await GuestModeService().initialize();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  // Real app shell/providers/routes; optional main() Maps/push bootstrap is
  // excluded. Exact packaged production bootstrap is a separate browser gate.
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider.value(value: GuestModeService()),
        ChangeNotifierProvider(create: (_) => SubscriptionService()),
        ChangeNotifierProvider(create: (_) => CreationLimitService()),
      ],
      child: application.MyApp(homeOverride: home),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> loginThroughForm(
  WidgetTester tester,
  Map<String, dynamic> account,
) async {
  await until(
    tester,
    () => find.text('Welcome back').evaluate().isNotEmpty,
    'Login screen',
  );
  await tester.enterText(
    find.byType(TextFormField).at(0),
    account['email'] as String,
  );
  await tester.enterText(
    find.byType(TextFormField).at(1),
    account['password'] as String,
  );
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await until(
    tester,
    () => FirebaseAuth.instance.currentUser?.uid == account['uid'],
    'Form login authenticated the fixture account',
  );
  await until(
    tester,
    () =>
        find.text('Discover').evaluate().isNotEmpty &&
        find.text('Welcome back').evaluate().isEmpty,
    'Discover restored after login',
  );
  await until(
    tester,
    () => find.byType(LoginScreen, skipOffstage: false).evaluate().isEmpty,
    'Completed login route disposal before the next navigation',
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'rendered guest restrictions, keyboard login and owner profile save',
    (tester) async {
      await FirebaseInitializer.initializeOnce();
      await FirebaseAuth.instance.signOut();
      final owner = await BrowserFixtures.post('/__accounts/owner');
      await showApplication(tester, const AuthGate(forceDiscover: true));
      await until(
        tester,
        () => find.text('Discover').evaluate().isNotEmpty,
        'Guest Discover',
      );
      await BrowserFixtures.track();
      final guestUid = FirebaseAuth.instance.currentUser?.uid;
      await until(
        tester,
        () => find.byTooltip('Create event').evaluate().isNotEmpty,
        'Accessible event creation action',
      );
      await tester.tap(find.byTooltip('Create event'));
      await until(
        tester,
        () => find.text('Not now').evaluate().isNotEmpty,
        'Contextual guest restriction',
      );
      await tapText(tester, 'Not now');
      expect(FirebaseAuth.instance.currentUser?.uid, guestUid);
      expect(find.text('Discover'), findsWidgets);
      await tapText(tester, 'Log in');
      await tapText(tester, 'Log in');
      await until(
        tester,
        () => find.byType(TextFormField).evaluate().length == 2,
        'Login form fields',
      );
      await tester.enterText(find.byType(TextFormField).first, 'invalid');
      await tester.enterText(find.byType(TextFormField).last, '123');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(FirebaseAuth.instance.currentUser?.uid, guestUid);
      await loginThroughForm(tester, owner);
      unawaited(
        application.appNavigatorKey.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const AccountDetailsScreen()),
        ),
      );
      await until(
        tester,
        () => find
            .byWidgetPredicate(
              (widget) =>
                  widget is TextField &&
                  widget.decoration?.hintText == 'Enter your full name',
            )
            .evaluate()
            .isNotEmpty,
        'Owner account editor',
      );
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.hintText == 'Enter your full name',
        ),
        'UI Updated Organizer',
      );
      await tapText(tester, 'Save Changes');
      await until(
        tester,
        () => find
            .text('Account details updated successfully!')
            .evaluate()
            .isNotEmpty,
        'Profile save succeeds',
      );
      final profile = await FirebaseFirestore.instance
          .collection('Customers')
          .doc(owner['uid'] as String)
          .get(const GetOptions(source: Source.server));
      expect(profile.get('name'), 'UI Updated Organizer');
      expect(profile.get('eventsCreated'), 0);
      await binding.takeScreenshot('owner-profile-saved');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Discover disposes without ancestor lookup errors',
      );
      await FirebaseAuth.instance.signOut();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'rendered wizard publication, guest form, roster and check-in lifecycle',
    (tester) async {
      await FirebaseInitializer.initializeOnce();
      final owner = await BrowserFixtures.post('/__accounts/owner');
      await showApplication(tester, const LoginScreen());
      await loginThroughForm(tester, owner);
      final draft = EventWizardDraft.blank(
        selectedDateTime: DateTime.now().add(const Duration(minutes: 30)),
      );
      String? publishedId;
      unawaited(
        application.appNavigatorKey.currentState!
            .push<String>(
              MaterialPageRoute(
                builder: (_) => EventCreationWizardScreen(initialDraft: draft),
              ),
            )
            .then((id) => publishedId = id),
      );
      await until(
        tester,
        () => find
            .widgetWithText(TextFormField, 'Event title')
            .evaluate()
            .isNotEmpty,
        'Creation form',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Event title'),
        'Rendered browser event',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Local rendered organizer qualification.',
      );
      await tapText(tester, 'Online');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Online location or meeting link'),
        'https://example.test/local-meeting',
      );
      await tapText(tester, 'Continue');
      await until(
        tester,
        () => find.text('Free ticket').evaluate().isNotEmpty,
        'Registration stage',
      );
      await tapText(tester, 'Free ticket');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Capacity (optional)'),
        '5',
      );
      await tapText(tester, 'Add question');
      await tester.enterText(
        find.widgetWithText(TextField, 'Question'),
        'Accessibility needs',
      );
      await tapText(tester, 'Registration');
      await tapText(tester, 'Save question');
      await tapText(tester, 'Continue');
      await until(
        tester,
        () => find.text('Step 3 of 4').evaluate().isNotEmpty,
        'Attendance stage',
      );
      await tapText(tester, 'Continue');
      await until(
        tester,
        () => find.text('Ready to publish?').evaluate().isNotEmpty,
        'Review stage',
      );
      final category = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Primary discovery category',
      );
      await tester.ensureVisible(category);
      await tester.tap(category);
      await tester.pump(const Duration(milliseconds: 300));
      await tapText(tester, 'Music & Nightlife');
      await binding.takeScreenshot('organizer-publication-review');
      await tapText(tester, 'Publish event');
      await until(
        tester,
        () => find.text('Your event is live').evaluate().isNotEmpty,
        'Authoritative publication',
      );
      await tapText(tester, 'Done');
      await until(
        tester,
        () => publishedId != null,
        'Published event route result',
      );
      await BrowserFixtures.track(eventId: publishedId);
      await BrowserFixtures.post('/__track', {
        'eventId': publishedId,
        'seedLegacyDoorQuestion': true,
      });
      final snapshot = await FirebaseFirestore.instance
          .collection('Events')
          .doc(publishedId)
          .get();
      final event = EventModel.fromJson({
        ...snapshot.data()!,
        'id': publishedId,
      });
      expect(event.title, 'Rendered browser event');
      expect(
        event.selectedDateTime.isAtSameMomentAs(draft.startAt),
        isTrue,
        reason: 'Publication preserves the instant chosen in the local picker',
      );
      expect(event.eventEndTime.isAtSameMomentAs(draft.endAt), isTrue);
      final attendee = await BrowserFixtures.post('/__accounts/attendee');
      await tester.pumpWidget(const SizedBox.shrink());
      await FirebaseAuth.instance.signOut();
      await showApplication(tester, const LoginScreen());
      await loginThroughForm(tester, attendee);
      Map<String, dynamic>? registered;
      unawaited(
        PublicRegistrationCard.showForm(
          application.appNavigatorKey.currentContext!,
          event,
        ).then((result) => registered = result),
      );
      await until(
        tester,
        () => find.text('Confirm registration').evaluate().isNotEmpty,
        'Rendered attendee registration form',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full name'),
        attendee['name'] as String,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        attendee['email'] as String,
      );
      await until(
        tester,
        () => find
            .widgetWithText(TextFormField, 'Accessibility needs')
            .evaluate()
            .isNotEmpty,
        'Registration question loaded from the published event',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Accessibility needs'),
        'Step-free access',
      );
      await tapText(tester, 'Confirm registration');
      await until(tester, () => registered != null, 'Registration completed');
      expect(registered?['status'], 'confirmed');
      await tester.pumpWidget(const SizedBox.shrink());
      await FirebaseAuth.instance.signOut();
      await AuthService().signInWithEmailAndPassword(
        owner['email'] as String,
        owner['password'] as String,
      );
      await showApplication(tester, CheckInConsoleScreen(event: event));
      await until(
        tester,
        () => find.text('Start check-in').evaluate().isNotEmpty,
        'Organizer check-in console',
      );
      await tapText(tester, 'Start check-in');
      await until(
        tester,
        () => find.text('Start check-in').evaluate().isEmpty,
        'Door session started',
      );
      await until(
        tester,
        () => find
            .widgetWithText(TextButton, 'Check in')
            .evaluate()
            .any((element) => (element.widget as TextButton).onPressed != null),
        'Door preparation completed and roster action enabled',
      );
      await tapText(tester, 'Check in');
      await until(
        tester,
        () => find
            .widgetWithText(TextField, 'Door access code *')
            .evaluate()
            .isNotEmpty,
        'Legacy check-in question with omitted timing',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Door access code *'),
        'LOCAL-ONLY',
      );
      await tapText(tester, 'Continue');
      expect(
        find.text('Accessibility needs'),
        findsNothing,
        reason: 'Registration-only questions must not be asked at the door.',
      );
      await until(
        tester,
        () => find
            .textContaining('${attendee['name']} checked in at ')
            .evaluate()
            .isNotEmpty,
        'Rendered admission receipt',
      );
      await binding.takeScreenshot('roster-admitted-attendee');
      await tapText(tester, 'Pause check-in');
      await until(
        tester,
        () => find.text('Check-in paused').evaluate().isNotEmpty,
        'Pause lifecycle reflected',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await FirebaseAuth.instance.signOut();
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets(
    'narrow 200-percent login remains operable by keyboard',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await showApplication(tester, const LoginScreen());
      await tester.enterText(find.byType(TextFormField).first, 'invalid');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.enterText(find.byType(TextFormField).last, '123');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      await tester.ensureVisible(find.text('Log in').last);
      await binding.takeScreenshot('login-390px-200percent');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
