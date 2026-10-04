import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/permissions.dart';
import '../google_oauth_config.dart';
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
      _api = api ?? AdminApiClient(auth: auth),
      _ownsApi = api == null {
    _subscription = _auth.authStateChanges().listen(_changed);
  }
  final FirebaseAuth _auth;
  final AdminApiClient _api;
  final bool _ownsApi;
  int _revision = 0;
  bool _disposed = false;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: const ['email', 'profile'],
  );
  StreamSubscription<User?>? _subscription;
  SessionStatus status = SessionStatus.loading;
  AdminPermissions permissions = const AdminPermissions({});
  String? error;
  User? get user => _auth.currentUser;
  Future<void> _changed(User? user) async {
    _revision++;
    permissions = const AdminPermissions({});
    error = null;
    if (user == null) {
      status = SessionStatus.signedOut;
      permissions = const AdminPermissions({});
      notifyListeners();
      return;
    }
    await refreshAccess();
  }

  Future<void> signIn(String email, String password) async {
    final revision = ++_revision;
    _api.invalidateSession();
    permissions = const AdminPermissions({});
    status = SessionStatus.loading;
    error = null;
    notifyListeners();
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (_disposed || revision != _revision) return;
      error = e.message ?? 'Sign in failed.';
      status = SessionStatus.signedOut;
      notifyListeners();
    }
  }

  Future<void> signInWithGoogle() async {
    final revision = ++_revision;
    _api.invalidateSession();
    permissions = const AdminPermissions({});
    status = SessionStatus.loading;
    error = null;
    notifyListeners();
    try {
      if (!isGoogleDesktopOAuthConfigured) {
        throw StateError(
          'Google desktop OAuth is not configured in this build.',
        );
      }
      final googleUser = await _googleSignIn.signIn();
      if (_disposed || revision != _revision) return;
      if (googleUser == null) {
        error = 'Google sign-in was canceled.';
        status = SessionStatus.signedOut;
        notifyListeners();
        return;
      }
      final googleAuth = await googleUser.authentication;
      if (_disposed || revision != _revision) return;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (_disposed || revision != _revision) return;
      error = switch (e.code) {
        'web-context-cancelled' ||
        'canceled' ||
        'cancelled-popup-request' => 'Google sign-in was canceled.',
        'account-exists-with-different-credential' =>
          'This email already uses a different sign-in method. Sign in with that method first.',
        _ => e.message ?? 'Google sign-in failed.',
      };
      status = SessionStatus.signedOut;
      notifyListeners();
    } on StateError catch (e) {
      if (_disposed || revision != _revision) return;
      error = e.message;
      status = SessionStatus.signedOut;
      notifyListeners();
    } catch (_) {
      if (_disposed || revision != _revision) return;
      error =
          'Google sign-in could not be completed. Check the desktop OAuth client configuration.';
      status = SessionStatus.signedOut;
      notifyListeners();
    }
  }

  Future<void> refreshAccess() async {
    final revision = ++_revision;
    final uid = _auth.currentUser?.uid;
    permissions = const AdminPermissions({});
    if (uid == null) {
      status = SessionStatus.signedOut;
      error = null;
      if (!_disposed) notifyListeners();
      return;
    }
    status = SessionStatus.checkingAccess;
    error = null;
    notifyListeners();
    try {
      final response = await _api.getJson('/v1/me');
      if (!_current(revision, uid)) return;
      final data = response['data'];
      if (data is! Map<String, dynamic> ||
          data['roles'] is! List ||
          (data['roles'] as List).any((role) => role is! String)) {
        throw const ApiException(
          'INVALID_RESPONSE',
          'The Admin API returned invalid access details. Please retry.',
        );
      }
      permissions = AdminPermissions.fromWire(
        data['roles'] as List? ?? const [],
      );
      status = SessionStatus.authorized;
    } on ApiException catch (e) {
      if (!_current(revision, uid)) return;
      error = e.message;
      status = e.status == 403
          ? SessionStatus.unauthorized
          : SessionStatus.error;
    }
    if (_current(revision, uid)) notifyListeners();
  }

  bool _current(int revision, String uid) =>
      !_disposed && revision == _revision && _auth.currentUser?.uid == uid;

  Future<void> signOut() async {
    _revision++;
    _api.invalidateSession();
    permissions = const AdminPermissions({});
    error = null;
    status = SessionStatus.signedOut;
    notifyListeners();
    try {
      if (isGoogleDesktopOAuthConfigured) await _googleSignIn.signOut();
    } finally {
      await _auth.signOut();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _subscription?.cancel();
    if (_ownsApi) _api.dispose();
    super.dispose();
  }
}
