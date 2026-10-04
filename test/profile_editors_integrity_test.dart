import 'dart:async';
import 'dart:convert';

import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/screens/Home/account_details_screen.dart';
import 'package:attendus/screens/Home/account_details_screen_v2.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
  @override
  String get email => '$uid@example.test';
  @override
  String get displayName => 'Controlled staff';
  @override
  String? get phoneNumber => null;
  @override
  String? get photoURL => null;
  @override
  List<UserInfo> get providerData => [];
  @override
  Future<void> reload() async {}
}

class _Auth extends Fake implements FirebaseAuth {
  @override
  User? currentUser = _User('staff');
  final changes = StreamController<User?>.broadcast();
  @override
  Stream<User?> authStateChanges() async* {
    yield currentUser;
    yield* changes.stream;
  }
}

// These SDK boundary doubles run the real screens and real model serialization.
// No Firebase app, emulator, plugin service or network is initialized.
class _Db extends Fake implements FirebaseFirestore {
  final data = <String, Map<String, dynamic>>{};
  final writes = <({String path, Map<String, dynamic> patch})>[];
  final failingReads = <String>{};
  int writeAttempts = 0;
  bool rejectWrites = false;
  Completer<void>? writeAck;
  void Function()? afterWrite;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);
  @override
  DocumentReference<Map<String, dynamic>> doc(String path) => _Ref(this, path);
  Future<void> apply(String path, Map<String, dynamic> patch) async {
    writeAttempts++;
    if (writeAck != null) await writeAck!.future;
    if (rejectWrites) throw StateError('Injected write failure');
    data[path] = {...?data[path], ...patch};
    writes.add((path: path, patch: Map.of(patch)));
    afterWrite?.call();
  }

  @override
  Future<T> runTransaction<T>(
    Future<T> Function(Transaction) handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    final tx = _Tx(this);
    final result = await handler(tx);
    for (final write in tx.pending) {
      await apply(write.path, write.patch);
    }
    return result;
  }
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
  CollectionReference<Map<String, dynamic>> collection(String child) =>
      _Collection(db, '$path/$child');
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    if (db.failingReads.contains(path)) {
      throw StateError('Injected read failure');
    }
    return _Snapshot(
      this,
      db.data[path] == null ? null : Map.of(db.data[path]!),
    );
  }

  @override
  Future<void> update(Map<Object, Object?> data) =>
      db.apply(path, data.cast<String, dynamic>());
}

// ignore: subtype_of_sealed_class
class _Snapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.reference, this.fields);
  @override
  final DocumentReference<Map<String, dynamic>> reference;
  final Map<String, dynamic>? fields;
  @override
  String get id => reference.id;
  @override
  bool get exists => fields != null;
  @override
  Map<String, dynamic>? data() => fields;
}

