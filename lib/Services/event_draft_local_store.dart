import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:attendus/models/event_wizard_model.dart';

/// Private drafts are scoped to the account that started the operation.
/// Unscoped legacy drafts are retained on disk but never assigned to a new user.
class EventDraftLocalStore {
  EventDraftLocalStore({
    required this.currentUid,
    FlutterSecureStorage? storage,
    Future<SharedPreferences> Function()? preferences,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _preferences = preferences ?? SharedPreferences.getInstance;
  final String? Function() currentUid;
  final FlutterSecureStorage _storage;
  final Future<SharedPreferences> Function() _preferences;
  String _key(String uid, String id) => 'event_wizard_draft_v3_${uid}_$id';
  String _last(String uid) => 'event_wizard_last_draft_v3_$uid';
  void _check(String uid) {
    if (currentUid() != uid) {
      throw StateError('Account changed. Reopen the event editor.');
    }
  }

  Future<EventWizardDraft?> read([String? draftId]) async {
    final uid = currentUid();
    if (uid == null) return null;
    final preferences = await _preferences();
    _check(uid);
    final id = draftId ?? preferences.getString(_last(uid));
    if (id == null || id.isEmpty) return null;
    final raw = await _storage.read(key: _key(uid, id));
    _check(uid);
    if (raw == null) return null;
    try {
      return EventWizardDraft.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> write(EventWizardDraft draft) async {
    final uid = currentUid();
    if (uid == null) throw StateError('Sign in to save an event draft.');
    final id = draft.draftId ?? 'local';
    final raw = jsonEncode({
      'id': draft.draftId,
      'revision': draft.revision,
      'mode': draft.mode,
      'sourceEventId': draft.sourceEventId,
      'sourceSeriesId': draft.sourceSeriesId,
      'sourceEventRevision': draft.sourceEventRevision,
      'currentStage': draft.currentStage.index,
      'formData': draft.toFormJson(),
    });
    final preferences = await _preferences();
    _check(uid);
    await _storage.write(key: _key(uid, id), value: raw);
    _check(uid);
    await preferences.setString(_last(uid), id);
    _check(uid);
  }

  Future<void> clear(EventWizardDraft draft) async {
    final uid = currentUid();
    if (uid == null) return;
    final id = draft.draftId ?? 'local';
    final preferences = await _preferences();
    _check(uid);
    await _storage.delete(key: _key(uid, id));
    _check(uid);
    if (preferences.getString(_last(uid)) == id) {
      await preferences.remove(_last(uid));
    }
  }
}
