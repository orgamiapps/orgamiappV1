import 'dart:async';

import 'package:attendus/firebase/organization_helper.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _Core extends FirebasePlatform {
  final value = FirebaseAppPlatform(
    '[DEFAULT]',
    const FirebaseOptions(
      apiKey: 'offline-only',
      appId: 'offline-only',
      messagingSenderId: '1',
      projectId: 'demo-attendus-admin',
    ),
  );
  @override
  FirebaseAppPlatform app([String name = '[DEFAULT]']) => value;
  @override
  List<FirebaseAppPlatform> get apps => [value];
}

class _User extends Fake
    with MockPlatformInterfaceMixin
    implements UserPlatform {
  _User(this.anonymous, this.id);
  final bool anonymous;
  final String id;
  @override
  String get uid => id;
  @override
  bool get isAnonymous => anonymous;
}

class _Auth extends FirebaseAuthPlatform {
  bool signedIn = true;
  bool anonymous = false;
  String uid = 'admin';
  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseAuthPlatform setInitialValues({
    InternalUserDetails? currentUser,
    String? languageCode,
  }) => this;
  @override
  UserPlatform? get currentUser => signedIn ? _User(anonymous, uid) : null;
}

typedef _Write = ({String path, Map<String, dynamic>? data, bool merge});

// Real Firebase wrappers/helper; the platform transport buffers atomic commits.
// This double does not claim to evaluate Firestore rules.
class _Db extends FirebaseFirestorePlatform {
  final data = <String, Map<String, dynamic>>{};
  final committed = <List<_Write>>[];
  final rejectedReads = <String>{};
  String? rejectedWrite;
  Completer<void>? commitAck;
  bool loseCommitAck = false;
  void Function()? retryAfterFirstReads;
  @override
  FirebaseFirestorePlatform delegateFor({
    required FirebaseApp app,
    required String databaseId,
  }) => this;
  @override
  DocumentReferencePlatform doc(String path) => _Document(this, path);
  @override
  CollectionReferencePlatform collection(String path) =>
      _Collection(this, path);

  Future<void> commit(List<_Write> writes) async {
    await commitAck?.future;
    if (writes.any((write) => write.path == rejectedWrite)) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    }
    for (final write in writes) {
      if (write.data == null) {
        data.remove(write.path);
      } else {
        data[write.path] = {
          if (write.merge) ...?data[write.path],
          ...write.data!,
        };
      }
    }
    if (writes.isNotEmpty) committed.add(List.of(writes));
    if (loseCommitAck && writes.isNotEmpty) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
  }

  @override
  Future<T?> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    var tx = _Tx(this);
    var result = await transactionHandler(tx);
    final retry = retryAfterFirstReads;
    if (retry != null) {
      retryAfterFirstReads = null;
      retry();
      tx = _Tx(this);
      result = await transactionHandler(tx);
    }
    await commit(tx.pending);
    return result;
  }
}

class _Document extends DocumentReferencePlatform {
  _Document(super.firestore, super.path);
  _Db get db => firestore as _Db;
  @override
  Future<DocumentSnapshotPlatform> get([
    GetOptions options = const GetOptions(),
  ]) async {
    if (db.rejectedReads.contains(path)) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    }
    return DocumentSnapshotPlatform(
      firestore,
      path,
      db.data[path] == null ? null : Map.of(db.data[path]!),
      InternalSnapshotMetadata(hasPendingWrites: false, isFromCache: false),
    );
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) =>
      db.commit([(path: path, data: data, merge: options?.merge == true)]);
  @override
  Future<void> delete() => db.commit([(path: path, data: null, merge: false)]);
}

class _Collection extends CollectionReferencePlatform {
  _Collection(super.firestore, super.path);
  @override
  DocumentReferencePlatform doc([String? id]) =>
      firestore.doc('$path/${id ?? 'created-group'}');
}

class _Tx extends TransactionPlatform {
  _Tx(this.db);
  final _Db db;
  final pending = <_Write>[];
  @override
  Future<DocumentSnapshotPlatform> get(String path) {
    expect(pending, isEmpty, reason: 'All reads must precede writes.');
    return db.doc(path).get();
  }

