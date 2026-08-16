import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:attendus/models/check_in_session.dart';

const int _idempotencyRandomUpperBound = 0x100000000;

String createAttendanceIdempotencyKey(Random random, {DateTime? now}) =>
    '${(now ?? DateTime.now()).microsecondsSinceEpoch}-'
    '${random.nextInt(_idempotencyRandomUpperBound)}';

class VenueCredential {
  const VenueCredential({
    required this.eventId,
    required this.sessionId,
    required this.code,
    required this.qrData,
    required this.codeExpiresAt,
    required this.tokenExpiresAt,
  });

  final String eventId;
  final String sessionId;
  final String code;
  final String qrData;
  final DateTime codeExpiresAt;
  final DateTime tokenExpiresAt;

  factory VenueCredential.fromJson(Map<String, dynamic> data) =>
      VenueCredential(
        eventId: data['eventId']?.toString() ?? '',
        sessionId: data['sessionId']?.toString() ?? '',
        code: data['code']?.toString() ?? '',
        qrData: data['qrData']?.toString() ?? '',
        codeExpiresAt:
            DateTime.tryParse(data['codeExpiresAt']?.toString() ?? '') ??
            DateTime.now(),
        tokenExpiresAt:
            DateTime.tryParse(data['tokenExpiresAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class ResolvedCheckInCredential {
  const ResolvedCheckInCredential({
    required this.eventId,
    required this.sessionId,
    required this.title,
    required this.normalizedCredential,
    required this.policy,
  });

  final String eventId;
  final String sessionId;
  final String title;
  final String normalizedCredential;
  final Map<String, dynamic> policy;

  factory ResolvedCheckInCredential.fromJson(Map<String, dynamic> data) =>
      ResolvedCheckInCredential(
        eventId: data['eventId']?.toString() ?? '',
        sessionId: data['sessionId']?.toString() ?? '',
        title: data['title']?.toString() ?? 'Event',
        normalizedCredential: data['normalizedCredential']?.toString() ?? '',
        policy: _map(data['policy']),
      );
}

class CheckInReceipt {
  const CheckInReceipt({
    required this.attendanceId,
    required this.eventId,
    required this.sessionId,
    required this.attendeeName,
    required this.status,
    required this.checkedInAt,
    this.queuedOffline = false,
  });

  final String attendanceId;
  final String eventId;
  final String sessionId;
  final String attendeeName;
  final String status;
  final DateTime checkedInAt;
  final bool queuedOffline;

  factory CheckInReceipt.fromJson(Map<String, dynamic> data) => CheckInReceipt(
    attendanceId: data['attendanceId']?.toString() ?? '',
    eventId: data['eventId']?.toString() ?? '',
    sessionId: data['sessionId']?.toString() ?? '',
    attendeeName: data['attendeeName']?.toString() ?? 'Attendee',
    status: data['status']?.toString() ?? 'checked_in',
    checkedInAt:
        DateTime.tryParse(data['checkedInAt']?.toString() ?? '') ??
        DateTime.now(),
  );

  factory CheckInReceipt.queued(Map<String, dynamic> request) => CheckInReceipt(
    attendanceId: '',
    eventId: request['eventId']?.toString() ?? '',
    sessionId: request['sessionId']?.toString() ?? '',
    attendeeName:
        _map(request['credential'])['displayName']?.toString() ??
        _map(request['credential'])['fullName']?.toString() ??
        'Attendee',
    status: 'queued_offline',
    checkedInAt:
        DateTime.tryParse(request['observedAt']?.toString() ?? '') ??
        DateTime.now(),
    queuedOffline: true,
  );
}

class PersonalAttendancePass {
  const PersonalAttendancePass({
    required this.eventId,
    required this.sessionId,
    required this.attendeeName,
    required this.qrData,
    required this.expiresAt,
    required this.passLockRequired,
    this.appleWalletUrl,
    this.googleWalletUrl,
  });

  final String eventId;
  final String sessionId;
  final String attendeeName;
  final String qrData;
  final DateTime expiresAt;
  final bool passLockRequired;
  final String? appleWalletUrl;
  final String? googleWalletUrl;

  factory PersonalAttendancePass.fromJson(Map<String, dynamic> data) =>
      PersonalAttendancePass(
        eventId: data['eventId']?.toString() ?? '',
        sessionId: data['sessionId']?.toString() ?? '',
        attendeeName: data['attendeeName']?.toString() ?? 'Attendee',
        qrData: data['qrData']?.toString() ?? '',
        expiresAt:
            DateTime.tryParse(data['expiresAt']?.toString() ?? '') ??
            DateTime.now(),
        passLockRequired: data['passLockRequired'] == true,
        appleWalletUrl: data['appleWalletUrl']?.toString(),
        googleWalletUrl: data['googleWalletUrl']?.toString(),
      );
}

class OfflineSyncResult {
  const OfflineSyncResult({required this.synced, required this.remaining});
  final int synced;
  final int remaining;
}

class AttendanceCheckInService {
  AttendanceCheckInService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
    FlutterSecureStorage? storage,
  }) : _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
       _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? const FlutterSecureStorage();

  static const _offlineQueueKey = 'attendance_v2_offline_queue';
  static const _offlineKitPrefix = 'attendance_v2_offline_kit_';
  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;
  final FlutterSecureStorage _storage;
  final Random _random = Random.secure();

  String createIdempotencyKey() => createAttendanceIdempotencyKey(_random);

  Future<CheckInSession?> findActiveSession(String eventId) async {
    final snapshot = await _firestore
        .collection('CheckInSessions')
        .where('eventId', isEqualTo: eventId)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    final document = snapshot.docs.first;
    return CheckInSession.fromJson(document.data());
  }

  Stream<CheckInSession?> watchActiveSession(String eventId) => _firestore
      .collection('CheckInSessions')
      .where('eventId', isEqualTo: eventId)
      .where('status', isEqualTo: 'active')
      .limit(1)
      .snapshots()
      .map((snapshot) {
        if (snapshot.docs.isEmpty) return null;
        final document = snapshot.docs.first;
        return CheckInSession.fromJson(document.data());
      });

  Stream<QuerySnapshot<Map<String, dynamic>>> watchAttendance(String eventId) =>
      _firestore
          .collection('Attendance')
          .where('eventId', isEqualTo: eventId)
          .snapshots();

  Future<CheckInSession> startSession(String eventId) async {
    await _call('startCheckInSession', {'eventId': eventId});
    final session = await findActiveSession(eventId);
    if (session == null) {
      throw StateError('The check-in session could not be loaded.');
    }
    return session;
  }

  Future<void> endSession(String sessionId) =>
      _call('endCheckInSession', {'sessionId': sessionId});

  Future<VenueCredential> mintVenueCredential(String sessionId) async {
    final data = await _call('mintVenueCredential', {'sessionId': sessionId});
    return VenueCredential.fromJson(data);
  }

  Future<ResolvedCheckInCredential> resolveCredential(String value) async {
    final data = await _call('resolveCheckInCredential', {'value': value});
    return ResolvedCheckInCredential.fromJson(data);
  }

  Future<PersonalAttendancePass> getPersonalPass({
    required String eventId,
    String? sessionId,
  }) async {
    final data = await _call('getPersonalAttendancePass', {
      'eventId': eventId,
      'sessionId': ?sessionId,
    });
    return PersonalAttendancePass.fromJson(data);
  }

  Future<CheckInReceipt> submitCheckIn({
    required String eventId,
    required String sessionId,
    required Map<String, dynamic> credential,
    List<String> answers = const [],
    String? idempotencyKey,
    DateTime? observedAt,
    bool allowOfflineQueue = false,
  }) async {
    final request = <String, dynamic>{
      'eventId': eventId,
      'sessionId': sessionId,
      'idempotencyKey': idempotencyKey ?? createIdempotencyKey(),
      'credential': credential,
      'answers': answers,
      'observedAt': (observedAt ?? DateTime.now()).toUtc().toIso8601String(),
    };
    try {
      return CheckInReceipt.fromJson(await _call('submitCheckIn', request));
    } on FirebaseFunctionsException catch (error) {
      final canQueue =
          allowOfflineQueue &&
          const {'unavailable', 'deadline-exceeded'}.contains(error.code) &&
          credential['type'] != 'venue_token' &&
          await _offlineCredentialAllowed(request);
      if (!canQueue) rethrow;
      await _queueRequest(request);
      return CheckInReceipt.queued(request);
    }
  }

  Future<void> checkout({
    required String eventId,
    required String sessionId,
    String? attendanceId,
  }) async {
    await submitCheckIn(
      eventId: eventId,
      sessionId: sessionId,
      credential: {'type': 'checkout', 'attendanceId': ?attendanceId},
    );
  }

  Future<void> voidAttendance({
    required String attendanceId,
    required String reason,
  }) =>
      _call('voidAttendance', {'attendanceId': attendanceId, 'reason': reason});

  Future<int> pendingCount() async => (await _readQueue()).length;

  Future<void> prepareOfflineKit({
    required String eventId,
    required CheckInSession session,
    required String eligibility,
  }) async {
    if (session.passPublicKey == null || session.passPublicKey!.isEmpty) {
      throw StateError(
        'Restart this session to enable offline pass verification.',
      );
    }
    final results = await Future.wait([
      _firestore
          .collection('RegisterAttendance')
          .where('eventId', isEqualTo: eventId)
          .get(),
      _firestore
          .collection('Tickets')
          .where('eventId', isEqualTo: eventId)
          .get(),
    ]);
    final registrations = results[0].docs;
    final tickets = results[1].docs;
    final kit = <String, dynamic>{
      'version': 1,
      'eventId': eventId,
      'sessionId': session.id,
      'eligibility': eligibility,
      'passPublicKey': session.passPublicKey,
      'preparedAt': DateTime.now().toUtc().toIso8601String(),
      'closesAt': session.closesAt.toUtc().toIso8601String(),
      'rosterIds': registrations
          .map((doc) => doc.data()['customerUid']?.toString())
          .whereType<String>()
          .toSet()
          .toList(),
      'tickets': tickets
          .map(
            (doc) => {
              'id': doc.id,
              'ticketCode': doc.data()['ticketCode']?.toString(),
              'customerUid': doc.data()['customerUid']?.toString(),
              'isUsed': doc.data()['isUsed'] == true,
            },
          )
          .toList(),
    };
    await _storage.write(
      key: '$_offlineKitPrefix$eventId',
      value: jsonEncode(kit),
    );
  }

  Future<OfflineSyncResult> syncPending() async {
    final pending = await _readQueue();
    final remaining = <Map<String, dynamic>>[];
    var synced = 0;
    for (final request in pending) {
      try {
        await _call('submitCheckIn', request);
        synced += 1;
      } on FirebaseFunctionsException catch (error) {
        if (const {'unavailable', 'deadline-exceeded'}.contains(error.code)) {
          remaining.add(request);
        }
        // Permanent policy, authorization, or credential failures are removed.
        // The rejected attempt remains in the server audit whenever it arrived.
      }
    }
    await _writeQueue(remaining);
    return OfflineSyncResult(synced: synced, remaining: remaining.length);
  }

  Future<Map<String, dynamic>> _call(
    String functionName,
    Map<String, dynamic> request,
  ) async {
    final result = await _functions.httpsCallable(functionName).call(request);
    return _map(result.data);
  }

  Future<void> _queueRequest(Map<String, dynamic> request) async {
    final queue = await _readQueue();
    final key = request['idempotencyKey'];
    if (queue.any((entry) => entry['idempotencyKey'] == key)) return;
    if (queue.length >= 500) {
      throw StateError(
        'This device has 500 unsynced scans. Reconnect and reconcile before scanning more.',
      );
    }
    queue.add(request);
    await _writeQueue(queue);
  }

  Future<bool> _offlineCredentialAllowed(Map<String, dynamic> request) async {
    final eventId = request['eventId']?.toString() ?? '';
    final raw = await _storage.read(key: '$_offlineKitPrefix$eventId');
    if (raw == null) return false;
    Map<String, dynamic> kit;
    try {
      kit = _map(jsonDecode(raw));
    } catch (_) {
      return false;
    }
    if (kit['eventId'] != eventId ||
        kit['sessionId'] != request['sessionId'] ||
        DateTime.tryParse(
              kit['closesAt']?.toString() ?? '',
            )?.isBefore(DateTime.now().toUtc()) ==
            true) {
      return false;
    }
    final credential = _map(request['credential']);
    final type = credential['type']?.toString();
    final roster = (kit['rosterIds'] as List? ?? const [])
        .map((value) => value.toString())
        .toSet();
    if (type == 'staff_roster') {
      return roster.contains(credential['attendeeId']?.toString()) ||
          (credential['overrideReason']?.toString().trim().isNotEmpty ?? false);
    }
    if (type == 'staff_guest') {
      return kit['eligibility'] == 'open' ||
          (credential['overrideReason']?.toString().trim().isNotEmpty ?? false);
    }
    if (type == 'checkout') return true;
    if (type != 'personal_pass') return false;

    final ticketCode = credential['ticketCode']?.toString();
    if (ticketCode != null && ticketCode.isNotEmpty) {
      return (kit['tickets'] as List? ?? const []).whereType<Map>().any((item) {
        final ticket = _map(item);
        return ticket['ticketCode'] == ticketCode && ticket['isUsed'] != true;
      });
    }
    final token = (credential['token'] ?? credential['value'])
        ?.toString()
        .replaceFirst('attendus_pass:v1:', '');
    if (token == null) return false;
    final parts = token.split('.');
    if (parts.length != 2) return false;
    try {
      final publicKey = SimplePublicKey(
        base64Url.decode(base64Url.normalize(kit['passPublicKey'].toString())),
        type: KeyPairType.ed25519,
      );
      final valid = await Ed25519().verify(
        utf8.encode(parts[0]),
        signature: Signature(
          base64Url.decode(base64Url.normalize(parts[1])),
          publicKey: publicKey,
        ),
      );
      if (!valid) return false;
      final payload = _map(
        jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))),
        ),
      );
      final observed = DateTime.tryParse(
        request['observedAt']?.toString() ?? '',
      );
      final expiry = DateTime.fromMillisecondsSinceEpoch(
        (payload['exp'] as num?)?.toInt() ?? 0,
        isUtc: true,
      );
      return payload['t'] == 'pass' &&
          payload['e'] == eventId &&
          payload['s'] == request['sessionId'] &&
          observed != null &&
          !expiry.isBefore(observed.toUtc());
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> _readQueue() async {
    final raw = await _storage.read(key: _offlineQueueKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.whereType<Map>().map(_map).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeQueue(List<Map<String, dynamic>> queue) =>
      _storage.write(key: _offlineQueueKey, value: jsonEncode(queue));
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return <String, dynamic>{};
}
