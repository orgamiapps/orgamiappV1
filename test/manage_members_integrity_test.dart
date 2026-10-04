import 'package:attendus/models/customer_model.dart';
import 'package:attendus/screens/Groups/manage_members_screen.dart';
import 'package:attendus/widgets/attendus_design_system.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _User extends Fake implements User {
  @override
  String get uid => 'viewer';
}

class _Auth extends Fake implements FirebaseAuth {
  @override
  User? get currentUser => _User();
}

// SDK boundary doubles: the actual screen builds, filters and routes menu actions.
class _Db extends Fake implements FirebaseFirestore {
  final rows = <String, Map<String, dynamic>>{};
  final writes = <Map<String, dynamic>>[];
  bool owner = false;
  String viewerRole = 'member';
  bool rejectWrites = false;
  bool rejectMembers = false;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);
}

// ignore: subtype_of_sealed_class
class _Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.db, this.path);
  final _Db db;
  @override
  final String path;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? id]) =>
      _Ref(db, '$path/$id');
  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) => this;
  @override
  Query<Map<String, dynamic>> limit(int limit) => this;
  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => _QuerySnapshot([]);
  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) async* {
    if (db.rejectMembers) throw StateError('Injected member read rejection');
    yield _QuerySnapshot([
      for (final entry in db.rows.entries)
        _Row(_Ref(db, '$path/${entry.key}'), entry.value),
    ]);
  }
}

// ignore: subtype_of_sealed_class
class _Ref extends Fake implements DocumentReference<Map<String, dynamic>> {
  _Ref(this.db, this.path);
  final _Db db;
  @override
  final String path;
  @override
  String get id => path.split('/').last;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(db, '${this.path}/$path');
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async => _Row(
    this,
    path == 'Organizations/group'
        ? {'createdBy': db.owner ? 'viewer' : 'other-owner'}
        : {'role': db.viewerRole, 'status': 'approved'},
  );
  @override
  Future<void> update(Map<Object, Object?> data) async {
    db.writes.add({'path': path, ...data.cast<String, dynamic>()});
    if (db.rejectWrites) throw StateError('Injected permission denial');
  }
}

// ignore: subtype_of_sealed_class
class _Row extends Fake implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _Row(this.reference, this.fields);
  @override
  final DocumentReference<Map<String, dynamic>> reference;
  final Map<String, dynamic> fields;
  @override
  String get id => reference.id;
  @override
  Map<String, dynamic> data() => Map.of(fields);
}

// ignore: subtype_of_sealed_class
class _QuerySnapshot extends Fake
    implements QuerySnapshot<Map<String, dynamic>> {
  _QuerySnapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
}

