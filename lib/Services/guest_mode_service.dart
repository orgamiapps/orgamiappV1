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

  GuestModeService._internal() : _authOverride = null, _storageOverride = null;

  @visibleForTesting
  GuestModeService.forTesting({
    required FirebaseAuth auth,
    required FlutterSecureStorage storage,
  }) : _authOverride = auth,
       _storageOverride = storage;

  final FirebaseAuth? _authOverride;
  final FlutterSecureStorage? _storageOverride;

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  FlutterSecureStorage get _storage => _storageOverride ?? _secureStorage;

  static const String _keyIsGuestMode = 'is_guest_mode';
  static const String _keyGuestSessionId = 'guest_session_id';
  static const String _keyGuestDisplayName = 'guest_display_name';

  bool _isGuestMode = true;
  bool _isInitialized = false;
  bool _isEnsuringGuestSession = false;
  Future<User?>? _guestSessionOperation;
  bool _disposed = false;
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
      _guestSessionId = await _storage.read(key: _keyGuestSessionId);
      final storedName = await _storage.read(key: _keyGuestDisplayName);
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
  Future<User?> ensureGuestSession() {
    final current = _auth.currentUser;
    if (current != null) {
      _syncFromAuthUser(current);
      return Future.value(current);
    }
    final pending = _guestSessionOperation;
    if (pending != null) return pending;

    final completer = Completer<User?>();
    _guestSessionOperation = completer.future;
    _isEnsuringGuestSession = true;
    _isGuestMode = true;
    _guestSessionError = null;
    notifyListeners();
    unawaited(_createGuestSession(completer));
    return completer.future;
  }

  Future<void> _createGuestSession(Completer<User?> completer) async {
    try {
      await _auth.signInAnonymously();
      final user = _auth.currentUser;
      if (user?.isAnonymous == true) {
        _guestSessionId = user!.uid;
        try {
          await _storage.write(key: _keyIsGuestMode, value: 'true');
          if (_auth.currentUser?.uid == user.uid) {
            await _storage.write(key: _keyGuestSessionId, value: user.uid);
          }
        } catch (error) {
          // Auth is authoritative even when browser storage is unavailable.
          Logger.warning('Could not persist anonymous session: $error');
        }
      }
      _syncFromAuthUser(_auth.currentUser, notify: false);
      completer.complete(_auth.currentUser);
    } catch (error, stack) {
      _guestSessionError = error;
      Logger.error('Unable to establish anonymous guest session', error);
      completer.completeError(error, stack);
    } finally {
      _guestSessionOperation = null;
      _isEnsuringGuestSession = false;
      notifyListeners();
    }
  }

  /// Backward-compatible entry point used by older guest flows.
  Future<void> enableGuestMode() async {
    await ensureGuestSession();
  }

  Future<void> disableGuestMode() async {
    _syncFromAuthUser(_auth.currentUser, notify: false);
    if (_isGuestMode) return;
    await _storage.delete(key: _keyIsGuestMode);
    await _storage.delete(key: _keyGuestSessionId);
    notifyListeners();
  }

  Future<void> saveGuestDisplayName(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return;
    _guestDisplayName = normalized;
    await _storage.write(key: _keyGuestDisplayName, value: normalized);
    notifyListeners();
  }

  Future<void> clearGuestDisplayName() async {
    _guestDisplayName = null;
    await _storage.delete(key: _keyGuestDisplayName);
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
    final previousId = _guestSessionId;
    _isGuestMode = user == null || user.isAnonymous;
    if (user?.isAnonymous == true) {
      _guestSessionId = user!.uid;
      _guestSessionError = null;
    } else {
      _guestSessionId = null;
      _guestSessionError = null;
    }
    if (notify &&
        (previousMode != _isGuestMode || previousId != _guestSessionId)) {
      notifyListeners();
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
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
