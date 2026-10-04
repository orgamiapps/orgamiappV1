import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:math';
import 'package:attendus/Utils/check_in_questions.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  const OfflineSyncResult({
    required this.synced,
    required this.remaining,
    this.rejected = 0,
  });
  final int rejected;
  final int synced;
  final int remaining;
}

class AttendanceCheckInService {
  AttendanceCheckInService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
    FlutterSecureStorage? storage,
    String? Function()? currentUid,
  }) : _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
       _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? const FlutterSecureStorage(),
       _currentUid =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid);

  static const _offlineRejectedKey = 'attendance_v2_offline_rejected';
  static const _offlineQueueKey = 'attendance_v2_offline_queue';
  static const _offlineKitPrefix = 'attendance_v2_offline_kit_';
  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;
  final FlutterSecureStorage _storage;
  final String? Function() _currentUid;
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
          !kIsWeb &&
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

  Future<Map<String, dynamic>> scanContext(
    String eventId,
    String qrData,
    String sessionId, {
    String? ticketId,
  }) async {
    try {
      return await _call('getAttendanceScanContext', {
        'eventId': eventId,
        'token': qrData,
        'ticketId': ?ticketId,
      });
    } on FirebaseFunctionsException catch (error) {
      if (kIsWeb ||
          !const {'unavailable', 'deadline-exceeded'}.contains(error.code)) {
        rethrow;
      }
      final raw = await _storage.read(key: '$_offlineKitPrefix$eventId');
      if (raw == null) rethrow;
      final kit = _map(jsonDecode(raw));
      final request = {
        'eventId': eventId,
        'sessionId': sessionId,
        'observedAt': DateTime.now().toUtc().toIso8601String(),
        'credential': {'type': 'attendance_pass', 'value': qrData},
      };
      if (!await _offlineCredentialAllowed(request)) rethrow;
      final encoded = qrData
          .substring('attendus_pass:v2:'.length)
          .split('.')
          .first;
      final payload = _map(
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(encoded)))),
      );
      final admission = _map(_map(kit['passes'])[payload['id']]);
      return {
        'answers': admission['answers'] ?? [],
        'questions': kit['questions'] ?? [],
      };
    }
  }

  Future<int> pendingCount() async => (await _readQueue()).length;

  Future<void> prepareOfflineKit({
    required String eventId,
    required CheckInSession session,
    required String eligibility,
  }) async {
    if (kIsWeb) {
      throw StateError('Staff scanning in the browser requires internet.');
    }
    final kit = await _call('getAttendanceOfflineKit', {
      'eventId': eventId,
      'sessionId': session.id,
    });
    await _storage.write(
      key: '$_offlineKitPrefix$eventId',
      value: jsonEncode(kit),
    );
  }

  Future<List<Map<String, dynamic>>> _readRejectedScans() async {
    final raw = await _storage.read(key: _offlineRejectedKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).whereType<Map>().map(_map).toList();
  }

  /// Never expose another staff member's reconciliation history on this device.
  Future<List<Map<String, dynamic>>> rejectedScans() async {
    final uid = _currentUid();
    if (uid == null) return [];
    final records = await _readRejectedScans();
    if (_currentUid() != uid) return [];
    return records.where((record) => record['offlineStaffUid'] == uid).toList();
  }

  Future<Map<String, dynamic>> offlineKitStatus(String eventId) async {
    final raw = await _storage.read(key: '$_offlineKitPrefix$eventId');
    final kit = raw == null ? <String, dynamic>{} : _map(jsonDecode(raw));
    if (kit['staffUid'] != _currentUid()) return {};
    return {
      'preparedAt': kit['preparedAt'],
      'lastSync': await _storage.read(key: 'attendance_last_sync'),
    };
  }

  Future<void> acknowledgeRejectedScans({required String idempotencyKey}) =>
      _serializeQueue(() async {
        final uid = _currentUid();
        if (uid == null) return;
        final records = await _readRejectedScans();
        if (_currentUid() != uid) return;
        records.removeWhere(
          (record) =>
              record['offlineStaffUid'] == uid &&
              record['idempotencyKey'] == idempotencyKey,
        );
        await _storage.write(
          key: _offlineRejectedKey,
          value: jsonEncode(records),
        );
      });

  static Future<void> _queueMutation = Future<void>.value();

  Future<T> _serializeQueue<T>(Future<T> Function() work) {
    final next = _queueMutation.then((_) => work());
    _queueMutation = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return next;
  }

  Future<OfflineSyncResult> syncPending() => _serializeQueue(_syncPending);

  Future<OfflineSyncResult> _syncPending() async {
    final pending = await _readQueue();
    final remaining = <Map<String, dynamic>>[];
    var synced = 0;
    final rejected = await _readRejectedScans();
    for (final request in pending) {
      if (request['offlineStaffUid'] != null &&
          request['offlineStaffUid'] != _currentUid()) {
        remaining.add(request);
        continue;
      }
      try {
        final result = await _call('submitCheckIn', {
          ...request,
          'offline': true,
        });
        if (result['conflict'] == true) {
          rejected.add({
            ...request,
            'rejectionCode': 'duplicate_conflict',
            'rejectionMessage':
                'Already checked in through another scan. Attendance was not added again.',
            'attendanceId': result['attendanceId'],
          });
        } else {
          synced += 1;
        }
      } on FirebaseFunctionsException catch (error) {
        if (const {'unavailable', 'deadline-exceeded'}.contains(error.code)) {
          remaining.add(request);
        }
        if (!const {'unavailable', 'deadline-exceeded'}.contains(error.code)) {
          rejected.add({
            ...request,
            'rejectionCode': error.code,
            'rejectionMessage': error.message ?? 'Staff review is required.',
          });
        }
      }
    }
    await _writeQueue(remaining);
    if (remaining.length < pending.length) {
      await _storage.write(
        key: 'attendance_last_sync',
        value: DateTime.now().toUtc().toIso8601String(),
      );
    }
    await _storage.write(key: _offlineRejectedKey, value: jsonEncode(rejected));
    return OfflineSyncResult(
      synced: synced,
      remaining: remaining.length,
      rejected: rejected
          .where((record) => record['offlineStaffUid'] == _currentUid())
          .length,
    );
  }

  Future<Map<String, dynamic>> _call(
    String functionName,
    Map<String, dynamic> request,
  ) async {
    final result = await _functions.httpsCallable(functionName).call(request);
    return _map(result.data);
  }

  Future<void> _queueRequest(Map<String, dynamic> request) =>
      _serializeQueue(() => _appendQueuedRequest(request));

  Future<void> _appendQueuedRequest(Map<String, dynamic> request) async {
    if (!await _offlineCredentialAllowed(request)) {
      throw StateError(
        'This scan needs an online eligibility check. Reconnect or ask another staff member.',
      );
    }
    final queue = await _readQueue();
    final key = request['idempotencyKey'];
    if (queue.any((entry) => entry['idempotencyKey'] == key)) return;
    if (queue.length >= 500) {
      throw StateError(
        'This device has 500 unsynced scans. Reconnect and reconcile before scanning more.',
      );
    }
    final raw = await _storage.read(
      key: '$_offlineKitPrefix${request['eventId']}',
    );
    final kit = raw == null ? <String, dynamic>{} : _map(jsonDecode(raw));
    final admission = _offlineAdmission(request, kit);
    final redeemedRaw = await _storage.read(
      key: 'attendance_redemptions_${request['eventId']}',
    );
    final redeemed = redeemedRaw == null
        ? <String>[]
        : (jsonDecode(redeemedRaw) as List).cast<String>();
    if (admission != null && redeemed.contains(admission)) {
      throw StateError(
        'This attendee was already scanned on this device. Reconnect for reentry.',
      );
    }
    if (admission != null &&
        queue.any(
          (item) =>
              item['eventId'] == request['eventId'] &&
              item['offlineAdmission'] == admission,
        )) {
      throw StateError(
        'This attendee already has a pending scan on this device.',
      );
    }
    queue.add({
      ...request,
      'offlineAdmission': admission,
      'offlineKitRevision': kit['revision'],
      'offlineStaffUid': kit['staffUid'],
    });
    await _writeQueue(queue);
    if (admission != null) {
      await _storage.write(
        key: 'attendance_redemptions_${request['eventId']}',
        value: jsonEncode([...redeemed, admission]),
      );
    }
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
    final observedAt = DateTime.tryParse(
      request['observedAt']?.toString() ?? '',
    );
    if (kit['staffUid'] == null || kit['staffUid'] != _currentUid()) {
      return false;
    }
    final preparedAt = DateTime.tryParse(kit['preparedAt']?.toString() ?? '');
    final opensAt = DateTime.tryParse(kit['opensAt']?.toString() ?? '');
    final closesAt = DateTime.tryParse(kit['closesAt']?.toString() ?? '');
    if (observedAt == null ||
        preparedAt == null ||
        opensAt == null ||
        closesAt == null ||
        DateTime.now().difference(preparedAt) > const Duration(hours: 24) ||
        preparedAt.isAfter(DateTime.now().add(const Duration(seconds: 5))) ||
        observedAt.isBefore(opensAt) ||
        observedAt.isAfter(closesAt)) {
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
    final admissionKey = _offlineAdmission(request, kit);
    if (admissionKey != null &&
        (kit['checkedInAdmissions'] as List? ?? const []).contains(
          admissionKey,
        )) {
      return false;
    }
    final credential = _map(request['credential']);
    final type = credential['type']?.toString();
    if (type != 'checkout' && !_offlineAnswersComplete(request, kit)) {
      return false;
    }
    final roster = (kit['rosterIds'] as List? ?? const [])
        .map((value) => value.toString())
        .toSet();
    if (type == 'staff_roster') {
      final attendeeId = credential['attendeeId']?.toString();
      return roster.contains(attendeeId) &&
          ((kit['version'] as num? ?? 1) < 2 ||
              _map(kit['rosterAdmissions'])[attendeeId] != null);
    }
    if (type == 'staff_guest') {
      // New guests and staff overrides need current server eligibility.
      return false;
    }
    if (type == 'checkout') return true;
    if (type == 'attendance_pass') {
      final value =
          (credential['token'] ?? credential['value'])?.toString() ?? '';
      if (!value.startsWith('attendus_pass:v2:')) return false;
      final parts = value.substring('attendus_pass:v2:'.length).split('.');
      if (parts.length != 2) return false;
      try {
        final payload = _map(
          jsonDecode(
            utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))),
          ),
        );
        final key = _map(_map(kit['publicKeys'])[payload['kid']]);
        final admission = _map(_map(kit['passes'])[payload['id']]);
        if (key['revoked'] == true ||
            admission['status'] != 'active' ||
            payload['v'] != 2 ||
            admission['kind'] != payload['kind'] ||
            admission['credentialVersion'] != payload['cv'] ||
            (payload['exp'] as num? ?? 0) < observedAt.millisecondsSinceEpoch) {
          return false;
        }
        return await Ed25519().verify(
          utf8.encode(parts[0]),
          signature: Signature(
            base64Url.decode(base64Url.normalize(parts[1])),
            publicKey: SimplePublicKey(
              base64Url.decode(
                base64Url.normalize(key['publicKey'].toString()),
              ),
              type: KeyPairType.ed25519,
            ),
          ),
        );
      } catch (_) {
        return false;
      }
    }
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
          roster.contains(payload['u']) &&
          ((kit['version'] as num? ?? 1) < 2 ||
              _map(kit['rosterAdmissions'])[payload['u']] != null) &&
          observed != null &&
          !expiry.isBefore(observed.toUtc());
    } catch (_) {
      return false;
    }
  }

  bool _offlineAnswersComplete(
    Map<String, dynamic> request,
    Map<String, dynamic> kit,
  ) {
    final credential = _map(request['credential']);
    final answers = <String>[
      ...(request['answers'] as List? ?? const []).map(
        (answer) => answer.toString(),
      ),
    ];
    try {
      List<dynamic> cached = const [];
      if (credential['type'] == 'staff_roster') {
        cached =
            _map(kit['rosterAnswers'])[credential['attendeeId']] as List? ??
            const [];
      } else if (credential['type'] == 'personal_pass' &&
          credential['ticketCode'] != null) {
        for (final ticket
            in (kit['tickets'] as List? ?? const []).whereType<Map>()) {
          if (ticket['ticketCode'] == credential['ticketCode']) {
            cached = ticket['answers'] as List? ?? const [];
          }
        }
      } else if (credential['type'] == 'personal_pass' ||
          credential['type'] == 'attendance_pass') {
        final value = (credential['token'] ?? credential['value']).toString();
        final encoded = value
            .replaceFirst(RegExp(r'^attendus_pass:v[12]:'), '')
            .split('.')
            .first;
        final payload = _map(
          jsonDecode(
            utf8.decode(base64Url.decode(base64Url.normalize(encoded))),
          ),
        );
        cached = credential['type'] == 'attendance_pass'
            ? _map(_map(kit['passes'])[payload['id']])['answers'] as List? ??
                  const []
            : _map(kit['rosterAnswers'])[payload['u']] as List? ?? const [];
      }
      answers.addAll(cached.map((answer) => answer.toString()));
    } catch (_) {
      return false;
    }
    return (kit['questions'] as List? ?? const [])
        .whereType<Map>()
        .where(isRequiredCheckInQuestion)
        .every((question) => hasCheckInAnswer(question, answers));
  }

  String? _offlineAdmission(
    Map<String, dynamic> request,
    Map<String, dynamic> kit,
  ) {
    final credential = _map(request['credential']);
    try {
      final roster = _map(kit['rosterAdmissions']);
      if (credential['type'] == 'personal_pass') {
        final ticketCode = credential['ticketCode']?.toString();
        if (ticketCode != null && ticketCode.isNotEmpty) {
          for (final ticket
              in (kit['tickets'] as List? ?? const []).whereType<Map>()) {
            if (ticket['ticketCode'] == ticketCode) {
              return ticket['admissionKey']?.toString() ??
                  'ticket:${ticket['id']}';
            }
          }
          return null;
        }
        final token = (credential['token'] ?? credential['value'])
            .toString()
            .replaceFirst('attendus_pass:v1:', '')
            .split('.')
            .first;
        final payload = _map(
          jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(token)))),
        );
        return roster[payload['u']]?.toString() ?? payload['u']?.toString();
      }
      if (credential['type'] != 'attendance_pass') {
        final attendeeId = credential['attendeeId']?.toString();
        return roster[attendeeId]?.toString() ?? attendeeId;
      }
      final value = (credential['token'] ?? credential['value']).toString();
      final encoded = value
          .substring('attendus_pass:v2:'.length)
          .split('.')
          .first;
      final payload = _map(
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(encoded)))),
      );
      return _map(
        _map(kit['passes'])[payload['id']],
      )['admissionKey']?.toString();
    } catch (_) {
      return null;
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