Future<void> _open(
  WidgetTester tester,
  _Db db, {
  bool rejectProfiles = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: ManageMembersScreen(
        organizationId: 'group',
        firestore: db,
        auth: _Auth(),
        loadProfiles: (ids) async {
          if (rejectProfiles) {
            throw StateError('Injected profile read rejection');
          }
          return ids
              .map(
                (id) => CustomerModel.fromPublicProfile({
                  'uid': id,
                  'name': id,
                  'username': 'user_$id',
                }),
              )
              .toList();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _row(String name) => find.byWidgetPredicate(
  (widget) => widget is AttendUsUserRow && widget.name == name,
);
Finder _menu(String name) => find.descendant(
  of: _row(name),
  matching: find.byType(PopupMenuButton<String>),
);
List<String?> _actionValues(WidgetTester tester, String name) {
  final menu = tester.widget<PopupMenuButton<String>>(_menu(name));
  return menu
      .itemBuilder(tester.element(_menu(name)))
      .whereType<PopupMenuItem<String>>()
      .map((item) => item.value)
      .toList();
}

Future<void> _filter(WidgetTester tester, String name) async {
  await tester.tap(find.widgetWithText(ChoiceChip, name));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Members includes legacy Member and canonical member, not pending',
    (tester) async {
      final db = _Db()
        ..rows.addAll({
          'Legacy': {'role': 'Member', 'status': 'approved'},
          'Canonical': {'role': 'member', 'status': 'approved'},
          'Pending': {'role': 'Member', 'status': 'pending'},
          'Administrator': {'role': 'Admin', 'status': 'approved'},
        });
      await _open(tester, db);
      await _filter(tester, 'Members');
      expect(_row('Legacy'), findsOneWidget);
      expect(_row('Canonical'), findsOneWidget);
      expect(_row('Pending'), findsNothing);
      expect(_row('Administrator'), findsNothing);
      await tester.enterText(find.byType(TextField), 'user_legacy');
      await tester.pumpAndSettle();
      expect(_row('Legacy'), findsOneWidget);
      expect(_row('Canonical'), findsNothing);
      expect(db.writes, isEmpty);
    },
  );

  testWidgets('Admins includes both supported cases of admin and owner', (
    tester,
  ) async {
    final db = _Db();
    for (final role in ['Admin', 'admin', 'Owner', 'owner', 'member']) {
      db.rows[role] = {'role': role, 'status': 'approved'};
    }
    await _open(tester, db);
    await _filter(tester, 'Admins');
    for (final role in ['Admin', 'admin', 'Owner', 'owner']) {
      expect(_row(role), findsOneWidget);
    }
    expect(_row('member'), findsNothing);
  });

  testWidgets('ordinary admin cannot manage legacy admin or owner as members', (
    tester,
  ) async {
    final db = _Db()
      ..viewerRole = 'admin'
      ..rows.addAll({
        'Peer': {'role': 'Admin', 'status': 'approved'},
        'Founder': {'role': 'Owner', 'status': 'approved'},
        'Member': {'role': 'Member', 'status': 'approved'},
      });
    await _open(tester, db);
    expect(_menu('Peer'), findsNothing);
    expect(_menu('Founder'), findsNothing);
    expect(_menu('Member'), findsOneWidget);
    expect(_actionValues(tester, 'Member'), ['remove']);
    expect(db.writes, isEmpty);
  });

  testWidgets(
    'owner demotes legacy admin with canonical payload; rejected ACK has no success',
    (tester) async {
      final db = _Db()
        ..owner = true
        ..rejectWrites = true
        ..rows['Legacy'] = {'role': 'Admin', 'status': 'approved'};
      await _open(tester, db);
      expect(_actionValues(tester, 'Legacy'), ['demote', 'remove']);
      tester.widget<PopupMenuButton<String>>(_menu('Legacy')).onSelected!(
        'demote',
      );
      await tester.pumpAndSettle();
      expect(db.writes.single['role'], 'member');
      expect(db.writes.single['path'], 'Organizations/group/Members/Legacy');
      expect(find.textContaining('Error demoting member'), findsOneWidget);
      expect(find.text('Legacy removed from admin role'), findsNothing);
    },
  );

  testWidgets(
    'owner promotion retains canonical role and acknowledged success',
    (tester) async {
      final db = _Db()
        ..owner = true
        ..rows['Legacy'] = {'role': 'Member', 'status': 'approved'};
      await _open(tester, db);
      expect(_actionValues(tester, 'Legacy'), ['promote', 'remove']);
      tester.widget<PopupMenuButton<String>>(_menu('Legacy')).onSelected!(
        'promote',
      );
      await tester.pumpAndSettle();
      expect(db.writes.single['role'], 'admin');
      expect(find.text('Legacy promoted to admin'), findsOneWidget);
      expect(find.textContaining('Error promoting member'), findsNothing);
    },
  );

  testWidgets('read failure retains visible error and no management controls', (
    tester,
  ) async {
    final db = _Db()..rejectMembers = true;
    await _open(tester, db);
    expect(find.text('Error loading members'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(db.writes, isEmpty);
  });

  testWidgets('profile failure does not expose partial member actions', (
    tester,
  ) async {
    final db = _Db()
      ..owner = true
      ..rows['Member'] = {'role': 'Member', 'status': 'approved'};
    await _open(tester, db, rejectProfiles: true);
    expect(find.text('Member profiles unavailable'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(db.writes, isEmpty);
  });
}
