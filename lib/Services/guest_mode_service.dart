import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:attendus/Utils/logger.dart';

/// Service to manage guest mode functionality
/// Allows users to explore the app without creating an account
/// with limited features and access
class GuestModeService extends ChangeNotifier {
  static final GuestModeService _instance = GuestModeService._internal();
  factory GuestModeService() => _instance;
  GuestModeService._internal();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // Storage keys
  static const String _keyIsGuestMode = 'is_guest_mode';
  static const String _keyGuestSessionId = 'guest_session_id';

  bool _isGuestMode = false;
  String? _guestSessionId;

  bool get isGuestMode => _isGuestMode;
  String? get guestSessionId => _guestSessionId;

  /// Initialize guest mode service
  Future<void> initialize() async {
    try {
      final storedGuestMode = await _secureStorage.read(key: _keyIsGuestMode);
      final storedSessionId = await _secureStorage.read(key: _keyGuestSessionId);

      _isGuestMode = storedGuestMode == 'true';
      _guestSessionId = storedSessionId;

      Logger.info('Guest mode initialized: $_isGuestMode');
    } catch (e) {
      Logger.error('Error initializing guest mode service', e);
      _isGuestMode = false;
      _guestSessionId = null;
    }
  }

  /// Enable guest mode
  /// Creates a temporary session for the guest user
  Future<void> enableGuestMode() async {
    try {
      _isGuestMode = true;
      _guestSessionId = 'guest_${DateTime.now().millisecondsSinceEpoch}';

      await _secureStorage.write(key: _keyIsGuestMode, value: 'true');
      await _secureStorage.write(key: _keyGuestSessionId, value: _guestSessionId);

      Logger.info('Guest mode enabled with session: $_guestSessionId');
      notifyListeners();
    } catch (e) {
      Logger.error('Error enabling guest mode', e);
    }
  }

  /// Disable guest mode
  /// Called when user creates an account or logs in
  Future<void> disableGuestMode() async {
    try {
      _isGuestMode = false;
      _guestSessionId = null;

      await _secureStorage.delete(key: _keyIsGuestMode);
      await _secureStorage.delete(key: _keyGuestSessionId);

      Logger.info('Guest mode disabled');
      notifyListeners();
    } catch (e) {
      Logger.error('Error disabling guest mode', e);
    }
  }

  /// Check if a feature is available in guest mode
  bool isFeatureAvailable(GuestFeature feature) {
    if (!_isGuestMode) return true; // All features available for logged-in users

    switch (feature) {
      case GuestFeature.viewEvents:
      case GuestFeature.searchEvents:
      case GuestFeature.viewGlobalMap:
      case GuestFeature.viewCalendar:
      case GuestFeature.eventSignIn:
        return true;
      case GuestFeature.createEvent:
      case GuestFeature.createGroup:
      case GuestFeature.editProfile:
      case GuestFeature.viewMyGroups:
      case GuestFeature.viewMyEvents:
      case GuestFeature.analytics:
        return false;
    }
  }

  /// Get a friendly message explaining why a feature is restricted
  String getFeatureRestrictionMessage(GuestFeature feature) {
    switch (feature) {
      case GuestFeature.createEvent:
        return 'Create an account to start creating events and organizing your community!';
      case GuestFeature.createGroup:
        return 'Create an account to create and manage groups!';
      case GuestFeature.editProfile:
        return 'Create an account to customize your profile!';
      case GuestFeature.viewMyGroups:
      case GuestFeature.viewMyEvents:
        return 'Create an account to view your personalized content!';
      case GuestFeature.analytics:
        return 'Create an account to access analytics and insights!';
      default:
        return 'Create an account to access this feature!';
    }
  }
}

/// Enum defining features that can be restricted in guest mode
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
