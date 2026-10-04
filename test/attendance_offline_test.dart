import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:attendus/Services/attendance_check_in_service.dart';

class _Firestore extends Fake implements FirebaseFirestore {}

class _Result<T> extends Fake implements HttpsCallableResult<T> {
  _Result(this.data);
  @override
  final T data;
}

class _Callable extends Fake implements HttpsCallable {
  _Callable(this.owner);
  final _Functions owner;
  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    if (!owner.online) {
      throw FirebaseFunctionsException(code: 'unavailable', message: 'Offline');
    }
    return _Result<T>(
      {
            'attendanceId': 'accepted',
            'conflict': owner.conflict,
            'status': 'checked_in',
          }
          as T,
    );
  }
}

class _Functions extends Fake implements FirebaseFunctions {
  bool online = false;
  bool conflict = false;
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _Callable(this);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AttendanceCheckInService service;
  late _Functions functions;
  late Map<String, dynamic> kit;
  late List<String> tokens;
  String? currentUid;
  const storage = FlutterSecureStorage();

  setUp(() async {
    functions = _Functions();
    currentUid = 'staff';
    service = AttendanceCheckInService(
      functions: functions,
      firestore: _Firestore(),
      storage: storage,
      currentUid: () => currentUid,
    );
    final pair = await Ed25519().newKeyPair();
    final public = await pair.extractPublicKey();
    final now = DateTime.now().toUtc();
    kit = {
      'staffUid': 'staff',
      'eventId': 'event',
      'sessionId': 'session',
      'revision': 'schedule',
      'preparedAt': now.toIso8601String(),
      'opensAt': now.subtract(const Duration(hours: 1)).toIso8601String(),
      'closesAt': now.add(const Duration(hours: 1)).toIso8601String(),
      'publicKeys': {
        'test': {'publicKey': base64Url.encode(public.bytes), 'revoked': false},
      },
      'passes': <String, dynamic>{},
    };
    tokens = [];
    for (final id in ['first', 'second']) {
      final payload = base64Url.encode(
        utf8.encode(
          jsonEncode({
            'v': 2,
            'kind': 'event',
            'id': id,
            'cv': 1,
            'kid': 'test',
            'exp': now.add(const Duration(days: 1)).millisecondsSinceEpoch,
          }),
        ),
      );
      final signature = await Ed25519().sign(
        utf8.encode(payload),
        keyPair: pair,
      );
      tokens.add(
        'attendus_pass:v2:$payload.${base64Url.encode(signature.bytes)}',
      );
      (kit['passes'] as Map)[id] = {
        'kind': 'event',
        'credentialVersion': 1,
        'status': 'active',
        'admissionKey': 'ticket:$id',
      };
    }
    FlutterSecureStorage.setMockInitialValues({
      'attendance_v2_offline_kit_event': jsonEncode(kit),
    });
  });

  Future<CheckInReceipt> scan(String token) => service.submitCheckIn(
    eventId: 'event',
    sessionId: 'session',
    credential: {'type': 'attendance_pass', 'value': token},
    allowOfflineQueue: true,
  );

  test(
    'rejected scans remain private to their staff account and survive other account acknowledgements',
    () async {
      await scan(tokens.first);
      functions.online = true;
      functions.conflict = true;
      await service.syncPending();
      final own = await service.rejectedScans();
      expect(own, hasLength(1));
      final key = own.single['idempotencyKey'] as String;
      currentUid = 'other-staff';
      expect(await service.rejectedScans(), isEmpty);
      await service.acknowledgeRejectedScans(idempotencyKey: key);
      await service.syncPending();
      currentUid = 'staff';
      expect(await service.rejectedScans(), hasLength(1));
      await service.acknowledgeRejectedScans(idempotencyKey: key);
      expect(await service.rejectedScans(), isEmpty);
    },
  );

