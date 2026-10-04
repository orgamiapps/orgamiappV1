import 'dart:async';

import 'package:attendus/Services/auth_service.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/auth_fakes.dart';

class _ProfileUser extends TestAuthUser {
  _ProfileUser() : super('owner');
  @override
  String get photoURL => 'https://example.test/avatar.png';
  @override
  Future<void> reload() async {}
}

// Only the Firebase transport is fake; tests invoke actual AuthService paths.
// ignore: subtype_of_sealed_class
class _Snapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.fields);
  final Map<String, dynamic>? fields;
  @override
  bool get exists => fields != null;
  @override
  String get id => 'owner';
  @override
  Map<String, dynamic>? data() => fields == null ? null : {...fields!};
}

// ignore: subtype_of_sealed_class
class _Ref extends Fake implements DocumentReference<Map<String, dynamic>> {
  _Ref(this.db);
  final _Db db;
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    if (db.failRead) throw StateError('Read failed');
    return _Snapshot(db.fields);
  }

  @override
  Future<void> update(Map<Object, Object?> data) =>
      db.apply(data.cast<String, dynamic>());
}

// ignore: subtype_of_sealed_class
class _Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.db);
  final _Db db;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? id]) {
    expect(id, 'owner');
    return _Ref(db);
  }
}

class _Tx extends Fake implements Transaction {
  _Tx(this.db);
  final _Db db;
  Map<String, dynamic>? pending;
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> ref,
  ) async => await (ref as _Ref).get() as DocumentSnapshot<T>;
  @override
  Transaction update(DocumentReference ref, Map<Object, Object?> data) {
    pending = data.cast<String, dynamic>();
    return this;
  }
}

class _Db extends Fake implements FirebaseFirestore {
  Map<String, dynamic>? fields;
  final writes = <Map<String, dynamic>>[];
  Completer<void>? ack;
  bool reject = false;
  bool failRead = false;
  void Function()? onCommit;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    expect(path, CustomerModel.firebaseKey);
    return _Collection(this);
  }

  Future<void> apply(Map<String, dynamic> patch) async {
    if (ack != null) await ack!.future;
    if (reject) throw StateError('Write failed');
    fields = {...?fields, ...patch};
    writes.add({...patch});
    onCommit?.call();
  }

  @override
  Future<T> runTransaction<T>(
    Future<T> Function(Transaction) handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    final tx = _Tx(this);
    final result = await handler(tx);
    if (tx.pending != null) await apply(tx.pending!);
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Db db;
  late TestFirebaseAuth auth;
  late AuthService service;
  setUp(() {
    db = _Db()
      ..fields = {
        'uid': 'owner',
        'name': 'Al',
        'email': 'owner@example.test',
        'bio': 'Saved bio',
        'favorites': ['current'],
      };
    auth = TestFirebaseAuth()..user = TestAuthUser('owner');
    service = AuthService.forTesting(
      auth: auth,
      firestore: db,
      storage: const FlutterSecureStorage(),
      loadCustomer: (_) async =>
          CustomerModel.fromFirestore(_Snapshot(db.fields)),
    );
    CustomerController.logeInCustomer = CustomerModel.fromFirestore(
      _Snapshot(db.fields),
    );
  });
  tearDown(() async {
    service.dispose();
    CustomerController.logeInCustomer = null;
    await auth.changes.close();
  });

  test(
    'Auth enrichment preserves the current saved name even when Auth name is longer',
    () async {
      await service.updateCurrentUserProfileFromAuth();
      expect(db.fields!['name'], 'Al');
      expect(CustomerController.logeInCustomer!.name, 'Al');
      expect(db.writes, isEmpty);
    },
  );

  test(
    'pending enrichment does not mutate the shared profile before acknowledgement',
    () async {
      db.fields!['name'] = '';
      CustomerController.logeInCustomer = CustomerModel.fromFirestore(
        _Snapshot(db.fields),
      );
      final original = CustomerController.logeInCustomer!;
      db.ack = Completer<void>();
      final pending = service.updateCurrentUserProfileFromAuth();
      await Future<void>.delayed(Duration.zero);
      try {
        expect(original.name, '');
        expect(CustomerController.logeInCustomer, same(original));
      } finally {
        db.ack!.complete();
        await pending;
      }
    },
  );

  test('fresh saved profile wins over stale cached missing fields', () async {
    CustomerController.logeInCustomer!.name = '';
    db.fields!['name'] = 'Saved in another session';
    db.fields!['profilePictureUrl'] = 'https://example.test/saved.png';
    auth.user = _ProfileUser();
    expect(await service.updateCurrentUserProfileFromAuth(), true);
    expect(db.writes, isEmpty);
    expect(CustomerController.logeInCustomer!.name, 'Saved in another session');
    expect(
      CustomerController.logeInCustomer!.profilePictureUrl,
      'https://example.test/saved.png',
    );
  });

  test(
    'absent fields are filled and cache refresh includes current independent data',
    () async {
      db.fields!['name'] = '';
      auth.user = _ProfileUser();
      db.onCommit = () => db.fields!['bio'] = 'Concurrent saved biography';
      expect(await service.updateCurrentUserProfileFromAuth(), true);
      expect(db.writes.single, {
        'name': 'Name owner',
        'profilePictureUrl': 'https://example.test/avatar.png',
      });
      expect(
        CustomerController.logeInCustomer!.bio,
        'Concurrent saved biography',
      );
      expect(db.fields!['favorites'], ['current']);
    },
  );

  test(
    'rejected enrichment leaves the original shared model unchanged',
    () async {
      db.fields!['name'] = '';
      db.reject = true;
      CustomerController.logeInCustomer = CustomerModel.fromFirestore(
        _Snapshot(db.fields),
      );
      final original = CustomerController.logeInCustomer;
      expect(await service.updateCurrentUserProfileFromAuth(), false);
      expect(CustomerController.logeInCustomer, same(original));
      expect(original!.name, '');
      expect(db.writes, isEmpty);
    },
  );

  test(
    'account switch after ACK cannot publish the previous account profile',
    () async {
      db.fields!['name'] = '';
      final other = CustomerModel(
        uid: 'other',
        name: 'Other',
        email: 'other@example.test',
        createdAt: DateTime.now(),
      );
      db.onCommit = () {
        auth.changeUser(TestAuthUser('other'));
        CustomerController.logeInCustomer = other;
      };
      expect(await service.updateCurrentUserProfileFromAuth(), false);
      expect(CustomerController.logeInCustomer, same(other));
    },
  );

  test(
    'aggressive refresh does not report a rejected write as success',
    () async {
      db.fields!['name'] = '';
      db.reject = true;
      auth.user = _ProfileUser();
      expect(await service.aggressiveProfileUpdate(), false);
      expect(db.writes, isEmpty);
    },
  );

  testWidgets(
    'unknown ACK timeout cannot mutate cache when the late write completes',
    (tester) async {
      db.fields!['name'] = '';
      CustomerController.logeInCustomer = CustomerModel.fromFirestore(
        _Snapshot(db.fields),
      );
      final original = CustomerController.logeInCustomer;
      db.ack = Completer<void>();
      final pending = service.updateCurrentUserProfileFromAuth();
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      expect(await pending, false);
      expect(CustomerController.logeInCustomer, same(original));
      db.ack!.complete();
      await tester.pump();
      expect(CustomerController.logeInCustomer, same(original));
      expect(original!.name, '');
    },
  );
}
