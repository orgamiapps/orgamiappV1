import 'package:attendus/Services/notification_preferences_service.dart';
import 'package:attendus/models/notification_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

// The Firebase transport is replaced; actual store and model code run unchanged.
// ignore: subtype_of_sealed_class
class _Snapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.value);
  final Map<String, dynamic>? value;
  @override
  bool get exists => value != null;
  @override
  Map<String, dynamic>? data() => value == null ? null : {...value!};
}

// ignore: subtype_of_sealed_class
class _Reference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _Reference(this.db, this.path);
  final _Firestore db;
  @override
  final String path;
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    if (db.readError != null) throw db.readError!;
    db.reads.add(path);
    return _Snapshot(db.documents[path]);
  }
}

class _Transaction extends Fake implements Transaction {
  _Transaction(this.db);
  final _Firestore db;
  final pending = <String, Map<String, dynamic>>{};
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> ref,
  ) async {
    expect(pending, isEmpty, reason: 'All reads must precede writes');
    return await (ref as _Reference).get() as DocumentSnapshot<T>;
  }

  @override
  Transaction set<T>(DocumentReference<T> ref, T data, [SetOptions? options]) {
    expect(options?.merge, true, reason: 'Unrelated metadata must survive');
    pending[ref.path] = Map<String, dynamic>.from(data as Map);
    return this;
  }

  void commit() {
    for (final entry in pending.entries) {
      db.writes.add({...entry.value});
      db.documents[entry.key] = {...?db.documents[entry.key], ...entry.value};
    }
  }
}

class _Firestore extends Fake implements FirebaseFirestore {
  final documents = <String, Map<String, dynamic>>{};
  final reads = <String>[];
  final writes = <Map<String, dynamic>>[];
  Object? readError;
  void Function()? conflictBeforeCommit;
  @override
  DocumentReference<Map<String, dynamic>> doc(String path) =>
      _Reference(this, path);
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> action, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    var tx = _Transaction(this);
    var result = await action(tx);
    final conflict = conflictBeforeCommit;
    if (conflict != null) {
      conflictBeforeCommit = null;
      conflict(); // Firestore retries when an absent canonical becomes present.
      tx = _Transaction(this);
      result = await action(tx);
    }
    tx.commit();
    return result;
  }
}

const canonicalPath = 'users/owner/settings/notifications';
const oldPath = 'users/owner/notificationSettings/settings';
const customerPath = 'Customers/owner';

