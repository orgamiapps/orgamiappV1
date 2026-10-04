import 'dart:async';

import 'package:attendus/firebase/organization_helper.dart';
import 'package:attendus/screens/Groups/group_profile_screen_v2.dart';
import 'package:attendus/widgets/attendus_design_system.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
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
  @override
  String get uid => 'viewer';
  @override
  bool get isAnonymous => false;
}

class _Auth extends FirebaseAuthPlatform {
  bool signedIn = true;
  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseAuthPlatform setInitialValues({
    InternalUserDetails? currentUser,
    String? languageCode,
  }) => this;
  @override
  UserPlatform? get currentUser => signedIn ? _User() : null;
}

// Real Firestore/Auth wrappers and real helper/screen; only platform I/O is fake.
class _Db extends FirebaseFirestorePlatform {
  final data = <String, Map<String, dynamic>>{};
  final writes = <({String path, Map<String, dynamic> data})>[];
  bool rejectWrite = false;
  final rejectReads = <String>{};
  Completer<void>? writeAck;
  Completer<void>? memberRead;
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
}

class _Document extends DocumentReferencePlatform {
  _Document(super.firestore, super.path);
  _Db get db => firestore as _Db;
  @override
  Future<DocumentSnapshotPlatform> get([
    GetOptions options = const GetOptions(),
  ]) async {
    if (path.endsWith('/Members/viewer')) await db.memberRead?.future;
    if (db.rejectReads.contains(path)) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    }
    return DocumentSnapshotPlatform(
      firestore,
      path,
      db.data[path],
      InternalSnapshotMetadata(hasPendingWrites: false, isFromCache: false),
    );
  }

  @override
  Stream<DocumentSnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    ListenSource listenSource = ListenSource.defaultSource,
  }) => Stream.fromFuture(get());
  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    db.writes.add((path: path, data: Map.of(data)));
    await db.writeAck?.future;
    if (db.rejectWrite) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
    }
    db.data[path] = Map.of(data);
  }
}

