import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendus/models/event_wizard_model.dart';
import 'package:attendus/Services/event_wizard_service.dart';
import 'package:attendus/screens/Events/event_creation_wizard_screen.dart';
import 'support/wizard_fake.dart';

class CoverRepository extends TestWizardRepository {
  final uploads = <Completer<String>>[];
  int publishes = 0;
  bool failImageSave = false;
  @override
  Future<EventWizardDraft> saveDraft(EventWizardDraft draft) async {
    if (failImageSave && draft.imageUrl.isNotEmpty) {
      throw StateError('draft save failed');
    }
    return super.saveDraft(draft);
  }

  @override
  Future<String> uploadDraftImage({
    required EventWizardDraft draft,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) {
    final upload = Completer<String>();
    uploads.add(upload);
    return upload.future;
  }

  @override
  Future<EventWizardPublishResult> publish(
    EventWizardDraft draft, {
    int? expectedEventRevision,
    String? changeReason,
    String? changePreviewToken,
    String recurrenceScope = 'this_occurrence',
  }) async {
    publishes++;
    return super.publish(draft);
  }
}

final cover = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=',
);
EventWizardDraft draftFixture() => EventWizardDraft.blank()
  ..title = 'Cover fixture'
  ..locationType = 'in_person'
  ..locationInputMode = 'text'
  ..location = 'Community clubhouse'
  ..primaryDiscoveryCategoryId = 'community-causes';
Future<void> mount(
  WidgetTester tester,
  CoverRepository repo, {
  EventWizardDraft? initialDraft,
}) async {
  tester.view.physicalSize = const Size(1440, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: EventCreationWizardScreen(
        initialDraft: initialDraft ?? draftFixture(),
        service: repo,
        pickCoverBytes: () async => cover,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('removing an optional pin keeps the typed label', (tester) async {
    final draft = draftFixture()
      ..locationCoordinatesEnabled = true
      ..latitude = 35
      ..longitude = -80;
    await mount(tester, CoverRepository(), initialDraft: draft);
    await tester.ensureVisible(find.text('Remove map pin'));
    await tester.tap(find.text('Remove map pin'));
    await tester.pumpAndSettle();
    expect(draft.location, 'Community clubhouse');
    expect(draft.locationCoordinatesEnabled, false);
    expect(draft.latitude, 0);
    expect(find.text('Add map pin (optional)'), findsOneWidget);
  });
  testWidgets(
    'uploaded bytes are not called saved when the draft URL save fails',
    (tester) async {
      final repo = CoverRepository()..failImageSave = true;
      await mount(tester, repo);
      await tester.tap(find.text('Add a cover image'));
      await tester.pump();
      repo.uploads.single.complete('https://example.test/new-cover.png');
      await tester.pumpAndSettle();
      expect(find.text('Retry image upload'), findsOneWidget);
      expect(find.text('Image uploaded'), findsNothing);
      expect(repo.publishes, 0);
    },
  );

  testWidgets(
    'text-only location advances without a map and clears stale place when switching',
    (tester) async {
      await mount(tester, CoverRepository());
      final location = find.widgetWithText(
        TextFormField,
        'Location description',
      );
      await tester.ensureVisible(location);
      await tester.enterText(location, 'The garden pavilion');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Location description'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'publishing waits for an upload and does not publish after failure',
    (tester) async {
      final repo = CoverRepository();
      await mount(tester, repo);
      await tester.tap(find.text('Add a cover image'));
      await tester.pump();
      expect(repo.uploads, hasLength(1));
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Continue'));
        await tester.pump();
      }
      await tester.tap(find.text('Publish event').last);
      await tester.pump();
      expect(repo.publishes, 0);
      repo.uploads.single.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(repo.publishes, 0);
      expect(find.textContaining('Save the selected image'), findsWidgets);
    },
  );
  testWidgets(
    'failed upload can retry or remove, and superseded uploads cannot restore a removed cover',
    (tester) async {
      final repo = CoverRepository();
      await mount(tester, repo);
      await tester.tap(find.text('Add a cover image'));
      await tester.pump();
      repo.uploads.single.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Retry image upload'), findsOneWidget);
      await tester.tap(find.text('Retry image upload'));
      await tester.pump();
      expect(repo.uploads, hasLength(2));
      await tester.tap(find.text('Remove image'));
      await tester.pump();
      repo.uploads.last.complete('https://example.test/stale.png');
      await tester.pumpAndSettle();
      expect(find.text('Add a cover image'), findsOneWidget);
      expect(find.text('Image uploaded'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
