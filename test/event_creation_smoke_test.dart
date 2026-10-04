import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/screens/Events/create_event_screen.dart';
import 'package:attendus/screens/Events/event_creation_wizard_screen.dart';
import 'package:attendus/screens/Events/premium_event_creation_wrapper.dart';
import 'package:attendus/models/event_wizard_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/wizard_fake.dart';

Future<void> wizard(WidgetTester tester, {EventWizardDraft? draft}) async {
  tester.view.physicalSize = const Size(1440, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AttendUsTheme.light,
      home: EventCreationWizardScreen(
        service: TestWizardRepository(),
        initialDraft: draft ?? EventWizardDraft.blank(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('event entrypoint never adds a premium purchase gate', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AttendUsTheme.light,
        home: const PremiumEventCreationWrapper(),
      ),
    );
    expect(find.byType(EventCreationExperienceGate), findsOneWidget);
    expect(find.text('Premium Required'), findsNothing);
  });
  testWidgets('legacy create routes to a safe retry state without Firebase', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AttendUsTheme.light, home: const CreateEventScreen()),
    );
    expect(find.byType(EventCreationExperienceGate), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Hosting as'), findsNothing);
  });
  testWidgets('secure wizard shell keeps advanced attendance out of basics', (
    tester,
  ) async {
    await wizard(tester);
    expect(find.text('Event title'), findsOneWidget);
    expect(find.text('Date and time'), findsOneWidget);
    expect(find.text('Advanced check-in & security'), findsNothing);
  });
  testWidgets('basics requires title and a valid in-person location', (
    tester,
  ) async {
    await wizard(tester);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Add an event title to continue.'), findsOneWidget);
    ScaffoldMessenger.of(
      tester.element(find.byType(EventCreationWizardScreen)),
    ).clearSnackBars();
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Event title'),
      'Community meetup',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      find.text('Add a valid event location to continue.'),
      findsOneWidget,
    );
  });
  testWidgets('online basics requires a meeting location', (tester) async {
    await wizard(
      tester,
      draft: EventWizardDraft.blank()
        ..title = 'Online meetup'
        ..locationType = 'online',
    );
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(
      find.text('Add a valid event location to continue.'),
      findsOneWidget,
    );
  });
  testWidgets('canonical date picker opens and can cancel', (tester) async {
    await wizard(tester);
    await tester.ensureVisible(find.text('Starts'));
    await tester.tap(find.text('Starts'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
  });
}
