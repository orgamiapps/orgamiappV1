import 'dart:async';
import 'package:attendus/Services/web_auth_session.dart';
import 'package:attendus/Services/guest_mode_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/auth_fakes.dart';

class BrowserAuth extends TestFirebaseAuth {
  final initial = Completer<User?>();
  final persistence = Completer<void>();
  final redirect = Completer<UserCredential>();
  final calls = <String>[];
  Object? persistenceError;
  final persistenceErrors = <Persistence, Object>{};

  @override
  Future<void> setPersistence(Persistence value) async {
    calls.add('persistence:${value.name}');
    await persistence.future;
    if (persistenceErrors[value] != null) throw persistenceErrors[value]!;
    if (persistenceError != null) throw persistenceError!;
  }

  @override
  Future<UserCredential> getRedirectResult() {
    calls.add('redirect');
    return redirect.future;
  }

  @override
  Stream<User?> authStateChanges() => initial.future.asStream().map((value) {
    user = value;
    return value;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('slow persistence and redirect cannot create a competing guest', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final auth = BrowserAuth();
    final session = WebAuthSession(auth: auth, initialize: () async {});
    final guest = GuestModeService.forTesting(
      auth: auth,
      storage: TestSecureStorage(),
      restoreSession: session.ready,
    );
    var finished = false;
    final first = guest.ensureGuestSession().then((user) {
      finished = true;
      return user;
    });
    final second = guest.ensureGuestSession();
    await tester.pump(const Duration(seconds: 20));
    expect(finished, false);
    expect(auth.anonymousCalls, 0);
    expect(auth.calls, ['persistence:INDEXED_DB']);
    auth.persistence.complete();
    await tester.pump();
    expect(auth.calls, ['persistence:INDEXED_DB', 'redirect']);
    await tester.pump(const Duration(seconds: 60));
    expect(auth.anonymousCalls, 0);
    final user = TestAuthUser('restored');
    auth.redirect.complete(TestUserCredential(user));
    await tester.pump();
    expect(finished, false);
    auth.initial.complete(user);
    await tester.pump();
    expect((await first)?.uid, 'restored');
    expect((await second)?.uid, 'restored');
    expect(auth.anonymousCalls, 0);
    expect(session.takeRedirectResult()?.user?.uid, 'restored');
    expect(session.takeRedirectResult(), isNull);
    guest.dispose();
    await auth.changes.close();
  });

  test(
    'falls back to durable localStorage when IndexedDB is unavailable',
    () async {
      final auth = BrowserAuth()..persistence.complete();
      auth.persistenceErrors[Persistence.INDEXED_DB] = FirebaseAuthException(
        code: 'unsupported-persistence-type',
      );
      auth.redirect.complete(TestUserCredential(null));
      auth.initial.complete(null);
      final session = WebAuthSession(auth: auth, initialize: () async {});
      await session.ready();
      expect(auth.calls, [
        'persistence:INDEXED_DB',
        'persistence:LOCAL',
        'redirect',
      ]);
      expect(session.temporaryStorage.value, false);
      await auth.changes.close();
    },
  );

  test('restoration failure stays an error and can be retried', () async {
    final auth = BrowserAuth()..persistence.complete();
    auth.persistenceError = FirebaseAuthException(
      code: 'network-request-failed',
    );
    final session = WebAuthSession(auth: auth, initialize: () async {});
    await expectLater(session.ready(), throwsA(isA<FirebaseAuthException>()));
    expect(auth.anonymousCalls, 0);
    auth.persistenceError = null;
    auth.redirect.complete(TestUserCredential(null));
    auth.initial.complete(null);
    await session.ready();
    expect(auth.calls.where((c) => c == 'redirect').length, 1);
    await auth.changes.close();
  });

  test(
    'unsupported durable storage is surfaced without blocking temporary login',
    () async {
      final auth = BrowserAuth()..persistence.complete();
      auth.persistenceError = FirebaseAuthException(
        code: 'web-storage-unsupported',
      );
      auth.redirect.complete(TestUserCredential(null));
      auth.initial.complete(null);
      final session = WebAuthSession(auth: auth, initialize: () async {});
      await session.ready();
      expect(session.temporaryStorage.value, true);
      await auth.changes.close();
    },
  );

  test('redirect network failure cannot silently become signed out', () async {
    final auth = BrowserAuth()..persistence.complete();
    final session = WebAuthSession(auth: auth, initialize: () async {});
    final pending = session.ready();
    // Attach the expectation before delivering the failure.
    final checked = expectLater(pending, throwsA(isA<FirebaseAuthException>()));
    await Future<void>.delayed(Duration.zero);
    auth.redirect.completeError(
      FirebaseAuthException(code: 'network-request-failed'),
    );
    await checked;
    expect(auth.anonymousCalls, 0);
    await auth.changes.close();
  });
}