class _Collection extends CollectionReferencePlatform {
  _Collection(super.firestore, super.path) {
    parameters.addAll({
      'where': <List<dynamic>>[],
      'orderBy': <List<dynamic>>[],
    });
  }
  @override
  DocumentReferencePlatform doc([String? id]) => firestore.doc('$path/$id');
  @override
  QueryPlatform where(List<List<dynamic>> conditions) => this;
  @override
  QueryPlatform orderBy(Iterable<List<dynamic>> orders) => this;
  @override
  QueryPlatform limit(int limit) => this;
  @override
  Future<QuerySnapshotPlatform> get([
    GetOptions options = const GetOptions(),
  ]) async =>
      QuerySnapshotPlatform([], [], SnapshotMetadataPlatform(false, false));
  @override
  Stream<QuerySnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    required ListenSource listenSource,
  }) => Stream.fromFuture(get());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FirebasePlatform.instance = _Core();
  final db = _Db();
  FirebaseFirestorePlatform.instance = db;
  final auth = _Auth();
  FirebaseAuthPlatform.instance = auth;
  const orgPath = 'Organizations/group';
  const memberPath = '$orgPath/Members/viewer';
  const requestPath = '$orgPath/JoinRequests/viewer';

  setUp(() {
    db.data
      ..clear()
      ..[orgPath] = {
        'name': 'Controlled group',
        'createdBy': 'owner',
        'category': 'Other',
      };
    db.writes.clear();
    db.rejectReads.clear();
    db.rejectWrite = false;
    db.writeAck = null;
    db.memberRead = null;
    auth.signedIn = true;
  });
  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: GroupProfileScreenV2(organizationId: 'group')),
    );
    await tester.pumpAndSettle();
  }

  Finder button(String label) =>
      find.byWidgetPredicate((w) => w is AttendUsButton && w.label == label);
  bool enabled(WidgetTester tester, String label) =>
      tester.widget<AttendUsButton>(button(label)).onPressed != null;

  test('helper propagates write failure', () async {
    db.rejectWrite = true;
    await expectLater(
      OrganizationHelper().requestToJoinOrganization('group'),
      throwsA(isA<FirebaseException>()),
    );
    expect(db.writes.single.path, requestPath);
  });
  test('helper rejects signed-out request without a write', () async {
    auth.signedIn = false;
    await expectLater(
      OrganizationHelper().requestToJoinOrganization('group'),
      throwsA(isA<StateError>()),
    );
    expect(db.writes, isEmpty);
  });
  testWidgets('failed request does not report success or mark pending', (
    tester,
  ) async {
    db.rejectWrite = true;
    await open(tester);
    await tester.tap(button('Join'));
    await tester.pumpAndSettle();
    expect(db.writes, hasLength(1));
    expect(find.text('Join request sent!'), findsNothing);
    expect(find.textContaining('Error:'), findsOneWidget);
    expect(enabled(tester, 'Join'), isTrue);
  });
  testWidgets(
    'acknowledged request writes exact pending payload then disables join',
    (tester) async {
      await open(tester);
      await tester.tap(button('Join'));
      await tester.pumpAndSettle();
      expect(db.writes.single.path, requestPath);
      expect(db.writes.single.data['status'], 'pending');
      expect(db.writes.single.data['userId'], 'viewer');
      expect(find.text('Join request sent!'), findsOneWidget);
      expect(enabled(tester, 'Requested'), isFalse);
      expect(find.text('Request pending'), findsOneWidget);
    },
  );
  testWidgets('declined request is truthful and cannot be reapplied with set', (
    tester,
  ) async {
    db.data[requestPath] = {'status': 'declined'};
    await open(tester);
    expect(find.text('Request declined'), findsOneWidget);
    expect(find.text('Request pending'), findsNothing);
    expect(enabled(tester, 'Declined'), isFalse);
    expect(button('Join'), findsNothing);
    expect(db.writes, isEmpty);
  });
  testWidgets('pending request remains disabled', (tester) async {
    db.data[requestPath] = {'status': 'pending'};
    await open(tester);
    expect(find.text('Request pending'), findsOneWidget);
    expect(enabled(tester, 'Requested'), isFalse);
    expect(db.writes, isEmpty);
  });
  for (final status in ['pending', 'declined', null]) {
    testWidgets('membership $status never grants member controls', (
      tester,
    ) async {
      db.data[memberPath] = {'role': 'Admin', 'status': status};
      await open(tester);
      expect(find.text('Manage Group'), findsNothing);
      expect(find.text('Create Post'), findsNothing);
      expect(button('Join'), findsNothing);
      expect(db.writes, isEmpty);
    });
  }
  for (final role in ['Admin', 'admin', 'Owner', 'owner']) {
    testWidgets(
      'approved $role has matching role and management presentation',
      (tester) async {
        db.data[memberPath] = {'role': role, 'status': 'approved'};
        await open(tester);
        expect(find.text('Manage Group'), findsOneWidget);
        expect(
          find.widgetWithText(FloatingActionButton, 'Create Post'),
          findsNothing,
        );
        expect(
          find.text(role.toLowerCase() == 'owner' ? 'Owner' : 'Admin'),
          findsWidgets,
        );
        expect(button('Join'), findsNothing);
      },
    );
  }
  testWidgets('creator remains owner with no membership document', (
    tester,
  ) async {
    db.data[orgPath]!['createdBy'] = 'viewer';
    await open(tester);
    expect(find.text('Owner'), findsWidgets);
    expect(find.text('Manage Group'), findsOneWidget);
    expect(button('Join'), findsNothing);
  });
  for (final role in ['Member', 'member']) {
    testWidgets(
      'approved $role retains ordinary posting but not admin options',
      (tester) async {
        db.data[memberPath] = {'role': role, 'status': 'approved'};
        await open(tester);
        expect(
          find.widgetWithText(FloatingActionButton, 'Create Post'),
          findsOneWidget,
        );
        expect(find.text('Manage Group'), findsNothing);
        expect(button('Join'), findsNothing);
        await tester.tap(
          find.widgetWithText(FloatingActionButton, 'Create Post'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Share Photo'), findsOneWidget);
        expect(find.text('Create Event'), findsNothing);
        expect(find.text('Post Announcement'), findsNothing);
      },
    );
  }
  for (final role in ['ADMIN', 'OWNER', ' admin ', 1]) {
    testWidgets('unsupported role $role never advertises admin access', (
      tester,
    ) async {
      db.data[memberPath] = {'role': role, 'status': 'approved'};
      await open(tester);
      expect(find.text('Manage Group'), findsNothing);
      expect(
        find.widgetWithText(FloatingActionButton, 'Create Post'),
        findsOneWidget,
      );
      // Inspect the actual active feed CTA too, not only the outer FAB.
      await tester.tap(find.widgetWithText(FilledButton, 'Create Post'));
      await tester.pumpAndSettle();
      expect(find.text('Share Photo'), findsOneWidget);
      expect(find.text('Post Announcement'), findsNothing);
      expect(find.text('Create Poll'), findsNothing);
      expect(db.writes, isEmpty);
    });
  }
  for (final status in [null, 'approved', 'unexpected']) {
    testWidgets('existing request $status is unavailable, not reapplicable', (
      tester,
    ) async {
      db.data[requestPath] = {'status': status};
      await open(tester);
      expect(find.text('Request status unavailable'), findsOneWidget);
      expect(enabled(tester, 'Unavailable'), isFalse);
      expect(button('Join'), findsNothing);
      expect(db.writes, isEmpty);
    });
  }
  testWidgets(
    'request remains disabled before ACK and repeated callback sends once',
    (tester) async {
      db.writeAck = Completer<void>();
      await open(tester);
      final submit = tester.widget<AttendUsButton>(button('Join')).onPressed!;
      submit();
      submit();
      await tester.pump();
      expect(db.writes, hasLength(1));
      expect(enabled(tester, 'Sending...'), isFalse);
      expect(find.text('Join request sent!'), findsNothing);
      db.writeAck!.complete();
      await tester.pumpAndSettle();
      expect(enabled(tester, 'Requested'), isFalse);
      expect(find.text('Join request sent!'), findsOneWidget);
    },
  );
  testWidgets('membership read failure stays unavailable, not joinable', (
    tester,
  ) async {
    db.rejectReads.add(memberPath);
    await open(tester);
    expect(button('Join'), findsNothing);
    expect(find.text('Membership status unavailable'), findsOneWidget);
    expect(find.text('Manage Group'), findsNothing);
    expect(db.writes, isEmpty);
  });
  testWidgets('pop during request ACK has no disposed state mutation', (
    tester,
  ) async {
    db.writeAck = Completer<void>();
    await open(tester);
    await tester.tap(button('Join'));
    await tester.pump();
    expect(db.writes, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    db.writeAck!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