  @override
  TransactionPlatform set(
    String path,
    Map<String, dynamic> data, [
    SetOptions? options,
  ]) {
    pending.add((path: path, data: data, merge: options?.merge == true));
    return this;
  }

  @override
  TransactionPlatform delete(String path) {
    pending.add((path: path, data: null, merge: false));
    return this;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FirebasePlatform.instance = _Core();
  final db = _Db();
  FirebaseFirestorePlatform.instance = db;
  final auth = _Auth();
  FirebaseAuthPlatform.instance = auth;
  const org = 'Organizations/group';
  const member = '$org/Members/applicant';
  const request = '$org/JoinRequests/applicant';
  const actor = '$org/Members/admin';
  final helper = OrganizationHelper();

  setUp(() {
    db.data.clear();
    db.committed.clear();
    db.rejectedReads.clear();
    db.rejectedWrite = null;
    db.commitAck = null;
    db.loseCommitAck = false;
    db.retryAfterFirstReads = null;
    auth.signedIn = true;
    auth.anonymous = false;
    auth.uid = 'admin';
    db.data[org] = {'createdBy': 'admin'};
    db.data[actor] = {
      'organizationId': 'group',
      'userId': 'admin',
      'role': 'Admin',
      'status': 'approved',
    };
    db.data[request] = {'userId': 'applicant', 'status': 'pending'};
  });

  test('rejected request deletion cannot partially grant membership', () async {
    db.rejectedWrite = request;
    expect(await helper.approveJoinRequest('group', 'applicant'), false);
    expect(db.data.containsKey(member), false);
    expect(db.data[request]!['status'], 'pending');
    expect(db.committed, isEmpty);
  });

  test(
    'pending approval commits membership and request deletion together',
    () async {
      expect(await helper.approveJoinRequest('group', 'applicant'), true);
      expect(db.data[member]!['status'], 'approved');
      expect(db.data[member]!['role'], 'Member');
      expect(db.data.containsKey(request), false);
      expect(db.committed, hasLength(1));
      expect(db.committed.single.map((write) => write.path), [member, request]);
    },
  );

  test(
    'replay preserves existing approved role permissions and joinedAt',
    () async {
      db.data.remove(request);
      final approved = {
        'organizationId': 'group',
        'userId': 'applicant',
        'role': 'Owner',
        'permissions': ['ManageMembersRoles'],
        'status': 'approved',
        'joinedAt': 'original',
      };
      db.data[member] = Map.of(approved);
      expect(await helper.approveJoinRequest('group', 'applicant'), true);
      expect(db.data[member], approved);
      expect(db.committed, isEmpty);
    },
  );

  for (final status in [null, 'declined', 'approved', 'unknown', 7]) {
    test(
      'missing or nonpending request $status cannot create membership',
      () async {
        if (status == null) {
          db.data.remove(request);
        } else {
          db.data[request]!['status'] = status;
        }
        expect(await helper.approveJoinRequest('group', 'applicant'), false);
        expect(db.data.containsKey(member), false);
        expect(db.committed, isEmpty);
      },
    );
  }

  test('transaction retry rechecks a declined request', () async {
    db.retryAfterFirstReads = () => db.data[request]!['status'] = 'declined';
    expect(await helper.approveJoinRequest('group', 'applicant'), false);
    expect(db.data.containsKey(member), false);
    expect(db.data[request]!['status'], 'declined');
    expect(db.committed, isEmpty);
  });

  test('legacy approved owner without organizationId is preserved', () async {
    final original = {
      'userId': 'applicant',
      'role': 'Owner',
      'permissions': ['ManageMembersRoles'],
      'status': 'approved',
      'joinedAt': 'original',
      'unknownField': 'preserved',
    };
    db.data[member] = Map.of(original);
    expect(await helper.approveJoinRequest('group', 'applicant'), true);
    expect(db.data[member], original);
    expect(db.data.containsKey(request), false);
    expect(db.committed.single.map((write) => write.path), [request]);
    expect(await helper.approveJoinRequest('group', 'applicant'), true);
    expect(db.data[member], original);
    expect(db.committed, hasLength(1));
  });

  test(
    'present invalid identity or missing required userId is rejected',
    () async {
      for (final identity in [
        {'organizationId': null, 'userId': 'applicant'},
        {'organizationId': 1, 'userId': 'applicant'},
        {'organizationId': 'foreign', 'userId': 'applicant'},
        {'organizationId': 'group'},
        {'organizationId': 'group', 'userId': null},
        {'organizationId': 'group', 'userId': 'foreign'},
      ]) {
        db.data[member] = {...identity, 'role': 'Owner', 'status': 'approved'};
        final original = Map<String, dynamic>.of(db.data[member]!);
        expect(await helper.approveJoinRequest('group', 'applicant'), false);
        expect(db.data[member], original);
        expect(db.data[request]!['status'], 'pending');
        expect(db.committed, isEmpty);
      }
    },
  );

  test(
    'account switch during retry cannot commit prior actor approval',
    () async {
      db.retryAfterFirstReads = () => auth.uid = 'other-admin';
      expect(await helper.approveJoinRequest('group', 'applicant'), false);
      expect(db.data.containsKey(member), false);
      expect(db.data[request]!['status'], 'pending');
      expect(db.committed, isEmpty);
    },
  );

  test('denied fresh read leaves both documents untouched', () async {
    db.rejectedReads.add(request);
    expect(await helper.approveJoinRequest('group', 'applicant'), false);
    expect(db.data.containsKey(member), false);
    expect(db.data[request]!['status'], 'pending');
    expect(db.committed, isEmpty);
  });

  test('approval waits for one atomic commit acknowledgement', () async {
    db.commitAck = Completer<void>();
    var completed = false;
    final approval = helper.approveJoinRequest('group', 'applicant').then((
      value,
    ) {
      completed = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    try {
      expect(completed, false);
      expect(db.data.containsKey(member), false);
      expect(db.data[request]!['status'], 'pending');
    } finally {
      db.commitAck!.complete();
    }
    expect(await approval, true);
    expect(db.committed, hasLength(1));
  });

  test(
    'lost commit acknowledgement keeps a consistent pair and safe replay',
    () async {
      db.loseCommitAck = true;
      expect(await helper.approveJoinRequest('group', 'applicant'), false);
      final granted = Map<String, dynamic>.of(db.data[member]!);
      expect(granted['status'], 'approved');
      expect(db.data.containsKey(request), false);
      db.loseCommitAck = false;
      expect(await helper.approveJoinRequest('group', 'applicant'), true);
      expect(db.data[member], granted);
      expect(db.committed, hasLength(1));
    },
  );

  test(
    'retry preserves concurrently approved owner and only removes pending request',
    () async {
      final promoted = {
        'organizationId': 'group',
        'userId': 'applicant',
        'role': 'Owner',
        'permissions': ['ManageMembersRoles'],
        'status': 'approved',
        'joinedAt': 'concurrent',
      };
      db.retryAfterFirstReads = () => db.data[member] = Map.of(promoted);
      expect(await helper.approveJoinRequest('group', 'applicant'), true);
      expect(db.data[member], promoted);
      expect(db.data.containsKey(request), false);
      expect(db.committed.single.map((write) => write.path), [request]);
    },
  );

  test('retry rejects revoked approver membership', () async {
    db.retryAfterFirstReads = () => db.data[actor]!['status'] = 'declined';
    expect(await helper.approveJoinRequest('group', 'applicant'), false);
    expect(db.data.containsKey(member), false);
    expect(db.data[request]!['status'], 'pending');
    expect(db.committed, isEmpty);
  });

  test(
    'foreign request or membership identity cannot be overwritten',
    () async {
      db.data[request]!['userId'] = 'foreign';
      expect(await helper.approveJoinRequest('group', 'applicant'), false);
      db.data[request]!['userId'] = 'applicant';
      db.data[member] = {
        'organizationId': 'foreign',
        'userId': 'applicant',
        'status': 'pending',
      };
      expect(await helper.approveJoinRequest('group', 'applicant'), false);
      expect(db.data[member]!['organizationId'], 'foreign');
      expect(db.committed, isEmpty);
    },
  );

  test('unapproved or malformed approver cannot use no-write replay', () async {
    db.data.remove(request);
    db.data[member] = {
      'organizationId': 'group',
      'userId': 'applicant',
      'role': 'Owner',
      'status': 'approved',
    };
    for (final fields in [
      {'status': 'pending', 'role': 'Admin'},
      {'status': 'approved', 'role': 'Member'},
      {'status': 'approved', 'role': ' ADMIN '},
    ]) {
      db.data[actor] = fields;
      expect(await helper.approveJoinRequest('group', 'applicant'), false);
    }
    db.data.remove(actor);
    expect(await helper.approveJoinRequest('group', 'applicant'), false);
    expect(db.committed, isEmpty);
  });

  test('missing organization cannot receive approved membership', () async {
    db.data.remove(org);
    expect(await helper.approveJoinRequest('group', 'applicant'), false);
    expect(db.data.containsKey(member), false);
    expect(db.committed, isEmpty);
  });

  test('signed-out and anonymous callers cannot approve', () async {
    auth.signedIn = false;
    expect(await helper.approveJoinRequest('group', 'applicant'), false);
    auth.signedIn = true;
    auth.anonymous = true;
    expect(await helper.approveJoinRequest('group', 'applicant'), false);
    expect(db.committed, isEmpty);
  });

  test(
    'valid pending member retains unrelated fields during approval',
    () async {
      db.data[member] = {
        'organizationId': 'group',
        'userId': 'applicant',
        'role': 'Member',
        'status': 'pending',
        'note': 'preserved',
      };
      expect(await helper.approveJoinRequest('group', 'applicant'), true);
      expect(db.data[member]!['note'], 'preserved');
      expect(db.data[member]!['role'], 'Member');
      expect(db.committed.single, hasLength(2));
    },
  );

  test(
    'creation retry rejects concurrently reserved name without partial records',
    () async {
      db.retryAfterFirstReads = () => db.data['OrganizationNames/new group'] = {
        'organizationId': 'concurrent',
      };
      expect(await helper.createOrganization(name: 'New group'), isNull);
      expect(
        db.data['OrganizationNames/new group']!['organizationId'],
        'concurrent',
      );
      expect(db.data.containsKey('Organizations/created-group'), false);
      expect(
        db.data.containsKey('Organizations/created-group/Members/admin'),
        false,
      );
      expect(db.committed, isEmpty);
    },
  );

  test(
    'creator membership rejection rolls back organization and name',
    () async {
      db.rejectedWrite = 'Organizations/created-group/Members/admin';
      expect(await helper.createOrganization(name: 'New group'), isNull);
      expect(db.data.containsKey('Organizations/created-group'), false);
      expect(db.data.containsKey('OrganizationNames/new group'), false);
      expect(db.committed, isEmpty);
    },
  );

  test('organization name and creator membership commit together', () async {
    expect(await helper.createOrganization(name: 'New group'), 'created-group');
    expect(db.data['Organizations/created-group']!['createdBy'], 'admin');
    expect(
      db.data['OrganizationNames/new group']!['organizationId'],
      'created-group',
    );
    expect(
      db.data['Organizations/created-group/Members/admin']!['role'],
      'Admin',
    );
    expect(db.committed, hasLength(1));
    expect(db.committed.single, hasLength(3));
  });

  test('reserved name prevents organization or member creation', () async {
    db.data['OrganizationNames/new group'] = {'organizationId': 'another'};
    expect(await helper.createOrganization(name: 'New group'), isNull);
    expect(db.data['OrganizationNames/new group'], {
      'organizationId': 'another',
    });
    expect(db.data.containsKey('Organizations/created-group'), false);
    expect(db.committed, isEmpty);
  });

  test(
    'name write rejection cannot create organization or membership',
    () async {
      db.rejectedWrite = 'OrganizationNames/new group';
      expect(await helper.createOrganization(name: 'New group'), isNull);
      expect(db.data.containsKey('Organizations/created-group'), false);
      expect(
        db.data.containsKey('Organizations/created-group/Members/admin'),
        false,
      );
      expect(db.committed, isEmpty);
    },
  );
}