  test(
    'offline kits and pending replay stay bound to the downloading staff account',
    () async {
      await scan(tokens.first);
      currentUid = 'other-staff';
      await expectLater(
        scan(tokens.last),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      functions.online = true;
      expect((await service.syncPending()).synced, 0);
      expect(await service.pendingCount(), 1);
      currentUid = 'staff';
      expect((await service.syncPending()).synced, 1);
    },
  );

  test(
    'concurrent offline writes preserve both entries and reconciliation removes each once',
    () async {
      final receipts = await Future.wait(tokens.map(scan));
      expect(receipts.every((r) => r.queuedOffline), true);
      expect(await service.pendingCount(), 2);
      functions.online = true;
      expect((await service.syncPending()).synced, 2);
      expect(await service.pendingCount(), 0);
      expect((await service.syncPending()).synced, 0);
      functions.online = false;
      await expectLater(scan(tokens.first), throwsStateError);
    },
  );

  test(
    'offline guest and override admission require current online eligibility',
    () async {
      kit['eligibility'] = 'open';
      await storage.write(
        key: 'attendance_v2_offline_kit_event',
        value: jsonEncode(kit),
      );
      await expectLater(
        service.submitCheckIn(
          eventId: 'event',
          sessionId: 'session',
          credential: {
            'type': 'staff_guest',
            'fullName': 'New Guest',
            'overrideReason': 'Staff approval',
          },
          allowOfflineQueue: true,
        ),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      expect(await service.pendingCount(), 0);
    },
  );

  test(
    'required answers must be supplied or present in cached pass eligibility',
    () async {
      kit['questions'] = [
        {'questionTitle': 'Company', 'required': true},
      ];
      await storage.write(
        key: 'attendance_v2_offline_kit_event',
        value: jsonEncode(kit),
      );
      await expectLater(
        scan(tokens.first),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      (kit['passes'] as Map)['first']['answers'] = ['Company--ans--Attendus'];
      await storage.write(
        key: 'attendance_v2_offline_kit_event',
        value: jsonEncode(kit),
      );
      expect((await scan(tokens.first)).queuedOffline, true);
      expect(
        (await service.submitCheckIn(
          eventId: 'event',
          sessionId: 'session',
          credential: {'type': 'attendance_pass', 'value': tokens.last},
          answers: ['Company--ans--Attendus'],
          allowOfflineQueue: true,
        )).queuedOffline,
        true,
      );
    },
  );

  test(
    'offline roster and legacy ticket reuse cached required answers',
    () async {
      kit['version'] = 2;
      kit['questions'] = [
        {'questionTitle': 'Company', 'required': true},
      ];
      kit['rosterIds'] = ['owner'];
      kit['rosterAdmissions'] = {'owner': 'registration:owner'};
      kit['rosterAnswers'] = {
        'owner': ['Company--ans--Attendus'],
      };
      kit['tickets'] = [
        {
          'id': 'ticket',
          'ticketCode': 'code',
          'admissionKey': 'ticket:ticket',
          'answers': ['Company--ans--Attendus'],
        },
      ];
      await storage.write(
        key: 'attendance_v2_offline_kit_event',
        value: jsonEncode(kit),
      );
      expect(
        (await service.submitCheckIn(
          eventId: 'event',
          sessionId: 'session',
          credential: {'type': 'staff_roster', 'attendeeId': 'owner'},
          allowOfflineQueue: true,
        )).queuedOffline,
        true,
      );
      expect(
        (await service.submitCheckIn(
          eventId: 'event',
          sessionId: 'session',
          credential: {'type': 'personal_pass', 'ticketCode': 'code'},
          allowOfflineQueue: true,
        )).queuedOffline,
        true,
      );
    },
  );

  test(
    'tampered credentials and stale kits cannot enter the pending queue',
    () async {
      await expectLater(
        scan('${tokens.first}tampered'),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      kit['preparedAt'] = DateTime.now()
          .subtract(const Duration(hours: 25))
          .toIso8601String();
      await storage.write(
        key: 'attendance_v2_offline_kit_event',
        value: jsonEncode(kit),
      );
      await expectLater(
        scan(tokens.first),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      expect(await service.pendingCount(), 0);
    },
  );

  test(
    'server reconciliation conflicts remain visible until staff acknowledge them',
    () async {
      await scan(tokens.first);
      functions.online = true;
      functions.conflict = true;
      final result = await service.syncPending();
      expect(result.rejected, 1);
      expect(result.synced, 0);
      expect(
        (await service.rejectedScans()).single['rejectionCode'],
        'duplicate_conflict',
      );
      final rejected = await service.rejectedScans();
      await service.acknowledgeRejectedScans(
        idempotencyKey: rejected.single['idempotencyKey'] as String,
      );
      expect(await service.rejectedScans(), isEmpty);
    },
  );

  test('acknowledging one offline conflict preserves the other', () async {
    await scan(tokens.first);
    await scan(tokens[1]);
    functions.online = true;
    functions.conflict = true;
    await service.syncPending();
    final rejected = await service.rejectedScans();
    expect(rejected.length, 2);
    await service.acknowledgeRejectedScans(
      idempotencyKey: rejected.first['idempotencyKey'] as String,
    );
    final remaining = await service.rejectedScans();
    expect(remaining.length, 1);
    expect(remaining.single['idempotencyKey'], rejected.last['idempotencyKey']);
  });

  test(
    'staff roster and signed pass share the same offline admission',
    () async {
      kit['version'] = 2;
      kit['rosterIds'] = ['owner'];
      kit['rosterAdmissions'] = {'owner': 'ticket:first'};
      await storage.write(
        key: 'attendance_v2_offline_kit_event',
        value: jsonEncode(kit),
      );
      await scan(tokens.first);
      await expectLater(
        service.submitCheckIn(
          eventId: 'event',
          sessionId: 'session',
          credential: {'type': 'staff_roster', 'attendeeId': 'owner'},
          allowOfflineQueue: true,
        ),
        throwsStateError,
      );
      expect(await service.pendingCount(), 1);
    },
  );

  test(
    'cached attendance and ambiguous roster admissions need an online check',
    () async {
      kit['version'] = 2;
      kit['checkedInAdmissions'] = ['ticket:first'];
      kit['rosterIds'] = ['multiple-ticket-owner'];
      kit['rosterAdmissions'] = <String, String>{};
      await storage.write(
        key: 'attendance_v2_offline_kit_event',
        value: jsonEncode(kit),
      );
      await expectLater(
        scan(tokens.first),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      await expectLater(
        service.submitCheckIn(
          eventId: 'event',
          sessionId: 'session',
          credential: {
            'type': 'staff_roster',
            'attendeeId': 'multiple-ticket-owner',
            'overrideReason': 'Does not resolve which ticket to admit',
          },
          allowOfflineQueue: true,
        ),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      expect(await service.pendingCount(), 0);
    },
  );
}
