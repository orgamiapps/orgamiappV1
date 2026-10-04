import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:attendus_admin/models/api_models.dart';
import 'package:attendus_admin/services/admin_api_client.dart';
import 'package:attendus_admin/services/session_controller.dart';

class TestUser extends Fake implements User {
  TestUser(this.uid, {this.token});
  @override
  final String uid;
  final Future<String?> Function()? token;
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async =>
      token == null ? 'test-token-$uid' : token!();
}

class TestAuth extends Fake implements FirebaseAuth {
  TestAuth(this.currentUser);
  @override
  User? currentUser;
  final changes = StreamController<User?>.broadcast(sync: true);
  @override
  Stream<User?> authStateChanges() => changes.stream;
  void change(User? value) {
    currentUser = value;
    changes.add(value);
  }

  @override
  Future<void> signOut() async => change(null);
}

void main() {
  late TestAuth auth;
  late AdminApiClient api;
  setUp(() => auth = TestAuth(TestUser('admin-a')));
  tearDown(() async {
    api.dispose();
    await auth.changes.close();
  });
  AdminApiClient client(
    Future<http.Response> Function(http.Request) handler, {
    Duration timeout = const Duration(seconds: 1),
  }) => api = AdminApiClient(
    auth: auth,
    client: MockClient(handler),
    requestTimeout: timeout,
  );
  Future<Map<String, dynamic>> mutate({
    Map<String, dynamic> values = const {},
  }) => api.postMutation(
    '/v1/accounts/fixture/disable',
    reason: 'Owned fixture regression',
    confirmed: true,
    values: values,
  );
  Matcher code(String code) =>
      isA<ApiException>().having((error) => error.code, 'code', code);

  test('normalizes HTML, empty, array and malformed error responses', () async {
    final responses = [
      http.Response('<html>upstream unavailable</html>', 502),
      http.Response('', 200),
      http.Response('[]', 200),
      http.Response('{"error":[]}', 403),
    ];
    client((_) async => responses.removeAt(0));
    await expectLater(api.getJson('/v1/me'), throwsA(code('HTTP_ERROR')));
    await expectLater(api.getJson('/v1/me'), throwsA(code('INVALID_RESPONSE')));
    await expectLater(api.getJson('/v1/me'), throwsA(code('INVALID_RESPONSE')));
    await expectLater(
      api.getJson('/v1/me'),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
    );
  });
  test('validates page rows and continuation token', () async {
    final bodies = [
      {
        'data': [1],
      },
      {
        'data': [],
        'meta': {'nextPageToken': 7},
      },
      {'data': null},
    ];
    client((_) async => http.Response(jsonEncode(bodies.removeAt(0)), 200));
    for (var i = 0; i < 3; i++) {
      await expectLater(
        api.page('/v1/accounts'),
        throwsA(code('INVALID_RESPONSE')),
      );
    }
  });
  test('times out token acquisition without sending a late mutation', () async {
    final token = Completer<String?>();
    auth.change(TestUser('admin-a', token: () => token.future));
    var sends = 0;
    client((_) async {
      sends++;
      return http.Response('{"data":{}}', 200);
    }, timeout: const Duration(milliseconds: 10));
    await expectLater(
      mutate(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'REQUEST_TIMEOUT')
            .having((e) => e.outcomeUnknown, 'unknown', false),
      ),
    );
    token.complete('late-token');
    await Future<void>.delayed(Duration.zero);
    expect(sends, 0);
  });
  test(
    'explicit retry reuses uncertain key and does not repeat automatically',
    () async {
      final keys = <String?>[];
      final requestIds = <String?>[];
      final first = Completer<http.Response>();
      client((request) async {
        keys.add(request.headers['idempotency-key']);
        requestIds.add(request.headers['x-request-id']);
        return keys.length == 1
            ? first.future
            : http.Response('{"data":{"completed":true}}', 200);
      }, timeout: const Duration(milliseconds: 10));
      await expectLater(
        mutate(values: {'b': 2, 'a': 1}),
        throwsA(
          isA<ApiException>().having((e) => e.outcomeUnknown, 'unknown', true),
        ),
      );
      expect(keys, hasLength(1));
      await mutate(values: {'a': 1, 'b': 2});
      expect(keys[1], keys[0]);
      expect(requestIds[1], isNot(requestIds[0]));
      first.complete(http.Response('{"data":{"completed":true}}', 200));
      await mutate(values: {'a': 1, 'b': 2});
      expect(keys[2], isNot(keys[1]));
    },
  );
  test(
    'operator-review responses retain uncertain key without claiming failure',
    () async {
      final keys = <String?>[];
      client((request) async {
        keys.add(request.headers['idempotency-key']);
        return http.Response(
          '{"error":{"code":"OPERATION_REVIEW_REQUIRED","message":"Review the operation before continuing."}}',
          409,
        );
      });
      for (var i = 0; i < 2; i++) {
        await expectLater(
          mutate(),
          throwsA(
            isA<ApiException>()
                .having((e) => e.outcomeUnknown, 'unknown', true)
                .having(
                  (e) => e.message,
                  'message',
                  isNot(contains('Retry the same')),
                ),
          ),
        );
      }
      expect(keys[0], keys[1]);
    },
  );
  test(
    'account change before token resolution never submits old action',
    () async {
      final token = Completer<String?>();
      auth.change(TestUser('admin-a', token: () => token.future));
      var sends = 0;
      client((_) async {
        sends++;
        return http.Response('{"data":{}}', 200);
      });
      final pending = mutate();
      final result = expectLater(pending, throwsA(code('SESSION_CHANGED')));
      auth.change(TestUser('admin-b'));
      token.complete('old-token');
      await result;
      expect(sends, 0);
    },
  );
  test('rejects responses across logout and same-user login', () async {
    final response = Completer<http.Response>();
    client((_) => response.future);
    final pending = api.getJson('/v1/accounts');
    final result = expectLater(pending, throwsA(code('SESSION_CHANGED')));
    await Future<void>.delayed(Duration.zero);
    auth.change(null);
    auth.change(TestUser('admin-a'));
    response.complete(http.Response('{"data":[{"uid":"private"}]}', 200));
    await result;
  });
  test(
    'access refresh cannot authorize signed-out or superseded sessions',
    () async {
      final responses = <Completer<http.Response>>[];
      client((_) {
        final response = Completer<http.Response>();
        responses.add(response);
        return response.future;
      });
      final session = SessionController(auth: auth, api: api);
      addTearDown(session.dispose);
      final first = session.refreshAccess();
      await Future<void>.delayed(Duration.zero);
      auth.change(null);
      expect(session.status, SessionStatus.signedOut);
      responses[0].complete(
        http.Response('{"data":{"roles":["super_admin"]}}', 200),
      );
      await first;
      expect(session.status, SessionStatus.signedOut);
      expect(session.permissions.roles, isEmpty);
    },
  );
  test(
    'malformed successful mutation response keeps its retry identity',
    () async {
      final keys = <String?>[];
      client((request) async {
        keys.add(request.headers['idempotency-key']);
        return http.Response(
          keys.length == 1 ? '{"data":true}' : '{"data":{"ok":true}}',
          200,
        );
      });
      await expectLater(
        mutate(),
        throwsA(
          isA<ApiException>().having((e) => e.outcomeUnknown, 'unknown', true),
        ),
      );
      await mutate();
      expect(keys[1], keys[0]);
    },
  );

  test(
    'late access refresh cannot replace newer roles for the same actor',
    () async {
      final responses = <Completer<http.Response>>[];
      client((_) {
        final response = Completer<http.Response>();
        responses.add(response);
        return response.future;
      });
      final session = SessionController(auth: auth, api: api);
      addTearDown(session.dispose);
      final first = session.refreshAccess();
      await Future<void>.delayed(Duration.zero);
      final second = session.refreshAccess();
      await Future<void>.delayed(Duration.zero);
      responses[1].complete(
        http.Response('{"data":{"roles":["analyst"]}}', 200),
      );
      await second;
      expect(session.permissions.isSuperAdmin, isFalse);
      responses[0].complete(
        http.Response('{"data":{"roles":["super_admin"]}}', 200),
      );
      await first;
      expect(session.status, SessionStatus.authorized);
      expect(session.permissions.isSuperAdmin, isFalse);
    },
  );

  test('TLS failure cannot claim that a mutation was not submitted', () async {
    client(
      (_) async => throw const HandshakeException('Connection interrupted'),
    );
    await expectLater(
      mutate(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'NETWORK_ERROR')
            .having((e) => e.outcomeUnknown, 'unknown', true)
            .having(
              (e) => e.message,
              'message',
              isNot(contains('No change was submitted')),
            ),
      ),
    );
  });

  test(
    'malformed access details fail closed and clear old permissions',
    () async {
      var calls = 0;
      client(
        (_) async => http.Response(
          ++calls == 1
              ? '{"data":{"roles":["super_admin"]}}'
              : '{"data":{"roles":true}}',
          200,
        ),
      );
      final session = SessionController(auth: auth, api: api);
      addTearDown(session.dispose);
      await session.refreshAccess();
      expect(session.permissions.isSuperAdmin, isTrue);
      await session.refreshAccess();
      expect(session.status, SessionStatus.error);
      expect(session.permissions.roles, isEmpty);
    },
  );
}
