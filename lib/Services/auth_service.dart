import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/Services/firebase_initializer.dart';

/// Authentication service that handles persistent login functionality
/// using Firebase Auth and secure storage for enhanced security
class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // Storage keys
  static const String _keyUserId = 'user_id';
  static const String _keyUserEmail = 'user_email';
  static const String _keyLastLoginTime = 'last_login_time';
  // Removed auto-login preference key; auto-login is always on

  // Initialization state
  bool _isInitialized = false;
  bool _isInitializing = false;
  Completer<void>? _initializationCompleter;

  User? get currentUser => _auth.currentUser;
  bool get isLoggedIn =>
      currentUser != null && CustomerController.logeInCustomer != null;

  /// Ensure Firebase is initialized before any auth operations
  Future<void> _ensureFirebaseInitialized() async {
    try {
      await FirebaseInitializer.initializeOnce();
      Logger.info('Firebase initialized via FirebaseInitializer (AuthService)');
    } catch (e) {
      Logger.warning(
        'Proceeding without confirmed Firebase init (AuthService): $e',
      );
    }
  }

  /// Initialize auth service and set up auth state listener
  Future<void> initialize() async {
    // Prevent multiple concurrent initializations
    if (_isInitialized) {
      Logger.debug('AuthService: Already initialized');
      return;
    }

    if (_isInitializing) {
      Logger.debug('AuthService: Waiting for ongoing initialization');
      return _initializationCompleter?.future ?? Future.value();
    }

    _isInitializing = true;
    _initializationCompleter = Completer<void>();

    try {
      await _ensureFirebaseInitialized();
      Logger.debug('AuthService: Starting initialization');

      // Listen to auth state changes
      _auth.authStateChanges().listen(_onAuthStateChanged);

      // Check if auto-login is enabled with timeout
      final autoLoginEnabled = await getAutoLoginEnabled().timeout(
        const Duration(seconds: 1),
        onTimeout: () {
          Logger.warning('Auto-login check timed out, defaulting to enabled');
          return true;
        },
      );

      if (!autoLoginEnabled) {
        Logger.info('Auto-login is disabled by user');
        _isInitialized = true;
        _initializationCompleter?.complete();
        return;
      }

      // Attempt to restore session with timeout to prevent hanging
      await _restoreUserSession().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          Logger.warning('Session restoration timed out');
          return false;
        },
      );

      _isInitialized = true;
      Logger.debug('AuthService: Initialization complete');
      _initializationCompleter?.complete();
    } catch (e) {
      Logger.error('Error initializing auth service', e);
      _initializationCompleter?.completeError(e);
    } finally {
      _isInitializing = false;
    }
  }

  /// Handle Firebase auth state changes
  void _onAuthStateChanged(User? user) async {
    if (user != null) {
      // User signed in, save session data
      await _saveUserSession(user);
      Logger.info('User signed in: ${user.uid}');
    } else {
      // User signed out, clear session data
      await _clearUserSession();
      Logger.info('User signed out');
    }
    notifyListeners();
  }

  /// Attempt to restore user session from stored data
  Future<bool> _restoreUserSession() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        Logger.info('No Firebase user found');
        return false;
      }

      // Verify stored user ID matches current user
      final storedUserId = await _secureStorage.read(key: _keyUserId);
      if (storedUserId != user.uid) {
        Logger.warning(
          'Stored user ID does not match current user, clearing session',
        );
        await _clearUserSession();
        await _auth.signOut();
        return false;
      }

      // Check if session is still valid (optional: implement session timeout)
      final lastLoginTimeStr = await _secureStorage.read(
        key: _keyLastLoginTime,
      );
      if (lastLoginTimeStr != null) {
        final lastLoginTime = DateTime.parse(lastLoginTimeStr);
        final sessionAge = DateTime.now().difference(lastLoginTime);

        // Optional: Implement session timeout (e.g., 30 days)
        if (sessionAge.inDays > 30) {
          Logger.info('Session expired, signing out');
          await signOut();
          return false;
        }
      }

      // Load user data from Firestore with shorter timeout for better UX
      final userData = await FirebaseFirestoreHelper()
          .getSingleCustomer(customerId: user.uid)
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () {
              Logger.warning('Firestore user data fetch timed out');
              return null;
            },
          );

      if (userData != null) {
        CustomerController.logeInCustomer = userData;
        Logger.info('User session restored successfully');
        notifyListeners();
        return true;
      } else {
        Logger.warning('Could not load user data from Firestore');
        await signOut();
        return false;
      }
    } catch (e) {
      Logger.error('Error restoring user session', e);
      return false;
    }
  }

  /// Save user session data securely
  Future<void> _saveUserSession(User user) async {
    try {
      await _secureStorage.write(key: _keyUserId, value: user.uid);
      await _secureStorage.write(key: _keyUserEmail, value: user.email ?? '');
      await _secureStorage.write(
        key: _keyLastLoginTime,
        value: DateTime.now().toIso8601String(),
      );
      Logger.info('User session saved');
    } catch (e) {
      Logger.error('Error saving user session', e);
    }
  }

  /// Complete post sign-in setup without blocking the UI
  Future<void> _completePostSignIn(User user) async {
    try {
      final userData = await FirebaseFirestoreHelper()
          .getSingleCustomer(customerId: user.uid)
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              Logger.warning('Post sign-in user data fetch timed out');
              return null;
            },
          );

      if (userData != null) {
        // Ensure user profile completeness (non-blocking importance)
        await FirebaseFirestoreHelper().ensureUserProfileCompleteness(user.uid);
        CustomerController.logeInCustomer = userData;
      } else {
        // Create minimal profile if none exists
        final newCustomer = CustomerModel(
          uid: user.uid,
          name: user.displayName ?? '',
          email: user.email ?? '',
          createdAt: DateTime.now(),
        );
        await FirebaseFirestore.instance
            .collection(CustomerModel.firebaseKey)
            .doc(newCustomer.uid)
            .set(CustomerModel.getMap(newCustomer));
        CustomerController.logeInCustomer = newCustomer;
      }

      await _saveUserSession(user);
      Logger.info('Post sign-in setup complete');
      notifyListeners();
    } catch (e) {
      Logger.error('Post sign-in setup failed', e);
    }
  }

  /// Clear all stored session data
  Future<void> _clearUserSession() async {
    try {
      await _secureStorage.delete(key: _keyUserId);
      await _secureStorage.delete(key: _keyUserEmail);
      await _secureStorage.delete(key: _keyLastLoginTime);
      CustomerController.logeInCustomer = null;
      Logger.info('User session cleared');
    } catch (e) {
      Logger.error('Error clearing user session', e);
    }
  }

  /// Sign in with email and password
  Future<User?> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
      await _ensureFirebaseInitialized();
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user != null) {
        // Do remaining work in background to avoid blocking UI
        Future.microtask(() => _completePostSignIn(credential.user!));
      }

      return credential.user;
    } catch (e) {
      Logger.error('Email/password sign in failed', e);
      rethrow;
    }
  }

  /// Sign out user and clear all session data
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      await _clearUserSession();
      Logger.info('User signed out successfully');
      notifyListeners();
    } catch (e) {
      Logger.error('Error signing out', e);
      rethrow;
    }
  }

  /// Check if auto-login is enabled
  Future<bool> getAutoLoginEnabled() async {
    // Force-enabled: app always remembers the user unless they sign out
    return true;
  }

  /// Enable or disable auto-login
  Future<void> setAutoLoginEnabled(bool enabled) async {
    // No-op: auto-login is always on. Intentionally ignore external toggles.
    Logger.info('Auto-login preference ignored (always-on).');
  }

  /// Get stored user information
  Future<Map<String, String?>> getStoredUserInfo() async {
    try {
      return {
        'userId': await _secureStorage.read(key: _keyUserId),
        'email': await _secureStorage.read(key: _keyUserEmail),
        'lastLoginTime': await _secureStorage.read(key: _keyLastLoginTime),
      };
    } catch (e) {
      Logger.error('Error reading stored user info', e);
      return {};
    }
  }

  /// Check if user session is valid
  Future<bool> isSessionValid() async {
    try {
      if (currentUser == null) return false;

      final storedUserId = await _secureStorage.read(key: _keyUserId);
      return storedUserId == currentUser!.uid;
    } catch (e) {
      Logger.error('Error checking session validity', e);
      return false;
    }
  }

  /// Refresh user data from Firestore
  Future<bool> refreshUserData() async {
    try {
      if (currentUser == null) return false;

      final userData = await FirebaseFirestoreHelper().getSingleCustomer(
        customerId: currentUser!.uid,
      );

      if (userData != null) {
        CustomerController.logeInCustomer = userData;
        notifyListeners();
        return true;
      }

      return false;
    } catch (e) {
      Logger.error('Error refreshing user data', e);
      return false;
    }
  }

  /// Handle successful social login (Google, Apple, etc.)
  Future<void> handleSocialLoginSuccess(User user) async {
    try {
      // Check if user exists in Firestore
      final userData = await FirebaseFirestoreHelper().getSingleCustomer(
        customerId: user.uid,
      );

      if (userData != null) {
        // Existing user
        CustomerController.logeInCustomer = userData;
      } else {
        // New user - create profile
        final newCustomerModel = CustomerModel(
          uid: user.uid,
          name: user.displayName ?? '',
          email: user.email ?? '',
          createdAt: DateTime.now(),
        );

        await FirebaseFirestore.instance
            .collection(CustomerModel.firebaseKey)
            .doc(newCustomerModel.uid)
            .set(CustomerModel.getMap(newCustomerModel));

        CustomerController.logeInCustomer = newCustomerModel;
      }

      await _saveUserSession(user);
      notifyListeners();
    } catch (e) {
      Logger.error('Error handling social login success', e);
      rethrow;
    }
  }
}