class _Tx extends Fake implements Transaction {
  _Tx(this.db);
  final _Db db;
  final pending = <({String path, Map<String, dynamic> patch})>[];
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> ref,
  ) async {
    expect(
      pending,
      isEmpty,
      reason: 'All transaction reads must precede writes',
    );
    return await (ref as _Ref).get() as DocumentSnapshot<T>;
  }

  @override
  Transaction update(DocumentReference ref, Map<Object, Object?> data) {
    pending.add((path: ref.path, patch: data.cast<String, dynamic>()));
    return this;
  }

  @override
  Transaction set<T>(DocumentReference<T> ref, T data, [SetOptions? options]) {
    pending.add((path: ref.path, patch: (data as Map).cast<String, dynamic>()));
    return this;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const profilePath = 'Customers/staff';
  const settingsPath = 'users/staff/settings/notifications';
  late _Db db;
  late _Auth auth;
  setUp(() {
    auth = _Auth();
    db = _Db();
    db.data[profilePath] = {
      'uid': 'staff',
      'name': 'Controlled staff',
      'email': 'staff@example.test',
      'username': 'controlled_staff',
      'bio': 'Original bio',
      'favorites': ['old-saved'],
      'isDiscoverable': true,
      'createdAt': Timestamp(1791110400, 123456000),
      'eventsCreated': 4,
      'groupsCreated': 2,
      'socialMediaLinks':
          '{ "unknown": "retain me", "twitter": "https://example.test" }',
    };
    db.data[settingsPath] = {
      'eventReminders': false,
      'messagesAll': true,
      'generalNotifications': false,
      'unknownPreference': false,
    };
    CustomerController.logeInCustomer = CustomerModel.fromFirestore(
      _Snapshot(_Ref(db, profilePath), db.data[profilePath]),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('PonnamKarthik/fluttertoast'),
          (_) async => true,
        );
  });
  tearDown(() async {
    CustomerController.logeInCustomer = null;
    await auth.changes.close();
  });

  Future<void> open(WidgetTester tester, bool legacy) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: legacy
            ? AccountDetailsScreen(auth: auth, firestore: db)
            : AccountDetailsScreenV2(auth: auth, firestore: db),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester, {bool valid = true}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(tester.state<FormState>(find.byType(Form)).validate(), valid);
    await tester.tap(find.text('Save Changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  for (final legacy in [false, true]) {
    final editor = legacy ? 'legacy' : 'V2';
    testWidgets(
      '$editor name save preserves concurrent privacy bio favorites timestamp and photo',
      (tester) async {
        await open(tester, legacy);
        final originalTime = db.data[profilePath]!['createdAt'];
        db.data[profilePath]!.addAll({
          'isDiscoverable': false,
          'favorites': ['new-saved'],
          'bio': 'Newer bio',
          'profilePictureUrl': 'newer-photo',
        });
        db.data[settingsPath]!['messagesAll'] = false;
        await tester.enterText(find.byType(TextFormField).first, 'Edited name');
        await save(tester);
        expect(db.writes, hasLength(1));
        expect(db.writes.single.patch, {'name': 'Edited name'});
        expect(db.data[profilePath]!['createdAt'], same(originalTime));
        expect(db.data[profilePath]!['isDiscoverable'], false);
        expect(db.data[profilePath]!['favorites'], ['new-saved']);
        expect(db.data[settingsPath]!['messagesAll'], false);
        expect(CustomerController.logeInCustomer!.bio, 'Newer bio');
        expect(CustomerController.logeInCustomer!.favorites, ['new-saved']);
        expect(
          CustomerController.logeInCustomer!.profilePictureUrl,
          'newer-photo',
        );
        await close(tester);
      },
    );
    testWidgets('$editor failed save never mutates shared customer', (
      tester,
    ) async {
      await open(tester, legacy);
      final before = CustomerController.logeInCustomer;
      db.rejectWrites = true;
      await tester.enterText(find.byType(TextFormField).first, 'Unsaved name');
      await save(tester);
      expect(identical(CustomerController.logeInCustomer, before), isTrue);
      expect(before!.name, 'Controlled staff');
      expect(db.writeAttempts, 1);
      expect(db.writes, isEmpty);
      await close(tester);
    });
    testWidgets(
      '$editor load failure exposes no save controls or default consent',
      (tester) async {
        db.failingReads.add(legacy ? settingsPath : profilePath);
        await open(tester, legacy);
        expect(find.text('Save Changes'), findsNothing);
        expect(find.text('Try again'), findsOneWidget);
        expect(db.writeAttempts, 0);
        expect(db.writes, isEmpty);
        await close(tester);
      },
    );
    testWidgets(
      '$editor acknowledged save with failed reload blocks further editing',
      (tester) async {
        await open(tester, legacy);
        final before = CustomerController.logeInCustomer;
        db.afterWrite = () => db.failingReads.add(profilePath);
        await tester.enterText(
          find.byType(TextFormField).first,
          'Committed name',
        );
        await save(tester);
        expect(db.writes, hasLength(1));
        expect(db.data[profilePath]!['name'], 'Committed name');
        expect(CustomerController.logeInCustomer, same(before));
        expect(before!.name, 'Controlled staff');
        expect(find.text('Save Changes'), findsNothing);
        expect(find.text('Try again'), findsOneWidget);
        await close(tester);
      },
    );
    testWidgets(
      '$editor account switch during acknowledgement never replaces new controller',
      (tester) async {
        await open(tester, legacy);
        db.writeAck = Completer<void>();
        await tester.enterText(
          find.byType(TextFormField).first,
          'Old account edit',
        );
        await save(tester);
        final newCustomer = CustomerModel(
          uid: 'other',
          name: 'Other member',
          email: 'other@example.test',
          createdAt: DateTime(2026),
        );
        auth.currentUser = _User('other');
        auth.changes.add(auth.currentUser);
        CustomerController.logeInCustomer = newCustomer;
        db.writeAck!.complete();
        await tester.pumpAndSettle();
        expect(CustomerController.logeInCustomer, same(newCustomer));
        expect(db.writes.every((w) => w.path == profilePath), isTrue);
        await close(tester);
      },
    );
  }

  testWidgets(
    'V2 saved name survives editor reopen despite older Auth displayName',
    (tester) async {
      db.data[profilePath]!['name'] = 'User selected name';
      await open(tester, false);
      expect(db.writes, isEmpty);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'User selected name',
      );
      await close(tester);
    },
  );
  testWidgets('V2 changed username saves normalized searchable handle', (
    tester,
  ) async {
    await open(tester, false);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      '  Alice_Example  ',
    );
    await save(tester);
    expect(db.writes, hasLength(1));
    expect(db.writes.single.patch, {'username': 'alice_example'});
    expect(CustomerController.logeInCustomer!.username, 'alice_example');
    await close(tester);
  });
  for (final invalid in ['ab', 'has space', '@name', 'n\u00e1me', 'x' * 51]) {
    testWidgets('V2 rejects changed invalid username "$invalid" before write', (
      tester,
    ) async {
      await open(tester, false);
      final before = CustomerController.logeInCustomer;
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        invalid,
      );
      await save(tester, valid: false);
      expect(
        find.text('Use 3 to 50 letters, numbers or underscores'),
        findsOneWidget,
      );
      expect(db.writeAttempts, 0);
      expect(db.writes, isEmpty);
      expect(CustomerController.logeInCustomer, same(before));
      expect(db.data[profilePath]!['username'], 'controlled_staff');
      await close(tester);
    });
  }
  for (final length in [3, 50]) {
    testWidgets('V2 accepts changed username at $length character boundary', (
      tester,
    ) async {
      await open(tester, false);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'A' * length,
      );
      await save(tester);
      expect(db.writes, hasLength(1));
      expect(db.writes.single.patch, {'username': 'a' * length});
      await close(tester);
    });
  }
  for (final historical in ['MiXeD_Old', 'Legacy handle!', '  old handle  ']) {
    testWidgets('V2 name edit preserves unchanged raw handle "$historical"', (
      tester,
    ) async {
      db.data[profilePath]!['username'] = historical;
      await open(tester, false);
      await tester.enterText(find.byType(TextFormField).first, 'Edited name');
      await save(tester);
      expect(db.writes, hasLength(1));
      expect(db.writes.single.patch, {'name': 'Edited name'});
      expect(db.data[profilePath]!['username'], historical);
      expect(CustomerController.logeInCustomer!.username, historical);
      await close(tester);
    });
  }
  testWidgets('V2 explicit blank username still clears the optional handle', (
    tester,
  ) async {
    await open(tester, false);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      '   ',
    );
    await save(tester);
    expect(db.writes, hasLength(1));
    expect(db.writes.single.patch, {'username': null});
    expect(CustomerController.logeInCustomer!.username, isNull);
    await close(tester);
  });
  testWidgets('V2 missing optional handle does not block an unrelated edit', (
    tester,
  ) async {
    db.data[profilePath]!.remove('username');
    await open(tester, false);
    await tester.enterText(find.byType(TextFormField).first, 'Edited name');
    await save(tester);
    expect(db.writes, hasLength(1));
    expect(db.writes.single.patch, {'name': 'Edited name'});
    expect(db.data[profilePath]!.containsKey('username'), isFalse);
    await close(tester);
  });
  testWidgets('legacy explicit privacy toggle saves only that control', (
    tester,
  ) async {
    await open(tester, true);
    final privacy = find.byType(Switch).first;
    await tester.ensureVisible(privacy);
    await tester.tap(privacy);
    await tester.pump();
    await save(tester);
    expect(db.writes, hasLength(1));
    expect(db.writes.single.patch, {'isDiscoverable': false});
    await close(tester);
  });
  testWidgets(
    'legacy new canonical preferences preserve fresh fallback false atomically with name',
    (tester) async {
      db.data.remove(settingsPath);
      db.data[profilePath]!['notificationPreferences'] = {
        'eventReminders': false,
        'announcements': false,
        'messages': true,
      };
      await open(tester, true);
      await tester.enterText(find.byType(TextFormField).first, 'Edited name');
      final messages = find.byType(Switch).at(2);
      await tester.ensureVisible(messages);
      await tester.tap(messages);
      await tester.pump();
      await save(tester);
      expect(db.writes, hasLength(2));
      expect(db.writes.first.patch, {'name': 'Edited name'});
      expect(db.data[settingsPath]!['eventReminders'], false);
      expect(db.data[settingsPath]!['generalNotifications'], false);
      expect(db.data[settingsPath]!['messagesAll'], false);
      await close(tester);
    },
  );
  testWidgets(
    'legacy social edit preserves unknown and concurrently changed untouched social keys',
    (tester) async {
      await open(tester, true);
      db.data[profilePath]!['socialMediaLinks'] =
          '{"unknown":"retain newer","twitter":"https://example.test","instagram":"https://example.test/newer"}';
      final twitter = find.byWidgetPredicate(
        (widget) =>
            widget is TextFormField &&
            widget.controller?.text == 'https://example.test',
      );
      await tester.ensureVisible(twitter);
      await tester.pumpAndSettle();
      await tester.enterText(twitter, 'https://example.test/edited');
      await save(tester);
      expect(db.writes, hasLength(1));
      final social = jsonDecode(
        db.data[profilePath]!['socialMediaLinks'] as String,
      );
      expect(social, {
        'unknown': 'retain newer',
        'twitter': 'https://example.test/edited',
        'instagram': 'https://example.test/newer',
      });
      await close(tester);
    },
  );
  testWidgets(
    'legacy malformed social storage blocks social mutation without destroying data',
    (tester) async {
      db.data[profilePath]!['socialMediaLinks'] = 'malformed JSON';
      await open(tester, true);
      // Twitter is the first social control immediately after the Bio controller.
      final controls = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      final bio = controls.indexWhere(
        (w) => w.controller?.text == 'Original bio',
      );
      final twitter = find.byWidget(controls[bio + 1]);
      await tester.ensureVisible(twitter);
      await tester.pumpAndSettle();
      await tester.enterText(twitter, 'https://example.test/edited');
      await save(tester);
      expect(db.writes, isEmpty);
      expect(db.data[profilePath]!['socialMediaLinks'], 'malformed JSON');
      await close(tester);
    },
  );
  testWidgets(
    'legacy opening profile with no username performs no implicit write',
    (tester) async {
      db.data[profilePath]!.remove('username');
      await open(tester, true);
      expect(db.writes, isEmpty);
      final username = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .elementAt(2);
      expect(username.controller!.text, isEmpty);
      await close(tester);
    },
  );
  testWidgets(
    'legacy name-only edit preserves malformed social storage untouched',
    (tester) async {
      db.data[profilePath]!['socialMediaLinks'] = 'malformed JSON';
      await open(tester, true);
      await tester.enterText(find.byType(TextFormField).first, 'Edited name');
      await save(tester);
      expect(db.writes, hasLength(1));
      expect(db.writes.single.patch, {'name': 'Edited name'});
      expect(db.data[profilePath]!['socialMediaLinks'], 'malformed JSON');
      await close(tester);
    },
  );
}
