import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../core/permissions.dart';
import '../models/api_models.dart';
import 'admin_api_client.dart';

enum SessionStatus {
  loading,
  signedOut,
  checkingAccess,
  authorized,
  unauthorized,
  error,
}

class SessionController extends ChangeNotifier {
  SessionController({FirebaseAuth? auth, AdminApiClient? api})
    : _auth = auth ?? FirebaseAuth.instance,
      _api = api ?? AdminApiClient() {
    _subscription = _auth.authStateChanges().listen(_changed);
  }
  final FirebaseAuth _auth;
  final AdminApiClient _api;
  StreamSubscription<User?>? _subscription;
  SessionStatus status = SessionStatus.loading;
  AdminPermissions permissions = const AdminPermissions({});
  String? error;
  User? get user => _auth.currentUser;
  Future<void> _changed(User? user) async {
    if (user == null) {
      status = SessionStatus.signedOut;
      permissions = const AdminPermissions({});
      notifyListeners();
      return;
    }
    await refreshAccess();
  }

  Future<void> signIn(String email, String password) async {
    status = SessionStatus.loading;
    error = null;
    notifyListeners();
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      error = e.message ?? 'Sign in failed.';
      status = SessionStatus.signedOut;
      notifyListeners();
    }
  }

  Future<void> refreshAccess() async {
    status = SessionStatus.checkingAccess;
    error = null;
    notifyListeners();
    try {
      final response = await _api.getJson('/v1/me');
      final data = response['data'] as Map<String, dynamic>;
      permissions = AdminPermissions.fromWire(
        data['roles'] as List? ?? const [],
      );
      status = SessionStatus.authorized;
    } on ApiException catch (e) {
      error = e.message;
      status = e.status == 403
          ? SessionStatus.unauthorized
          : SessionStatus.error;
    }
    notifyListeners();
  }

  Future<void> signOut() => _auth.signOut();
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
