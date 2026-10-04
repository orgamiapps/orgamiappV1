import 'package:attendus/models/notification_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

typedef LoadNotificationPreferences =
    Future<Map<String, dynamic>?> Function(String uid);
typedef SaveNotificationPreferences =
    Future<Map<String, dynamic>?> Function(
      String uid,
      Map<String, dynamic> patch,
    );

/// One document is authoritative, matching notification delivery workers.
/// Existing canonical settings win; only an absent document uses legacy data.
class NotificationPreferencesSnapshot {
  NotificationPreferencesSnapshot({
    required this.canonicalRef,
    required this.canonicalData,
    required Map<String, dynamic> selected,
  }) : effectiveData = Map.unmodifiable({
         ...UserNotificationSettings().toMap(),
         ...selected,
         'messagesAll': UserNotificationSettings.fromMap(selected).messagesAll,
       });

  final DocumentReference<Map<String, dynamic>> canonicalRef;
  final Map<String, dynamic>? canonicalData;
  final Map<String, dynamic> effectiveData;
  UserNotificationSettings get settings =>
      UserNotificationSettings.fromMap(effectiveData);

  Map<String, dynamic> patchForWrite(Map<String, dynamic> dirty) {
    NotificationPreferencesStore.validatePatch(dirty);
    if (dirty.isEmpty) return {};
    // Read in the writing transaction: creation preserves fresh legacy opt-outs
    // while an existing document receives only explicitly changed controls.
    final patch = canonicalData == null
        ? {...effectiveData, ...dirty}
        : {...dirty};
    if (dirty.containsKey('messagesAll')) {
      patch['messageNotifications'] = dirty['messagesAll'];
    }
    return patch;
  }
}

class NotificationPreferencesStore {
  static void validatePatch(Map<String, dynamic> patch) {
    final defaults = UserNotificationSettings().toMap();
    for (final entry in patch.entries) {
      if (!defaults.containsKey(entry.key) ||
          entry.value.runtimeType != defaults[entry.key].runtimeType) {
        throw ArgumentError('Only typed notification controls can be changed.');
      }
    }
  }

  static Future<NotificationPreferencesSnapshot> read(
    FirebaseFirestore db,
    String uid, {
    Transaction? transaction,
  }) async {
    final canonical = db.doc('users/$uid/settings/notifications');
    Future<DocumentSnapshot<Map<String, dynamic>>> get(
      DocumentReference<Map<String, dynamic>> ref,
    ) => transaction == null ? ref.get() : transaction.get(ref);
    final current = await get(canonical);
    Map<String, dynamic> selected;
    if (current.exists) {
      selected = current.data()!;
    } else {
      final old = await get(db.doc('users/$uid/notificationSettings/settings'));
      if (old.exists) {
        selected = old.data()!;
      } else {
        final customer = await get(db.doc('Customers/$uid'));
        final legacy = customer.data()?['notificationPreferences'];
        selected = legacy is Map ? Map<String, dynamic>.from(legacy) : {};
        // Customer's old editor named these controls differently.
        if (selected.containsKey('messages')) {
          selected['messagesAll'] = selected['messages'];
        }
        if (selected.containsKey('announcements')) {
          selected['generalNotifications'] = selected['announcements'];
        }
      }
    }
    final result = NotificationPreferencesSnapshot(
      canonicalRef: canonical,
      canonicalData: current.data(),
      selected: selected,
    );
    // Malformed data/load failures must not display an opt-in default.
    result.settings;
    return result;
  }

  static Future<Map<String, dynamic>> save(
    FirebaseFirestore db,
    String uid,
    Map<String, dynamic> dirty, {
    required String? Function() currentUid,
  }) {
    validatePatch(dirty);
    return db.runTransaction((transaction) async {
      if (currentUid() != uid) {
        throw StateError('Account changed. Reload preferences.');
      }
      final snapshot = await read(db, uid, transaction: transaction);
      if (currentUid() != uid) {
        throw StateError('Account changed. Reload preferences.');
      }
      final patch = snapshot.patchForWrite(dirty);
      if (patch.isNotEmpty) {
        transaction.set(snapshot.canonicalRef, patch, SetOptions(merge: true));
      }
      return {
        ...snapshot.effectiveData,
        ...dirty,
        if (dirty.containsKey('messagesAll'))
          'messageNotifications': dirty['messagesAll'],
      };
    });
  }
}

/// Prevents a delayed load or save for a previous account from changing defaults.
class NotificationPreferencesService {
  NotificationPreferencesService({
    required this.currentUid,
    required this.load,
    required this.save,
  });
  final String? Function() currentUid;
  final LoadNotificationPreferences load;
  final SaveNotificationPreferences save;
  String? _owner;
  UserNotificationSettings? _cached;
  Future<void> _writes = Future<void>.value();
  int _loadRevision = 0;
  UserNotificationSettings? get cached =>
      _owner == currentUid() ? _cached : null;

  Future<UserNotificationSettings> read() async {
    final revision = ++_loadRevision;
    final uid = currentUid();
    if (uid == null) {
      throw StateError('Sign in to load notification preferences.');
    }
    final data = await load(uid);
    if (currentUid() != uid || revision != _loadRevision) {
      throw StateError('Account changed. Reload preferences.');
    }
    _owner = uid;
    return _cached = data == null
        ? UserNotificationSettings()
        : UserNotificationSettings.fromMap(data);
  }

  Future<void> write(
    UserNotificationSettings settings, {
    UserNotificationSettings? baseline,
  }) {
    final uid = currentUid();
    if (uid == null) {
      return Future.error(
        StateError('Sign in to save notification preferences.'),
      );
    }
    final previous = baseline ?? cached;
    if (previous == null || _owner != uid || cached == null) {
      return Future.error(StateError('Load preferences before saving.'));
    }
    final before = previous.toMap();
    final dirty = <String, dynamic>{
      for (final entry in settings.toMap().entries)
        if (entry.value != before[entry.key]) entry.key: entry.value,
    };
    if (dirty.isEmpty) return Future.value();
    final next = _writes.then((_) async {
      if (currentUid() != uid) {
        throw StateError('Account changed. Reload preferences.');
      }
      final saved = await save(uid, dirty);
      if (currentUid() != uid) {
        throw StateError('Account changed. Reload preferences.');
      }
      _owner = uid;
      _loadRevision++;
      _cached = UserNotificationSettings.fromMap(
        saved ?? {...?_cached?.toMap(), ...dirty},
      );
    });
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}