void main() {
  test(
    'legacy messageNotifications opt-out is represented by the displayed Messages control',
    () {
      expect(
        UserNotificationSettings.fromMap({
          'messageNotifications': false,
        }).messagesAll,
        false,
      );
      expect(
        UserNotificationSettings.fromMap({
          'messagesAll': true,
          'messageNotifications': false,
        }).messagesAll,
        false,
      );
    },
  );
  test(
    'a single channel edit preserves another session change and unknown metadata',
    () async {
      var canonical = <String, dynamic>{
        'messagesAll': true,
        'eventReminders': true,
        'futurePreference': false,
      };
      final service = NotificationPreferencesService(
        currentUid: () => 'owner',
        load: (_) async => Map<String, dynamic>.from(canonical),
        save: (_, data) async {
          canonical.addAll(data);
          return null;
        },
      );
      final loaded = await service.read();
      canonical['messagesAll'] = false; // Another session changed this channel.
      await service.write(loaded.copyWith(eventReminders: false));
      expect(canonical['messagesAll'], false);
      expect(canonical['futurePreference'], false);
    },
  );

  test('the save boundary receives only the changed control', () async {
    Map<String, dynamic>? saved;
    final service = NotificationPreferencesService(
      currentUid: () => 'owner',
      load: (_) async => {'messagesAll': false, 'generalNotifications': false},
      save: (_, data) async {
        saved = data;
        return null;
      },
    );
    final loaded = await service.read();
    await service.write(loaded.copyWith(eventReminders: false));
    expect(saved, {'eventReminders': false});
  });

  test(
    'store canonical doc is authoritative, even sparse; old then Customer used only when absent',
    () async {
      final db = _Firestore();
      db.documents[customerPath] = {
        'notificationPreferences': {
          'messages': false,
          'announcements': false,
          'eventReminders': false,
        },
      };
      var loaded = await NotificationPreferencesStore.read(db, 'owner');
      expect(loaded.settings.messagesAll, false);
      expect(loaded.settings.generalNotifications, false);
      db.documents[oldPath] = {
        'messagesAll': true,
        'generalNotifications': false,
      };
      loaded = await NotificationPreferencesStore.read(db, 'owner');
      expect(loaded.settings.messagesAll, true);
      expect(loaded.settings.eventReminders, true);
      db.documents[canonicalPath] = {'eventReminders': false};
      db.reads.clear();
      loaded = await NotificationPreferencesStore.read(db, 'owner');
      expect(loaded.settings.messagesAll, true);
      expect(loaded.settings.generalNotifications, true);
      expect(db.reads, [canonicalPath]);
      expect(db.writes, isEmpty);
    },
  );

  test(
    'absent canonical single toggle creates all fresh effective legacy preferences',
    () async {
      final db = _Firestore();
      db.documents[oldPath] = {
        'messagesAll': false,
        'eventReminders': false,
        'generalNotifications': false,
        'futurePreference': 'retained',
      };
      final saved = await NotificationPreferencesStore.save(db, 'owner', {
        'soundEnabled': false,
      }, currentUid: () => 'owner');
      expect(saved['messagesAll'], false);
      expect(db.documents[canonicalPath]!['eventReminders'], false);
      expect(db.documents[canonicalPath]!['generalNotifications'], false);
      expect(db.documents[canonicalPath]!['futurePreference'], 'retained');
      expect(db.documents[canonicalPath]!['soundEnabled'], false);
    },
  );

  test(
    'concurrent canonical creation is reread on transaction retry and receives only dirty key',
    () async {
      final db = _Firestore();
      db.documents[oldPath] = {'messagesAll': true, 'eventReminders': true};
      db.conflictBeforeCommit = () => db.documents[canonicalPath] = {
        'messagesAll': false,
        'eventReminders': false,
        'anotherSession': 'kept',
      };
      final saved = await NotificationPreferencesStore.save(db, 'owner', {
        'soundEnabled': false,
      }, currentUid: () => 'owner');
      expect(db.writes, [
        {'soundEnabled': false},
      ]);
      expect(saved['messagesAll'], false);
      expect(db.documents[canonicalPath]!['anotherSession'], 'kept');
      expect(db.documents[canonicalPath]!['eventReminders'], false);
    },
  );

  test(
    'message alias opt-out survives unrelated edit; explicit Messages opt-in updates both keys',
    () async {
      final db = _Firestore();
      db.documents[canonicalPath] = {
        'messageNotifications': false,
        'futurePreference': false,
      };
      var loaded = await NotificationPreferencesStore.read(db, 'owner');
      expect(loaded.effectiveData['messagesAll'], false);
      await NotificationPreferencesStore.save(db, 'owner', {
        'eventReminders': false,
      }, currentUid: () => 'owner');
      expect(db.writes.single, {'eventReminders': false});
      final saved = await NotificationPreferencesStore.save(db, 'owner', {
        'messagesAll': true,
      }, currentUid: () => 'owner');
      expect(db.writes.last, {
        'messagesAll': true,
        'messageNotifications': true,
      });
      expect(UserNotificationSettings.fromMap(saved).messagesAll, true);
      expect(db.documents[canonicalPath]!['futurePreference'], false);
      loaded = await NotificationPreferencesStore.read(db, 'owner');
      expect(loaded.settings.messagesAll, true);
    },
  );

  test(
    'load failure cannot provide default opt-in settings or permit save',
    () async {
      final db = _Firestore()..readError = StateError('offline');
      final service = NotificationPreferencesService(
        currentUid: () => 'owner',
        load: (uid) async =>
            (await NotificationPreferencesStore.read(db, uid)).effectiveData,
        save: (uid, dirty) => NotificationPreferencesStore.save(
          db,
          uid,
          dirty,
          currentUid: () => 'owner',
        ),
      );
      await expectLater(service.read(), throwsStateError);
      expect(service.cached, isNull);
      await expectLater(
        service.write(
          UserNotificationSettings(messagesAll: false),
          baseline: UserNotificationSettings(),
        ),
        throwsStateError,
      );
      expect(db.writes, isEmpty);
    },
  );

  test(
    'empty dirty patch does not migrate/create a canonical document',
    () async {
      final db = _Firestore();
      db.documents[oldPath] = {'messagesAll': false};
      await NotificationPreferencesStore.save(
        db,
        'owner',
        {},
        currentUid: () => 'owner',
      );
      expect(db.documents.containsKey(canonicalPath), false);
      expect(db.writes, isEmpty);
    },
  );

  test(
    'queued UI baselines preserve later intent after first save fails',
    () async {
      final first = Completer<Map<String, dynamic>?>();
      final seen = <Map<String, dynamic>>[];
      final service = NotificationPreferencesService(
        currentUid: () => 'owner',
        load: (_) async => {},
        save: (_, patch) {
          seen.add(patch);
          return seen.length == 1
              ? first.future
              : Future.value({'eventReminders': true, ...patch});
        },
      );
      final initial = await service.read();
      final firstUi = initial.copyWith(eventReminders: false);
      final a = service.write(firstUi, baseline: initial);
      final failure = expectLater(a, throwsStateError);
      final b = service.write(
        firstUi.copyWith(soundEnabled: false),
        baseline: firstUi,
      );
      await Future<void>.delayed(Duration.zero);
      first.completeError(StateError('unknown acknowledgement'));
      await failure;
      await b;
      expect(seen, [
        {'eventReminders': false},
        {'soundEnabled': false},
      ]);
      expect(service.cached!.eventReminders, true);
      expect(service.cached!.soundEnabled, false);
    },
  );

  test(
    'explicit old-screen baseline cannot save to a switched account',
    () async {
      var uid = 'owner';
      var writes = 0;
      final service = NotificationPreferencesService(
        currentUid: () => uid,
        load: (_) async => {},
        save: (_, _) async {
          writes++;
          return {};
        },
      );
      final initial = await service.read();
      uid = 'other';
      await expectLater(
        service.write(initial.copyWith(soundEnabled: false), baseline: initial),
        throwsStateError,
      );
      expect(writes, 0);
    },
  );
}
