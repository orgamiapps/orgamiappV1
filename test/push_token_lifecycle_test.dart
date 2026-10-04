import 'dart:async';
import 'dart:convert';

import 'package:attendus/Services/push_token_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> copy(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

class PushFixture {
  String? uid = 'account-a';
  Map<String, dynamic> stored = {
    'installationId': 'installation_00000000000000000001',
    'generation': 0,
  };
  int ids = 1;
  int deletes = 0;
  int cancelled = 0;
  final registered = <Map<String, dynamic>>[];
  final revoked = <Map<String, dynamic>>[];
  final errors = <Object>[];
  Future<String?> Function()? acquire;
  Future<void> Function()? deleting;
  Future<void> Function(Map<String, dynamic>)? registering;
  Future<void> Function(Map<String, dynamic>)? revoking;
  bool failPersistence = false;

  late final lifecycle = PushTokenLifecycle(
    currentUid: () => uid,
    readState: () async => copy(stored),
    writeState: (state) async {
      if (failPersistence) throw StateError('storage unavailable');
      stored = copy(state);
    },
    newInstallationId: () =>
        'installation_${(++ids).toString().padLeft(20, '0')}',
    acquireToken: () async =>
        acquire != null ? acquire!() : 'token-$uid-$deletes',
    deleteToken: () async {
      deletes++;
      if (deleting != null) await deleting!();
    },
    register: (intent) async {
      expect(stored['generation'], intent['generation']);
      registered.add(copy(intent));
      if (registering != null) await registering!(intent);
    },
    revoke: (intent) async {
      expect(stored['generation'], intent['generation']);
      revoked.add(copy(intent));
      if (revoking != null) await revoking!(intent);
    },
    clearNotifications: () async {
      cancelled++;
    },
    onError: errors.add,
    timeout: const Duration(milliseconds: 30),
  );
}

void main() {
  test(
    'persists ownership and generation before registering, including refresh',
    () async {
      final f = PushFixture();
      await f.lifecycle.synchronize();
      await f.lifecycle.tokenRefreshed('refreshed-token');
      expect(f.registered.map((value) => value['generation']), [1, 2]);
      expect(f.stored['binding']['uid'], 'account-a');
      expect(f.stored['binding']['token'], 'refreshed-token');
    },
  );

  test(
    'account changes during token acquisition never register the old result',
    () async {
      final f = PushFixture();
      final started = Completer<void>();
      final token = Completer<String?>();
      f.acquire = () {
        started.complete();
        return token.future;
      };
      final old = f.lifecycle.synchronize();
      await started.future;
      f.uid = 'account-b';
      f.acquire = () async => 'token-b';
      final next = f.lifecycle.synchronize();
      token.complete('token-a');
      await old;
      await next;
      expect(f.registered.length, 1);
      expect(f.registered.single['expectedUid'], 'account-b');
      expect(f.registered.single['token'], 'token-b');
    },
  );

  test(
    'in-flight old registration is superseded by a higher generation and rotated token',
    () async {
      final f = PushFixture();
      final started = Completer<void>();
      final response = Completer<void>();
      f.registering = (_) {
        started.complete();
        return response.future;
      };
      final old = f.lifecycle.synchronize();
      await started.future;
      f.uid = 'account-b';
      f.registering = null;
      final next = f.lifecycle.synchronize();
      response.complete();
      await old;
      await next;
      expect(f.registered.last['expectedUid'], 'account-b');
      expect(
        f.registered.last['generation'],
        greaterThan(f.registered.first['generation'] as int),
      );
      expect(f.registered.last['token'], isNot(f.registered.first['token']));
      expect(f.stored['binding']['uid'], 'account-b');
      expect(f.deletes, 1);
      expect(f.cancelled, 1);
    },
  );

  test('refresh cannot register for an unobserved new account', () async {
    final f = PushFixture();
    await f.lifecycle.synchronize();
    f.uid = 'account-b';
    await f.lifecycle.tokenRefreshed('late-old-token');
    expect(f.registered.length, 1);
  });

  test(
    'offline logout cancels local alerts and retains revocation for matching account',
    () async {
      final f = PushFixture();
      await f.lifecycle.synchronize();
      f.revoking = (_) async => throw StateError('offline');
      await f.lifecycle.clearForSignOut();
      expect(f.cancelled, 1);
      expect(f.deletes, 1);
      expect(f.stored['binding'], isNull);
      expect(f.stored['pendingRevocations'], hasLength(1));
      await f.lifecycle.tokenRefreshed('late-token');
      expect(f.registered.length, 1);
      f.uid = null;
      await f.lifecycle.synchronize();
      f.uid = 'account-a';
      f.revoking = null;
      await f.lifecycle.synchronize();
      expect(f.stored['pendingRevocations'], isEmpty);
      expect(f.revoked.last['expectedUid'], 'account-a');
      expect(
        f.registered.last['generation'],
        greaterThan(f.revoked.last['generation'] as int),
      );
    },
  );

  test('persistence failure cannot submit an unfenced registration', () async {
    final f = PushFixture()..failPersistence = true;
    await expectLater(f.lifecycle.synchronize(), throwsStateError);
    expect(f.registered, isEmpty);
  });

  test(
    'unfinished SDK token deletion fences registration after a bounded logout',
    () async {
      final f = PushFixture();
      await f.lifecycle.synchronize();
      final deletion = Completer<void>();
      f.deleting = () => deletion.future;
      await f.lifecycle.clearForSignOut();
      f.uid = 'account-b';
      await expectLater(
        f.lifecycle.synchronize(),
        throwsA(isA<TimeoutException>()),
      );
      expect(f.registered.length, 1);
      deletion.complete();
      await Future<void>.delayed(Duration.zero);
      f.deleting = null;
      await f.lifecycle.synchronize();
      expect(f.registered.last['expectedUid'], 'account-b');
    },
  );

  test(
    'installation conflict rotates token and identity before one bounded retry',
    () async {
      final f = PushFixture();
      f.registering = (_) async {
        if (f.registered.length == 1) throw PushInstallationReset();
      };
      await f.lifecycle.synchronize();
      expect(f.registered, hasLength(2));
      expect(
        f.registered.last['installationId'],
        isNot(f.registered.first['installationId']),
      );
      expect(
        f.registered.last['generation'],
        greaterThan(f.registered.first['generation'] as int),
      );
      expect(f.deletes, 1);
    },
  );

  test('denied permission acquires no push ownership', () async {
    final f = PushFixture()..acquire = (() async => null);
    await f.lifecycle.synchronize();
    expect(f.registered, isEmpty);
  });
}
