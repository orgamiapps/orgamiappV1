import 'package:attendus/screens/Events/premium_event_creation_wrapper.dart';
import 'package:attendus/models/event_model.dart';
import 'support/wizard_fake.dart';

import 'package:attendus/Services/event_wizard_service.dart';
import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/models/event_wizard_model.dart';
import 'package:attendus/screens/Events/event_creation_wizard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _StorageFailureRepository extends TestWizardRepository {
  @override
  Future<EventWizardDraft> saveDraft(EventWizardDraft draft) async =>
      throw StateError('offline');
  @override
  Future<void> saveLocalDraft(EventWizardDraft draft) async =>
      throw StateError('storage unavailable');
}

EventWizardDraft _draft() =>
    EventWizardDraft.blank(selectedDateTime: DateTime(2027, 6, 1, 18))
      ..title = 'Neighborhood meetup'
      ..description = 'Meet neighbors and local organizers.'
      ..locationType = 'online'
      ..location = 'https://meet.example.test/attendus'
      ..primaryDiscoveryCategoryId = 'community-causes'
      ..discoveryCategoryIds = ['community-causes'];

void main() {
  testWidgets(
    'step three defaults to RSVP only and enables attendance explicitly',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final draft = _draft()..currentStage = EventWizardStage.experience;
      await tester.pumpWidget(
        MaterialApp(
          theme: AttendUsTheme.light,
          home: EventCreationWizardScreen(
            initialDraft: draft,
            service: TestWizardRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final none = find.text('RSVP only — no attendance tracking');
      await tester.ensureVisible(none);
      expect(none, findsOneWidget);
      expect(find.text('Advanced check-in & security'), findsNothing);
      await tester.tap(find.text('Hybrid'));
      await tester.pumpAndSettle();
      expect(find.text('Advanced check-in & security'), findsOneWidget);
      await tester.tap(none);
      await tester.pumpAndSettle();
      expect(find.text('Advanced check-in & security'), findsNothing);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Publish event'), findsWidgets);
    },
  );

  testWidgets('question editor survives save and cancel closing transitions', (
    tester,
  ) async {
    final draft = _draft()..currentStage = EventWizardStage.registration;
    await tester.pumpWidget(
      MaterialApp(
        theme: AttendUsTheme.light,
        home: EventCreationWizardScreen(
          initialDraft: draft,
          service: TestWizardRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final action in ['Save question', 'Cancel']) {
      await tester.ensureVisible(find.text('Add question'));
      await tester.tap(find.text('Add question'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Question'),
        'Accessibility needs',
      );
      await tester.tap(find.text(action));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Accessibility needs'), findsOneWidget);
  });

  testWidgets(
    'autosave reports failure when both server and device storage fail',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AttendUsTheme.light,
          home: EventCreationWizardScreen(
            initialDraft: _draft(),
            service: _StorageFailureRepository(),
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Event title'),
        'Changed title',
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('Couldn’t sync'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing presentation configuration still opens the secure creation wizard',
    (tester) async {
      expect(resolveEventCreationExperienceVersion(null), 1);
      await tester.pumpWidget(
        MaterialApp(
          theme: AttendUsTheme.light,
          home: EventCreationExperienceGate(service: TestWizardRepository()),
        ),
      );
      await tester.pump();
      expect(find.byType(EventCreationWizardScreen), findsOneWidget);
    },
  );
  testWidgets(
    'edit draft denial offers retry and never falls back to a direct writer',
    (tester) async {
      final now = DateTime(2027, 6, 1);
      final event = EventModel(
        id: 'event',
        groupName: '',
        title: 'Event',
        description: '',
        location: 'Online',
        customerUid: 'owner',
        imageUrl: '',
        selectedDateTime: now,
        eventGenerateTime: now,
        status: 'scheduled',
        private: false,
        getLocation: false,
        radius: 0,
        latitude: 0,
        longitude: 0,
      );
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: EventCreationExperienceGate(
            event: event,
            service: TestWizardRepository(),
            editDraftLoader: (_) async {
              attempts++;
              throw StateError('Unavailable');
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(EventCreationWizardScreen), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(attempts, 2);
      expect(find.byType(EventCreationWizardScreen), findsNothing);
    },
  );

  testWidgets('desktop wizard exposes four progressive stages and preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AttendUsTheme.light,
        home: EventCreationWizardScreen(
          initialDraft: _draft(),
          service: TestWizardRepository(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Basics'), findsOneWidget);
    expect(find.text('Registration'), findsOneWidget);
    expect(find.text('Experience'), findsOneWidget);
    expect(find.text('Publish'), findsOneWidget);
    expect(find.text('Live attendee preview'), findsOneWidget);
    expect(find.text('Start with the essentials'), findsOneWidget);
  });

  testWidgets('mobile wizard advances without exposing advanced attendance', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AttendUsTheme.light,
        home: EventCreationWizardScreen(
          initialDraft: _draft(),
          service: TestWizardRepository(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Advanced check-in & security'), findsNothing);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Shape registration'), findsOneWidget);
  });
}
