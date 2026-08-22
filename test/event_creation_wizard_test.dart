import 'dart:typed_data';

import 'package:attendus/Services/event_wizard_service.dart';
import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/models/event_wizard_model.dart';
import 'package:attendus/screens/Events/event_creation_wizard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWizardRepository implements EventWizardRepository {
  @override
  Future<EventWizardDraft> saveDraft(EventWizardDraft draft) async {
    draft.draftId ??= 'draft-test';
    draft.revision += 1;
    return draft;
  }

  @override
  Future<void> saveLocalDraft(EventWizardDraft draft) async {}

  @override
  Future<EventWizardDraft?> restoreLocalDraft([String? draftId]) async => null;

  @override
  Future<List<EventWizardDraft>> listDrafts() async => const [];

  @override
  Future<List<Map<String, dynamic>>> listSavedTemplates({
    String? organizationId,
  }) async => const [];

  @override
  Future<String> uploadDraftImage({
    required EventWizardDraft draft,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async => 'https://example.test/cover.jpg';

  @override
  Future<EventWizardPublishResult> publish(
    EventWizardDraft draft, {
    int? expectedEventRevision,
    String recurrenceScope = 'this_occurrence',
  }) async => const EventWizardPublishResult(
    eventId: 'event-test',
    eventIds: ['event-test'],
    status: 'scheduled',
  );

  @override
  Future<void> saveTemplate({
    required String name,
    required EventWizardDraft draft,
    bool includeLocation = false,
    bool includeContact = false,
  }) async {}
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
          service: _FakeWizardRepository(),
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
          service: _FakeWizardRepository(),
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
