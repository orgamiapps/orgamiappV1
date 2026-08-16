import 'dart:async';

import 'package:attendus/Utils/logger.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum AccessMode { guest, authenticated }

/// The single source of truth for anonymous-versus-full account access.
class GuestModeService extends ChangeNotifier {
  static final GuestModeService _instance = GuestModeService._internal();
  factory GuestModeService() => _instance;

  GuestModeService._internal();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  FirebaseAuth get _auth => FirebaseAuth.instance;

  static const String _keyIsGuestMode = 'is_guest_mode';
  static const String _keyGuestSessionId = 'guest_session_id';
  static const String _keyGuestDisplayName = 'guest_display_name';

  bool _isGuestMode = true;
  bool _isInitialized = false;
  bool _isEnsuringGuestSession = false;
  String? _guestSessionId;
  String? _guestDisplayName;
  Object? _guestSessionError;
  StreamSubscription<User?>? _authSubscription;

  bool get isGuestMode => _isGuestMode;
  bool get isInitialized => _isInitialized;
  bool get isEnsuringGuestSession => _isEnsuringGuestSession;
  String? get guestSessionId => _guestSessionId;
  String? get guestDisplayName => _guestDisplayName;
  Object? get guestSessionError => _guestSessionError;
  AccessMode get accessMode =>
      _isGuestMode ? AccessMode.guest : AccessMode.authenticated;

  Future<void> initialize() async {
    try {
      _authSubscription ??= _auth.authStateChanges().listen(_syncFromAuthUser);
      _guestSessionId = await _secureStorage.read(key: _keyGuestSessionId);
      final storedName = await _secureStorage.read(key: _keyGuestDisplayName);
      _guestDisplayName = storedName?.trim().isEmpty == true
          ? null
          : storedName?.trim();
      _syncFromAuthUser(_auth.currentUser, notify: false);
    } catch (error) {
      Logger.error('Error initializing guest mode service', error);
      _syncFromAuthUser(_auth.currentUser, notify: false);
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Reuses an anonymous user, creates one when signed out, and never replaces
  /// a fully authenticated account.
  Future<User?> ensureGuestSession() async {
    final current = _auth.currentUser;
    if (current != null) {
      _syncFromAuthUser(current);
      return current;
    }
    if (_isEnsuringGuestSession) {
      return _auth.authStateChanges().firstWhere((user) => user != null);
    }

    _isEnsuringGuestSession = true;
    _isGuestMode = true;
    _guestSessionError = null;
    notifyListeners();
    try {
      final credential = await _auth.signInAnonymously();
      final user = credential.user;
      if (user != null) {
        _guestSessionId = user.uid;
        await _secureStorage.write(key: _keyIsGuestMode, value: 'true');
        await _secureStorage.write(key: _keyGuestSessionId, value: user.uid);
      }
      _syncFromAuthUser(user, notify: false);
      return user;
    } catch (error) {
      _guestSessionError = error;
      Logger.error('Unable to establish anonymous guest session', error);
      rethrow;
    } finally {
      _isEnsuringGuestSession = false;
      notifyListeners();
    }
  }

  /// Backward-compatible entry point used by older guest flows.
  Future<void> enableGuestMode() async {
    await ensureGuestSession();
  }

  Future<void> disableGuestMode() async {
    _isGuestMode = false;
    _guestSessionId = null;
    await _secureStorage.delete(key: _keyIsGuestMode);
    await _secureStorage.delete(key: _keyGuestSessionId);
    notifyListeners();
  }

  Future<void> saveGuestDisplayName(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return;
    _guestDisplayName = normalized;
    await _secureStorage.write(key: _keyGuestDisplayName, value: normalized);
    notifyListeners();
  }

  Future<void> clearGuestDisplayName() async {
    _guestDisplayName = null;
    await _secureStorage.delete(key: _keyGuestDisplayName);
    notifyListeners();
  }

  bool isFeatureAvailable(GuestFeature feature) {
    if (!_isGuestMode) return true;
    return switch (feature) {
      GuestFeature.viewEvents ||
      GuestFeature.searchEvents ||
      GuestFeature.viewGlobalMap ||
      GuestFeature.viewCalendar ||
      GuestFeature.eventSignIn => true,
      _ => false,
    };
  }

  String getFeatureRestrictionMessage(GuestFeature feature) {
    return switch (feature) {
      GuestFeature.createEvent =>
        'Create an account to start creating events and organizing your community.',
      GuestFeature.createGroup =>
        'Create an account to create and manage groups.',
      GuestFeature.editProfile =>
        'Create an account to customize your profile.',
      GuestFeature.viewMyGroups || GuestFeature.viewMyEvents =>
        'Create an account to view your personalized content.',
      GuestFeature.analytics =>
        'Create an account to access analytics and insights.',
      _ => 'Create an account to access this feature.',
    };
  }

  void _syncFromAuthUser(User? user, {bool notify = true}) {
    final previousMode = _isGuestMode;
    _isGuestMode = user == null || user.isAnonymous;
    if (user?.isAnonymous == true) {
      _guestSessionId = user!.uid;
      _guestSessionError = null;
    } else if (user != null) {
      _guestSessionId = null;
      _guestSessionError = null;
    }
    if (notify && previousMode != _isGuestMode) notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

enum GuestFeature {
  viewEvents,
  searchEvents,
  viewGlobalMap,
  viewCalendar,
  eventSignIn,
  createEvent,
  createGroup,
  editProfile,
  viewMyGroups,
  viewMyEvents,
  analytics,
}
