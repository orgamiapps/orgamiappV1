import 'dart:typed_data';
import 'package:attendus/Services/event_wizard_service.dart';
import 'package:attendus/models/event_wizard_model.dart';

class TestWizardRepository implements EventWizardRepository {
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
    String? changeReason,
    String? changePreviewToken,
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
