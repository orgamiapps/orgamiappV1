import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'artifact_download_service.dart';

class EventExportService {
  EventExportService({
    String? Function()? currentUid,
    Stream<String?> Function()? accountChanges,
    Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)? call,
    Future<http.Response> Function(Uri)? fetch,
    Future<ArtifactDownloadResult> Function(Uint8List, Rect?)? save,
    Future<void> Function(Duration)? delay,
  }) : _currentUid =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _accountChanges =
           accountChanges ??
           (() => FirebaseAuth.instance.authStateChanges().map(
             (user) => user?.uid,
           )),
       _call = call ?? _productionCall,
       _fetch = fetch ?? http.get,
       _save = save ?? _productionSave,
       _delay = delay ?? Future<void>.delayed;

  final String? Function() _currentUid;
  final Stream<String?> Function() _accountChanges;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  _call;
  final Future<http.Response> Function(Uri) _fetch;
  final Future<ArtifactDownloadResult> Function(Uint8List, Rect?) _save;
  final Future<void> Function(Duration) _delay;
  String? _job;
  String? _scope;
  String? _requestId;
  int _operation = 0;

  static Future<Map<String, dynamic>> _productionCall(
    String name,
    Map<String, dynamic> data,
  ) async => Map<String, dynamic>.from(
    (await FirebaseFunctions.instance
                .httpsCallable(name)
                .call(data)
                .timeout(const Duration(seconds: 120)))
            .data
        as Map,
  );

  static Future<ArtifactDownloadResult> _productionSave(
    Uint8List bytes,
    Rect? origin,
  ) => downloadArtifact(
    bytes,
    'attendus-roster.csv',
    'text/csv',
    sharePositionOrigin: origin,
  );

  Future<ArtifactDownloadResult> download(
    String eventId, {
    String attendanceStatus = 'all',
    String registrationStatus = 'all',
    String query = '',
    Rect? sharePositionOrigin,
  }) async {
    final uid = _currentUid();
    if (uid == null) throw StateError('Log in to export this event.');
    final operation = ++_operation;
    var accountChanged = false;
    final subscription = _accountChanges().listen((nextUid) {
      if (nextUid != uid) accountChanged = true;
    });
    void checkAccount() {
      if (accountChanged || _currentUid() != uid || operation != _operation) {
        throw StateError(
          'Your account changed. Reopen the export to continue.',
        );
      }
    }

    final scope = jsonEncode([
      uid,
      eventId,
      attendanceStatus,
      registrationStatus,
      query,
    ]);
    if (_scope != scope) {
      _job = null;
      _scope = scope;
      _requestId = null;
    }
    Future<Map<String, dynamic>> call(
      String name,
      Map<String, dynamic> data,
    ) async {
      checkAccount();
      final result = await _call(name, {'eventId': eventId, ...data});
      checkAccount();
      return result;
    }

    try {
      _requestId ??= const Uuid().v4();
      _job ??= (await call('createEventExportV2', {
        'attendanceStatus': attendanceStatus,
        'registrationStatus': registrationStatus,
        'query': query,
        'idempotencyKey': _requestId,
      }))['jobId'];
      for (var attempt = 0; attempt < 30; attempt++) {
        final result = await call('getEventExportV2', {'jobId': _job});
        if (result['status'] == 'failed') {
          _job = null;
          _requestId = null;
          throw StateError('Export failed. Please retry.');
        }
        if (result['status'] == 'complete') {
          checkAccount();
          final response = await _fetch(
            Uri.parse(result['url'] as String),
          ).timeout(const Duration(seconds: 60));
          checkAccount();
          if (response.statusCode != 200) {
            throw StateError('Download failed. Please retry.');
          }
          final outcome = await _save(
            Uint8List.fromList(response.bodyBytes),
            sharePositionOrigin,
          );
          checkAccount();
          _job = null;
          _requestId = null;
          return outcome;
        }
        await _delay(const Duration(seconds: 2));
        checkAccount();
      }
      throw StateError(
        'Export is still generating. Retry to retrieve the same job.',
      );
    } finally {
      await subscription.cancel();
      if (operation == _operation && (accountChanged || _currentUid() != uid)) {
        _job = null;
        _requestId = null;
        _scope = null;
      }
    }
  }
}
