import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:attendus/Services/firebase_initializer.dart';

/// One barrier for browser persistence, OAuth return, and stored auth hydration.
/// A slow operation stays pending; it must never be interpreted as signed out.
class WebAuthSession {
  WebAuthSession({
    required this.auth,
    required this.initialize,
    this.isWeb = true,
  });

  static WebAuthSession? _instance;
  static WebAuthSession get instance => _instance ??= WebAuthSession(
    auth: FirebaseAuth.instance,
    initialize: FirebaseInitializer.initializeOnce,
    isWeb: kIsWeb,
  );

  final FirebaseAuth auth;
  final Future<void> Function() initialize;
  final bool isWeb;
  final ValueNotifier<bool> temporaryStorage = ValueNotifier(false);
  Future<void>? _pending;
  UserCredential? _redirect;

  Future<void> ready() => _pending ??= _restore();

  Future<void> _restore() async {
    try {
      await initialize();
      if (isWeb) {
        try {
          // Match FlutterFire's default durable backend. Switching every tab
          // from IndexedDB to localStorage disrupts cross-tab session updates.
          try {
            await auth.setPersistence(Persistence.INDEXED_DB);
          } on FirebaseAuthException catch (error) {
            if (!_storageUnavailable(error)) rethrow;
            await auth.setPersistence(Persistence.LOCAL);
          }
          temporaryStorage.value = false;
        } on FirebaseAuthException catch (error) {
          if (!_storageUnavailable(error)) rethrow;
          temporaryStorage.value = true;
        }
        try {
          _redirect = await auth.getRedirectResult();
        } on FirebaseAuthException catch (error) {
          // Cancellation does not invalidate an existing stored session.
          if (auth.currentUser == null &&
              error.code != 'popup-closed-by-user' &&
              error.code != 'cancelled-popup-request' &&
              error.code != 'redirect-cancelled-by-user') {
            rethrow;
          }
        }
      }
      // Firebase's first event is emitted after persisted state is loaded.
      await auth.authStateChanges().first;
    } catch (_) {
      _pending =
          null; // Failed attempts are retryable; in-flight work is shared.
      rethrow;
    }
  }

  static bool _storageUnavailable(FirebaseAuthException error) =>
      error.code == 'web-storage-unsupported' ||
      error.code == 'unsupported-persistence-type' ||
      error.code == 'operation-not-supported-in-this-environment';

  UserCredential? takeRedirectResult() {
    final result = _redirect;
    _redirect = null;
    return result;
  }
}
