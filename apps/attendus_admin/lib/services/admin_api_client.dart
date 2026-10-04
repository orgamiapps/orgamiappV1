import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/api_models.dart';

class AdminApiClient {
  AdminApiClient({
    FirebaseAuth? auth,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _auth = auth ?? FirebaseAuth.instance,
       _client = client ?? http.Client() {
    _uid = _auth.currentUser?.uid;
    _subscription = _auth.authStateChanges().listen(
      (user) => _updateUser(user?.uid),
    );
  }
  final FirebaseAuth _auth;
  final http.Client _client;
  final Duration requestTimeout;
  StreamSubscription<User?>? _subscription;
  String? _uid;
  int _epoch = 0;
  bool _disposed = false;
  // Preserve uncertain writes for an explicit identical retry, including after
  // sign-out/sign-in by the same actor. Never automatically repeat mutations.
  final Map<String, String> _pendingMutations = {};
  static const baseUrl = String.fromEnvironment(
    'ATTENDUS_ADMIN_API_URL',
    defaultValue:
        'https://us-central1-orgami-66nxok.cloudfunctions.net/adminApi',
  );

  void _updateUser(String? uid) {
    if (_uid == uid) return;
    _uid = uid;
    _epoch++;
  }

  void invalidateSession() => _epoch++;
  void _assertSession(String uid, int epoch) {
    _updateUser(_auth.currentUser?.uid);
    if (_disposed || uid != _uid || epoch != _epoch) {
      throw const ApiException(
        'SESSION_CHANGED',
        'The signed-in account changed. Refresh before continuing.',
      );
    }
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? mutation,
    String? idempotencyKey,
  }) async {
    _updateUser(_auth.currentUser?.uid);
    final user = _auth.currentUser;
    if (_disposed || user == null) {
      throw const ApiException('UNAUTHENTICATED', 'Please sign in again.');
    }
    final epoch = _epoch;
    final requestId = const Uuid().v4();
    final fingerprint = mutation == null
        ? null
        : jsonEncode([user.uid, path, _canonical(mutation)]);
    final key = fingerprint == null
        ? null
        : _pendingMutations.putIfAbsent(
            fingerprint,
            () => idempotencyKey ?? const Uuid().v4(),
          );
    var submitted = false;
    try {
      final token = await user.getIdToken(true).timeout(requestTimeout);
      _assertSession(user.uid, epoch);
      if (token == null || token.isEmpty) {
        throw const ApiException('UNAUTHENTICATED', 'Please sign in again.');
      }
      final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
      final headers = {
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
        'x-request-id': requestId,
        'idempotency-key': ?key,
      };
      submitted = mutation != null;
      final response =
          await (mutation == null
                  ? _client.get(uri, headers: headers)
                  : _client.post(
                      uri,
                      headers: headers,
                      body: jsonEncode(mutation),
                    ))
              .timeout(requestTimeout);
      _assertSession(user.uid, epoch);
      final decoded = _decode(response, requestId);
      if (mutation != null) requireApiObject(decoded['data']);
      if (fingerprint != null) _pendingMutations.remove(fingerprint);
      return decoded;
    } on TimeoutException {
      throw _transportError('REQUEST_TIMEOUT', submitted, requestId, key);
    } on IOException {
      throw _transportError('NETWORK_ERROR', submitted, requestId, key);
    } on http.ClientException {
      throw _transportError('NETWORK_ERROR', submitted, requestId, key);
    } on FirebaseAuthException {
      _assertSession(user.uid, epoch);
      throw const ApiException('UNAUTHENTICATED', 'Please sign in again.');
    } on ApiException catch (error) {
      final unknown =
          submitted &&
          (error.code == 'SESSION_CHANGED' ||
              error.code == 'INVALID_RESPONSE' ||
              error.code == 'REQUEST_IN_PROGRESS' ||
              error.code == 'OPERATION_REVIEW_REQUIRED' ||
              (error.status ?? 0) >= 500);
      if (fingerprint != null && !unknown) {
        _pendingMutations.remove(fingerprint);
      }
      throw ApiException(
        error.code,
        unknown && error.code != 'OPERATION_REVIEW_REQUIRED'
            ? '${error.message} The change may have completed. Retry the same action to check its result.'
            : error.message,
        requestId: error.requestId ?? requestId,
        status: error.status,
        idempotencyKey: key,
        outcomeUnknown: unknown,
      );
    }
  }

  ApiException _transportError(
    String code,
    bool submitted,
    String requestId,
    String? key,
  ) => ApiException(
    code,
    submitted
        ? 'The result could not be confirmed. The change may have completed. Retry the same action to check its result.'
        : code == 'REQUEST_TIMEOUT'
        ? 'The request timed out. Please retry.'
        : 'The Admin API could not be reached. Check your connection and retry.',
    requestId: requestId,
    idempotencyKey: key,
    outcomeUnknown: submitted,
  );

  static Object? _canonical(Object? value) {
    if (value is Map<String, dynamic>) {
      return {
        for (final key in value.keys.toList()..sort())
          key: _canonical(value[key]),
      };
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
  }) => _request(path, query: query);
  Future<Map<String, dynamic>> postMutation(
    String path, {
    required String reason,
    required bool confirmed,
    Map<String, dynamic> values = const {},
    String? idempotencyKey,
  }) => _request(
    path,
    mutation: {...values, 'reason': reason, 'confirmed': confirmed},
    idempotencyKey: idempotencyKey,
  );

  Map<String, dynamic> _decode(http.Response response, String requestId) {
    Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      // Reverse proxies can return HTML or an empty response on failure.
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final raw = body is Map<String, dynamic> ? body['error'] : null;
      final error = raw is Map<String, dynamic>
          ? raw
          : const <String, dynamic>{};
      throw ApiException(
        error['code'] is String ? error['code'] as String : 'HTTP_ERROR',
        error['message'] is String
            ? error['message'] as String
            : 'The Admin API request failed. Please retry.',
        requestId:
            error['requestId']?.toString() ??
            response.headers['x-request-id'] ??
            requestId,
        status: response.statusCode,
      );
    }
    if (body is! Map<String, dynamic> ||
        !body.containsKey('data') ||
        (body['meta'] != null && body['meta'] is! Map<String, dynamic>)) {
      throw ApiException(
        'INVALID_RESPONSE',
        'The Admin API returned an invalid response. Please retry.',
        requestId: response.headers['x-request-id'] ?? requestId,
        status: response.statusCode,
      );
    }
    return body;
  }

  Future<AdminPage> page(
    String path, {
    String? search,
    String? pageToken,
    int limit = 25,
  }) async {
    final response = await getJson(
      path,
      query: {
        'limit': '$limit',
        if (search?.isNotEmpty == true) 'search': search!,
        'pageToken': ?pageToken,
      },
    );
    final data = response['data'];
    final token = (response['meta'] as Map<String, dynamic>?)?['nextPageToken'];
    if (data is! List ||
        data.any((row) => row is! Map<String, dynamic>) ||
        (token != null && token is! String)) {
      throw const ApiException(
        'INVALID_RESPONSE',
        'The Admin API returned an invalid page. Please retry.',
      );
    }
    return AdminPage(
      items: data.cast<Map<String, dynamic>>(),
      nextPageToken: token as String?,
    );
  }

  void dispose() {
    _disposed = true;
    _epoch++;
    _subscription?.cancel();
    _client.close();
  }
}
