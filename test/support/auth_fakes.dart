import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TestSecureStorage extends FlutterSecureStorage {
  Future<void> Function(String key, String? value)? beforeWrite;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await beforeWrite?.call(key, value);
    return super.write(key: key, value: value);
  }
}

class TestAuthUser extends Fake implements User {
  TestAuthUser(this.uid, {this.isAnonymous = false});
  @override
  final String uid;
  @override
  final bool isAnonymous;
  @override
  String get displayName => 'Name $uid';
  @override
  String get email => '$uid@example.test';
  @override
  String? get photoURL => null;
}

class TestUserCredential extends Fake implements UserCredential {
  TestUserCredential(this.user);
  @override
  final User? user;
}

class TestFirebaseAuth extends Fake implements FirebaseAuth {
  User? user;
  final changes = StreamController<User?>.broadcast(sync: true);
  Future<UserCredential> Function()? anonymousSignIn;
  Future<UserCredential> Function()? emailSignIn;
  int anonymousCalls = 0;

  @override
  User? get currentUser => user;

  @override
  Stream<User?> authStateChanges() => changes.stream;

  void changeUser(User? next) {
    user = next;
    changes.add(next);
  }

  @override
  Future<UserCredential> signInAnonymously() {
    anonymousCalls++;
    return anonymousSignIn!();
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) => emailSignIn!();

  @override
  Future<void> signOut() async => changeUser(null);
}
