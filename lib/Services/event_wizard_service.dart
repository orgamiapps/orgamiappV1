import 'package:attendus/Services/event_draft_local_store.dart';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:attendus/models/event_wizard_model.dart';

int resolveEventCreationExperienceVersion(Map<String, dynamic>? data) =>
    data?['experienceVersion'] == 2 ? 2 : 1;

class EventWizardPublishResult {
  const EventWizardPublishResult({
    required this.eventId,
    required this.eventIds,
    required this.status,
    this.seriesId,
  });

  final String eventId;
  final List<String> eventIds;
  final String status;
  final String? seriesId;
}

abstract interface class EventWizardRepository {
  Future<EventWizardDraft?> restoreLocalDraft([String? draftId]);
  Future<void> saveLocalDraft(EventWizardDraft draft);
  Future<EventWizardDraft> saveDraft(EventWizardDraft draft);
  Future<List<EventWizardDraft>> listDrafts();
  Future<List<Map<String, dynamic>>> listSavedTemplates({
    String? organizationId,
  });
  Future<String> uploadDraftImage({
    required EventWizardDraft draft,
    required Uint8List bytes,
    String contentType,
  });
  Future<EventWizardPublishResult> publish(
    EventWizardDraft draft, {
    int? expectedEventRevision,
    String? changeReason,
    String? changePreviewToken,
    String recurrenceScope,
  });
  Future<void> saveTemplate({
    required String name,
    required EventWizardDraft draft,
    bool includeLocation,
    bool includeContact,
  });
}

class EventWizardService implements EventWizardRepository {
  EventWizardService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
       _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _ownerUid = FirebaseAuth.instance.currentUser?.uid;

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final String? _ownerUid;
  late final EventDraftLocalStore _localDrafts = EventDraftLocalStore(
    currentUid: () => FirebaseAuth.instance.currentUser?.uid,
  );
  void _checkSession() {
    if (_ownerUid == null ||
        FirebaseAuth.instance.currentUser?.uid != _ownerUid) {
      throw StateError('Account changed. Reopen the event editor.');
    }
  }

  Future<int> experienceVersion() async {
    try {
      final snapshot = await _firestore
          .collection('AppConfig')
          .doc('eventCreation')
          .get(const GetOptions(source: Source.serverAndCache));
      return resolveEventCreationExperienceVersion(snapshot.data());
    } catch (_) {
      return 1;
    }
  }

  @override
  Future<EventWizardDraft?> restoreLocalDraft([String? draftId]) {
    _checkSession();
    return _localDrafts.read(draftId);
  }

  @override
  Future<void> saveLocalDraft(EventWizardDraft draft) {
    _checkSession();
    return _localDrafts.write(draft);
  }

  Future<void> clearLocalDraft(EventWizardDraft draft) {
    _checkSession();
    return _localDrafts.clear(draft);
  }

  @override
  Future<EventWizardDraft> saveDraft(EventWizardDraft draft) async {
    _checkSession();
    await saveLocalDraft(draft);
    final result = await _functions.httpsCallable('saveEventDraftV1').call({
      'draftId': draft.draftId,
      'expectedRevision': draft.revision,
      'mode': draft.mode,
      'sourceEventId': draft.sourceEventId,
      'sourceSeriesId': draft.sourceSeriesId,
      'sourceEventRevision': draft.sourceEventRevision,
      'currentStage': draft.currentStage.index,
      'completedStages': [
        for (var index = 0; index < draft.currentStage.index; index++) index,
      ],
      'clientMutationId':
          '${FirebaseAuth.instance.currentUser?.uid ?? 'unknown'}-${DateTime.now().microsecondsSinceEpoch}',
      'formData': draft.toFormJson(),
    });
    _checkSession();
    final data = Map<String, dynamic>.from(result.data as Map);
    draft.draftId = data['draftId']?.toString();
    draft.revision = (data['revision'] as num?)?.round() ?? draft.revision;
    await saveLocalDraft(draft);
    return draft;
  }

  @override
  Future<List<EventWizardDraft>> listDrafts() async {
    _checkSession();
    final result = await _functions.httpsCallable('listEventDraftsV1').call();
    _checkSession();
    final data = Map<String, dynamic>.from(result.data as Map);
    return (data['drafts'] as List? ?? [])
        .map(
          (item) =>
              EventWizardDraft.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> listSavedTemplates({
    String? organizationId,
  }) async {
    _checkSession();
    final result = await _functions.httpsCallable('listEventTemplatesV1').call({
      'organizationId': organizationId,
    });
    _checkSession();
    final data = Map<String, dynamic>.from(result.data as Map);
    return [
      ...(data['personal'] as List? ?? const []),
      ...(data['group'] as List? ?? const []),
    ].map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<EventWizardDraft> duplicateEvent(String eventId) async {
    _checkSession();
    final result = await _functions
        .httpsCallable('duplicateEventToDraftV1')
        .call({'eventId': eventId});
    _checkSession();
    return EventWizardDraft.fromJson(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  Future<EventWizardDraft> createEditDraft(String eventId) async {
    _checkSession();
    final result = await _functions
        .httpsCallable('createEditEventDraftV1')
        .call({'eventId': eventId});
    _checkSession();
    return EventWizardDraft.fromJson(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  Future<void> archiveDraft(String draftId) async {
    _checkSession();
    await _functions.httpsCallable('archiveEventDraftV1').call({
      'draftId': draftId,
    });
  }

  @override
  Future<String> uploadDraftImage({
    required EventWizardDraft draft,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    _checkSession();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('A signed-in organizer is required.');
    if (draft.draftId == null) await saveDraft(draft);
    final reference = _storage.ref(
      'event-drafts/$uid/${draft.draftId}/cover-${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await reference.putData(bytes, SettableMetadata(contentType: contentType));
    return reference.getDownloadURL();
  }

  @override
  Future<EventWizardPublishResult> publish(
    EventWizardDraft draft, {
    int? expectedEventRevision,
    String? changeReason,
    String? changePreviewToken,
    String recurrenceScope = 'this_occurrence',
  }) async {
    _checkSession();
    if (draft.draftId == null) await saveDraft(draft);
    final result = await _functions.httpsCallable('publishEventDraftV1').call({
      'draftId': draft.draftId,
      'expectedDraftRevision': draft.revision,
      'expectedEventRevision':
          expectedEventRevision ?? draft.sourceEventRevision,
      'recurrenceScope': recurrenceScope,
      'changeReason': ?changeReason,
      'changePreviewToken': ?changePreviewToken,
      'idempotencyKey': 'publish-${draft.draftId}-${draft.revision}',
    });
    _checkSession();
    final data = Map<String, dynamic>.from(result.data as Map);
    await clearLocalDraft(draft);
    return EventWizardPublishResult(
      eventId: data['eventId']?.toString() ?? '',
      eventIds: List<String>.from(data['eventIds'] as List? ?? const []),
      status: data['status']?.toString() ?? 'scheduled',
      seriesId: data['seriesId']?.toString(),
    );
  }

  @override
  Future<void> saveTemplate({
    required String name,
    required EventWizardDraft draft,
    bool includeLocation = false,
    bool includeContact = false,
  }) async {
    _checkSession();
    await _functions.httpsCallable('saveEventTemplateV1').call({
      'name': name,
      'organizationId': draft.organizationId,
      'includeLocation': includeLocation,
      'includeContact': includeContact,
      'formData': draft.toFormJson(),
    });
  }
}
