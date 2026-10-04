import 'dart:async';

import 'package:attendus/Services/guest_mode_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/auth_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestFirebaseAuth auth;
  late GuestModeService service;
  late TestSecureStorage storage;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    auth = TestFirebaseAuth();
    storage = TestSecureStorage();
    service = GuestModeService.forTesting(auth: auth, storage: storage);
  });
  tearDown(() async {
    service.dispose();
    await auth.changes.close();
  });

  test(
    'concurrent anonymous failures reach every caller and allow retry',
    () async {
      final attempt = Completer<UserCredential>();
      auth.anonymousSignIn = () => attempt.future;
      final first = service.ensureGuestSession();
      final second = service.ensureGuestSession();
      expect(identical(first, second), isTrue);
      expect(auth.anonymousCalls, 1);
      final failure = FirebaseAuthException(code: 'network-request-failed');
      final checks = [
        expectLater(first, throwsA(same(failure))),
        expectLater(second, throwsA(same(failure))),
      ];
      attempt.completeError(failure);
      await Future.wait(checks);
      expect(service.isEnsuringGuestSession, isFalse);

      final guest = TestAuthUser('guest', isAnonymous: true);
      auth.anonymousSignIn = () async {
        auth.changeUser(guest);
        return TestUserCredential(guest);
      };
      expect(await service.ensureGuestSession(), same(guest));
      expect(auth.anonymousCalls, 2);
      expect(service.guestSessionError, isNull);
    },
  );

  test(
    'late anonymous completion cannot replace the current full account',
    () async {
      final attempt = Completer<UserCredential>();
      auth.anonymousSignIn = () => attempt.future;
      final pending = service.ensureGuestSession();
      final account = TestAuthUser('account');
      auth.changeUser(account);
      attempt.complete(
        TestUserCredential(TestAuthUser('old', isAnonymous: true)),
      );
      expect(await pending, same(account));
      expect(service.isGuestMode, isFalse);
      expect(service.guestSessionId, isNull);
    },
  );

  test(
    'sign-out clears guest identity and does not promote anonymous users',
    () async {
      auth.user = TestAuthUser('guest', isAnonymous: true);
      await service.initialize();
      expect(service.guestSessionId, 'guest');
      await service.disableGuestMode();
      expect(service.isGuestMode, isTrue);
      auth.changeUser(null);
      expect(service.guestSessionId, isNull);
      expect(service.isGuestMode, isTrue);
    },
  );

  test('existing full account never starts anonymous authentication', () async {
    final account = TestAuthUser('account');
    auth.user = account;
    expect(await service.ensureGuestSession(), same(account));
    expect(auth.anonymousCalls, 0);
    expect(service.isGuestMode, isFalse);
  });

  test(
    'restricted browser storage does not turn successful guest auth into failure',
    () async {
      storage.beforeWrite = (_, _) async => throw StateError('storage blocked');
      final guest = TestAuthUser('guest', isAnonymous: true);
      auth.anonymousSignIn = () async {
        auth.changeUser(guest);
        return TestUserCredential(guest);
      };
      expect(await service.ensureGuestSession(), same(guest));
      expect(service.guestSessionId, 'guest');
      expect(service.guestSessionError, isNull);
    },
  );
}
