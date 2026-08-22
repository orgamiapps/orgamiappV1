import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
       _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static const _localDraftPrefix = 'event_wizard_draft_v2_';
  static const _lastDraftKey = 'event_wizard_last_draft_v2';

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
  Future<EventWizardDraft?> restoreLocalDraft([String? draftId]) async {
    final preferences = await SharedPreferences.getInstance();
    final id = draftId ?? preferences.getString(_lastDraftKey);
    if (id == null || id.isEmpty) return null;
    final raw = await _secureStorage.read(key: '$_localDraftPrefix$id');
    if (raw == null) return null;
    try {
      return EventWizardDraft.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveLocalDraft(EventWizardDraft draft) async {
    final preferences = await SharedPreferences.getInstance();
    final id = draft.draftId ?? 'local';
    await _secureStorage.write(
      key: '$_localDraftPrefix$id',
      value: jsonEncode({
        'id': draft.draftId,
        'revision': draft.revision,
        'mode': draft.mode,
        'sourceEventId': draft.sourceEventId,
        'sourceSeriesId': draft.sourceSeriesId,
        'sourceEventRevision': draft.sourceEventRevision,
        'currentStage': draft.currentStage.index,
        'formData': draft.toFormJson(),
      }),
    );
    await preferences.setString(_lastDraftKey, id);
  }

  Future<void> clearLocalDraft(EventWizardDraft draft) async {
    final preferences = await SharedPreferences.getInstance();
    final id = draft.draftId ?? 'local';
    await _secureStorage.delete(key: '$_localDraftPrefix$id');
    if (preferences.getString(_lastDraftKey) == id) {
      await preferences.remove(_lastDraftKey);
    }
  }

  @override
  Future<EventWizardDraft> saveDraft(EventWizardDraft draft) async {
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
    final data = Map<String, dynamic>.from(result.data as Map);
    draft.draftId = data['draftId']?.toString();
    draft.revision = (data['revision'] as num?)?.round() ?? draft.revision;
    await saveLocalDraft(draft);
    return draft;
  }

  @override
  Future<List<EventWizardDraft>> listDrafts() async {
    final result = await _functions.httpsCallable('listEventDraftsV1').call();
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
    final result = await _functions.httpsCallable('listEventTemplatesV1').call({
      'organizationId': organizationId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return [
      ...(data['personal'] as List? ?? const []),
      ...(data['group'] as List? ?? const []),
    ].map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<EventWizardDraft> duplicateEvent(String eventId) async {
    final result = await _functions
        .httpsCallable('duplicateEventToDraftV1')
        .call({'eventId': eventId});
    return EventWizardDraft.fromJson(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  Future<EventWizardDraft> createEditDraft(String eventId) async {
    final result = await _functions
        .httpsCallable('createEditEventDraftV1')
        .call({'eventId': eventId});
    return EventWizardDraft.fromJson(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  Future<void> archiveDraft(String draftId) async {
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
    String recurrenceScope = 'this_occurrence',
  }) async {
    if (draft.draftId == null) await saveDraft(draft);
    final result = await _functions.httpsCallable('publishEventDraftV1').call({
      'draftId': draft.draftId,
      'expectedDraftRevision': draft.revision,
      'expectedEventRevision':
          expectedEventRevision ?? draft.sourceEventRevision,
      'recurrenceScope': recurrenceScope,
      'idempotencyKey': 'publish-${draft.draftId}-${draft.revision}',
    });
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
    await _functions.httpsCallable('saveEventTemplateV1').call({
      'name': name,
      'organizationId': draft.organizationId,
      'includeLocation': includeLocation,
      'includeContact': includeContact,
      'formData': draft.toFormJson(),
    });
  }
}
