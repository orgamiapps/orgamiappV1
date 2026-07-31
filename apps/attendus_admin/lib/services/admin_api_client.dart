import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/api_models.dart';

class AdminApiClient {
  AdminApiClient({FirebaseAuth? auth, http.Client? client})
    : _auth = auth ?? FirebaseAuth.instance,
      _client = client ?? http.Client();
  final FirebaseAuth _auth;
  final http.Client _client;
  static const baseUrl = String.fromEnvironment(
    'ATTENDUS_ADMIN_API_URL',
    defaultValue:
        'https://us-central1-orgami-66nxok.cloudfunctions.net/adminApi',
  );
  Future<Map<String, String>> _headers({String? idempotencyKey}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const ApiException('UNAUTHENTICATED', 'Please sign in again.');
    }
    final token = await user.getIdToken(true);
    return {
      'authorization': 'Bearer $token',
      'content-type': 'application/json',
      'x-request-id': const Uuid().v4(),
      'idempotency-key': ?idempotencyKey,
    };
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    try {
      return _decode(await _client.get(uri, headers: await _headers()));
    } on SocketException {
      throw const ApiException(
        'NETWORK_ERROR',
        'Attendus Admin is offline. Check your connection and retry.',
      );
    } on http.ClientException {
      throw const ApiException(
        'NETWORK_ERROR',
        'The Admin API could not be reached.',
      );
    }
  }

  Future<Map<String, dynamic>> postMutation(
    String path, {
    required String reason,
    required bool confirmed,
    Map<String, dynamic> values = const {},
    String? idempotencyKey,
  }) async {
    try {
      return _decode(
        await _client.post(
          Uri.parse('$baseUrl$path'),
          headers: await _headers(
            idempotencyKey: idempotencyKey ?? const Uuid().v4(),
          ),
          body: jsonEncode({
            ...values,
            'reason': reason,
            'confirmed': confirmed,
          }),
        ),
      );
    } on SocketException {
      throw const ApiException(
        'NETWORK_ERROR',
        'Attendus Admin is offline. No change was submitted.',
      );
    } on http.ClientException {
      throw const ApiException(
        'NETWORK_ERROR',
        'The Admin API could not be reached.',
      );
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = body['error'] as Map<String, dynamic>? ?? const {};
      throw ApiException(
        error['code']?.toString() ?? 'HTTP_ERROR',
        error['message']?.toString() ?? 'Request failed.',
        requestId: error['requestId']?.toString(),
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
    final data = (response['data'] as List? ?? const [])
        .cast<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
    return AdminPage(
      items: data,
      nextPageToken:
          (response['meta'] as Map<String, dynamic>?)?['nextPageToken']
              ?.toString(),
    );
  }
}
