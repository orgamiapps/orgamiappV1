import 'dart:async';

import 'package:attendus/Services/auth_service.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/auth_fakes.dart';

CustomerModel profile(String uid) => CustomerModel(
  uid: uid,
  name: 'Profile $uid',
  email: '$uid@example.test',
  createdAt: DateTime(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestFirebaseAuth auth;
  late AuthService service;
  late TestSecureStorage storage;
  late Future<CustomerModel?> Function(String) load;
  int saved = 0;

  setUp(() {
    CustomerController.logeInCustomer = null;
    FlutterSecureStorage.setMockInitialValues({});
    saved = 0;
    auth = TestFirebaseAuth();
    storage = TestSecureStorage();
    load = (uid) async => profile(uid);
    service = AuthService.forTesting(
      auth: auth,
      storage: storage,
      loadCustomer: (uid) => load(uid),
      initializeFirebase: () async {},
      onAuthenticatedSession: () async {
        saved++;
      },
      onLogout: () async {},
    );
  });
  tearDown(() async {
    service.dispose();
    CustomerController.logeInCustomer = null;
    await auth.changes.close();
  });

  test(
    'anonymous authentication never grants full-account UI access',
    () async {
      auth.user = TestAuthUser('guest', isAnonymous: true);
      expect(await service.ensureInMemoryUserModel(), isFalse);
      expect(await service.ensureUserDataLoaded(), isFalse);
      expect(service.isLoggedIn, isFalse);
      expect(CustomerController.logeInCustomer, isNull);
      expect(saved, 0);
    },
  );

  test(
    'account switch replaces the old profile before storage completes',
    () async {
      auth.user = TestAuthUser('b');
      CustomerController.logeInCustomer = profile('a');
      expect(service.isLoggedIn, isFalse);
      final pending = service.ensureInMemoryUserModel();
      expect(CustomerController.logeInCustomer?.uid, 'b');
      expect(await pending, isTrue);
      expect(service.isLoggedIn, isTrue);
    },
  );

  test(
    'delayed profile refresh cannot overwrite a different account',
    () async {
      auth.user = TestAuthUser('a');
      final request = Completer<CustomerModel?>();
      load = (_) => request.future;
      final pending = service.refreshUserData();
      auth.changeUser(TestAuthUser('b'));
      CustomerController.logeInCustomer = profile('b');
      request.complete(profile('a'));
      expect(await pending, isFalse);
      expect(CustomerController.logeInCustomer?.uid, 'b');
    },
  );

  test(
    'delayed initial profile cannot resurrect a signed-out account',
    () async {
      auth.user = TestAuthUser('a');
      final request = Completer<CustomerModel?>();
      load = (_) => request.future;
      final pending = service.ensureUserDataLoaded();
      auth.changeUser(null);
      request.complete(profile('a'));
      expect(await pending, isFalse);
      expect(CustomerController.logeInCustomer, isNull);
    },
  );

  test(
    'email login with unreadable profile keeps local fallback without Firebase writes',
    () async {
      load = (_) async => null;
      auth.emailSignIn = () async {
        final account = TestAuthUser('a');
        auth.changeUser(account);
        return TestUserCredential(account);
      };
      expect(
        await service.signInWithEmailAndPassword('a@example.test', 'pw'),
        isNotNull,
      );
      await Future<void>.delayed(Duration.zero);
      // No Firebase app is initialized in this test. A profile write would fail
      // before the successful session callback, exposing the old overwrite path.
      expect(saved, 1);
      expect(CustomerController.logeInCustomer?.uid, 'a');
    },
  );

  test(
    'sign-out clears private in-memory data synchronously with auth event',
    () async {
      auth.user = TestAuthUser('a');
      await service.initialize();
      expect(CustomerController.logeInCustomer?.uid, 'a');
      auth.changeUser(null);
      expect(CustomerController.logeInCustomer, isNull);
      expect(service.isLoggedIn, isFalse);
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'queued storage work cannot erase or mix the next account session',
    () async {
      auth.user = TestAuthUser('a');
      await service.initialize();
      final gate = Completer<void>();
      final started = Completer<void>();
      storage.beforeWrite = (key, value) async {
        if (key == 'user_id' && value == 'b') {
          started.complete();
          await gate.future;
        }
      };
      auth.changeUser(TestAuthUser('b'));
      await started.future;
      auth.changeUser(null);
      auth.changeUser(TestAuthUser('c'));
      expect(CustomerController.logeInCustomer?.uid, 'c');
      gate.complete();
      await service.ensureInMemoryUserModel();
      await Future<void>.delayed(Duration.zero);
      expect(await storage.read(key: 'user_id'), 'c');
      expect(await storage.read(key: 'user_email'), 'c@example.test');
      expect(CustomerController.logeInCustomer?.uid, 'c');
    },
  );
}
