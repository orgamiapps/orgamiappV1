import 'dart:async';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/Services/onboarding_profile_service.dart';
import 'package:attendus/screens/Authentication/create_account/create_account_view_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/auth_fakes.dart';

class SignupAuth extends TestFirebaseAuth {
  int creations = 0;
  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    creations++;
    changeUser(TestAuthUser('a'));
    return TestUserCredential(user);
  }
}

CustomerModel customer(String uid) => CustomerModel(
  uid: uid,
  name: uid,
  email: '$uid@example.test',
  createdAt: DateTime(2026),
);
CreateAccountViewModel model(
  SignupAuth auth, {
  Future<CustomerModel> Function(CustomerModel)? save,
}) =>
    CreateAccountViewModel(
      auth: auth,
      usernameAvailable: (_) async => true,
      saveProfile: save ?? (c) async => c,
      ensureProfile: (_) async {},
      completeSession: () async {},
      showMessage: (_) {},
    )..setBasicInfo(
      firstName: 'Test',
      lastName: 'User',
      username: 'testuser',
      email: 'a@example.test',
    );
void main() {
  tearDown(() => CustomerController.logeInCustomer = null);
  test('signup completion cannot replace a switched account', () async {
    final auth = SignupAuth();
    final pending = Completer<CustomerModel>();
    final vm = model(auth, save: (_) => pending.future);
    final result = vm.createAccount('password');
    await Future<void>.delayed(Duration.zero);
    auth.changeUser(TestAuthUser('b'));
    CustomerController.logeInCustomer = customer('b');
    pending.complete(customer('a'));
    expect(await result, isFalse);
    expect(CustomerController.logeInCustomer?.uid, 'b');
    vm.dispose();
    await auth.changes.close();
  });
  test('disposed signup does not notify or install delayed profile', () async {
    final auth = SignupAuth();
    final pending = Completer<CustomerModel>();
    final vm = model(auth, save: (_) => pending.future);
    var notifications = 0;
    vm.addListener(() => notifications++);
    final result = vm.createAccount('password');
    await Future<void>.delayed(Duration.zero);
    vm.dispose();
    final before = notifications;
    pending.complete(customer('a'));
    expect(await result, isFalse);
    expect(notifications, before);
    expect(CustomerController.logeInCustomer, isNull);
    await auth.changes.close();
  });
  test(
    'signup retry resumes its created Auth account after profile failure',
    () async {
      final auth = SignupAuth();
      var saves = 0;
      final vm = model(
        auth,
        save: (c) async {
          if (++saves == 1) throw StateError('offline');
          return c;
        },
      );
      expect(await vm.createAccount('password'), isFalse);
      expect(await vm.createAccount('password'), isTrue);
      expect(auth.creations, 1);
      expect(CustomerController.logeInCustomer?.uid, 'a');
      vm.dispose();
      await auth.changes.close();
    },
  );
  test('concurrent signup submissions create only one Auth account', () async {
    final auth = SignupAuth();
    final pending = Completer<CustomerModel>();
    final vm = model(auth, save: (_) => pending.future);
    final first = vm.createAccount('password');
    expect(await vm.createAccount('password'), isFalse);
    await Future<void>.delayed(Duration.zero);
    pending.complete(customer('a'));
    expect(await first, isTrue);
    expect(auth.creations, 1);
    vm.dispose();
    await auth.changes.close();
  });
  test(
    'a failed signup retry cannot replace a different signed-in account',
    () async {
      final auth = SignupAuth();
      final vm = model(auth, save: (_) async => throw StateError('offline'));
      expect(await vm.createAccount('password'), isFalse);
      auth.changeUser(TestAuthUser('b'));
      expect(await vm.createAccount('password'), isFalse);
      expect(auth.currentUser?.uid, 'b');
      expect(auth.creations, 1);
      vm.dispose();
      await auth.changes.close();
    },
  );
  test(
    'signup retry cannot store a different email than the created Auth account',
    () async {
      final auth = SignupAuth();
      var saves = 0;
      final vm = model(
        auth,
        save: (_) async {
          saves++;
          throw StateError('offline');
        },
      );
      expect(await vm.createAccount('password'), isFalse);
      vm.email = 'other@example.test';
      expect(await vm.createAccount('password'), isFalse);
      expect(saves, 1);
      expect(auth.creations, 1);
      vm.dispose();
      await auth.changes.close();
    },
  );
  test(
    'professional profile fields are persisted before updating local state',
    () async {
      CustomerController.logeInCustomer = customer('a');
      Map<String, dynamic>? saved;
      final service = OnboardingProfileService(
        currentUid: () => 'a',
        saveFields: (uid, fields) async {
          expect(uid, 'a');
          saved = fields;
        },
      );
      await service.save({
        'occupation': 'Teacher',
        'company': 'School',
        'bio': 'Hello',
      }, expectedUid: 'a');
      expect(saved, {
        'occupation': 'Teacher',
        'company': 'School',
        'bio': 'Hello',
      });
      expect(CustomerController.logeInCustomer?.occupation, 'Teacher');
      expect(CustomerController.logeInCustomer?.bio, 'Hello');
    },
  );
  test('late photo persistence never changes the next account photo', () async {
    String uid = 'a';
    CustomerController.logeInCustomer = customer(uid);
    final pending = Completer<void>();
    final service = OnboardingProfileService(
      currentUid: () => uid,
      saveFields: (_, _) => pending.future,
    );
    final save = service.save({
      'profilePictureUrl': 'private-a',
    }, expectedUid: 'a');
    uid = 'b';
    CustomerController.logeInCustomer = customer(uid);
    pending.complete();
    await expectLater(save, throwsStateError);
    expect(CustomerController.logeInCustomer?.profilePictureUrl, isNull);
  });
}
