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
import 'package:attendus/firebase/firebase_google_auth_helper.dart';

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
  bool _initialAuthChecked = false;

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

      // Ensure FirebaseAuth has delivered the initial persisted state
      await _waitForInitialAuthState().timeout(
        const Duration(seconds: 1),
        onTimeout: () {
          Logger.warning('Initial auth state wait timed out; continuing');
        },
      );

      // If a user is present but local model is missing, set a minimal profile immediately
      if (_auth.currentUser != null &&
          CustomerController.logeInCustomer == null) {
        _setMinimalCustomerFromFirebaseUser(_auth.currentUser!);
        await _saveUserSession(_auth.currentUser!);
      }

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
        const Duration(seconds: 1),
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

  /// Wait for the first auth state emission so persisted sessions are available
  Future<void> _waitForInitialAuthState() async {
    if (_initialAuthChecked) return;
    try {
      // If a user is already present, nothing to wait for
      if (_auth.currentUser != null) {
        _initialAuthChecked = true;
        return;
      }

      // Await the first emission which delivers persisted user (if any)
      await _auth.authStateChanges().first;
    } catch (e) {
      Logger.warning('Failed waiting for initial auth state: $e');
    } finally {
      _initialAuthChecked = true;
    }
  }

  void _setMinimalCustomerFromFirebaseUser(User user) {
    try {
      if (CustomerController.logeInCustomer != null) return;
      final minimalCustomer = CustomerModel(
        uid: user.uid,
        name: user.displayName ?? '',
        email: user.email ?? '',
        createdAt: DateTime.now(),
      );
      CustomerController.logeInCustomer = minimalCustomer;
      notifyListeners();
    } catch (e) {
      Logger.warning('Failed to set minimal customer model: $e');
    }
  }

  /// Ensure an in-memory user model exists when Firebase has a current user
  Future<bool> ensureInMemoryUserModel() async {
    try {
      if (_auth.currentUser == null) return false;
      if (CustomerController.logeInCustomer == null) {
        _setMinimalCustomerFromFirebaseUser(_auth.currentUser!);
        await _saveUserSession(_auth.currentUser!);
      }
      return true;
    } catch (e) {
      Logger.warning('ensureInMemoryUserModel failed: $e');
      return false;
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
        // Do not force sign-out on startup; prefer keeping Firebase session
        // Clear only local session data and re-save with current user
        await _clearUserSession();
        await _saveUserSession(user);
        // Continue with user data fetch below
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
        // Fallback: set minimal customer model so app can proceed offline
        Logger.warning(
          'Could not load user data from Firestore, using minimal profile',
        );
        final minimalCustomer = CustomerModel(
          uid: user.uid,
          name: user.displayName ?? '',
          email: user.email ?? '',
          createdAt: DateTime.now(),
        );
        CustomerController.logeInCustomer = minimalCustomer;
        notifyListeners();
        return true;
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

  /// Enhanced method to handle social login with profile data extraction
  /// Optimized for fast login - defers profile updates to background
  Future<void> handleSocialLoginSuccessWithProfileData(
    Map<String, dynamic> profileData,
  ) async {
    try {
      final user = profileData['user'] as User;

      // Check if user exists in Firestore with timeout
      final userData = await FirebaseFirestoreHelper()
          .getSingleCustomer(customerId: user.uid)
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              Logger.warning('User lookup timed out during social login');
              return null;
            },
          );

      if (userData != null) {
        // Existing user - set immediately for fast navigation
        CustomerController.logeInCustomer = userData;
        Logger.info('Existing user logged in: ${user.uid}');

        // Defer profile updates to background (non-blocking)
        Future.microtask(() async {
          try {
            await _updateExistingUserProfile(userData, profileData);
            Logger.info('Background profile update completed');
          } catch (e) {
            Logger.warning('Background profile update failed: $e');
            // Non-critical, don't block login
          }
        });
      } else {
        // New user - create minimal profile immediately
        final newCustomerModel = await _createEnhancedUserProfile(
          user,
          profileData,
        );

        // Set in memory immediately
        CustomerController.logeInCustomer = newCustomerModel;

        // Save to Firestore in background (non-blocking)
        Future.microtask(() async {
          try {
            await FirebaseFirestore.instance
                .collection(CustomerModel.firebaseKey)
                .doc(newCustomerModel.uid)
                .set(CustomerModel.getMap(newCustomerModel))
                .timeout(const Duration(seconds: 5));
            Logger.info('New user profile saved to Firestore');
          } catch (e) {
            Logger.error('Error saving new user profile to Firestore: $e');
            // Retry once
            try {
              await Future.delayed(const Duration(seconds: 2));
              await FirebaseFirestore.instance
                  .collection(CustomerModel.firebaseKey)
                  .doc(newCustomerModel.uid)
                  .set(CustomerModel.getMap(newCustomerModel))
                  .timeout(const Duration(seconds: 5));
              Logger.info('New user profile saved on retry');
            } catch (retryError) {
              Logger.error('Failed to save user profile on retry: $retryError');
            }
          }
        });
      }

      await _saveUserSession(user);
      notifyListeners();
      Logger.info('Social login completed successfully');
    } catch (e) {
      Logger.error('Error handling social login success with profile data', e);
      rethrow;
    }
  }

  /// Update current user's profile from Firebase Auth data if incomplete
  /// This is useful for existing users who may have incomplete profile information
  Future<bool> updateCurrentUserProfileFromAuth() async {
    try {
      final currentFirebaseUser = _auth.currentUser;
      final currentCustomer = CustomerController.logeInCustomer;

      Logger.info('=== MANUAL PROFILE UPDATE DEBUG ===');
      Logger.info('Current Firebase User: ${currentFirebaseUser?.uid}');
      Logger.info('Display Name: "${currentFirebaseUser?.displayName}"');
      Logger.info('Email: "${currentFirebaseUser?.email}"');
      Logger.info('Photo URL: "${currentFirebaseUser?.photoURL}"');
      Logger.info('Current Customer Name: "${currentCustomer?.name}"');
      Logger.info('Current Customer Email: "${currentCustomer?.email}"');

      if (currentFirebaseUser == null || currentCustomer == null) {
        Logger.warning('No current user to update profile for');
        return false;
      }

      // Create minimal profile data from Firebase Auth user
      Map<String, dynamic> profileData = {'user': currentFirebaseUser};

      // Add display name if available
      if (currentFirebaseUser.displayName != null &&
          currentFirebaseUser.displayName!.isNotEmpty) {
        profileData['fullName'] = currentFirebaseUser.displayName;
        Logger.info(
          'Added fullName to profile data: ${currentFirebaseUser.displayName}',
        );

        // Try to split full name into first and last name
        final nameParts = currentFirebaseUser.displayName!.trim().split(' ');
        if (nameParts.isNotEmpty) {
          profileData['firstName'] = nameParts[0];
          Logger.info('Added firstName to profile data: ${nameParts[0]}');
          if (nameParts.length > 1) {
            profileData['lastName'] = nameParts.sublist(1).join(' ');
            Logger.info(
              'Added lastName to profile data: ${nameParts.sublist(1).join(' ')}',
            );
          }
        }
      } else {
        Logger.warning('Firebase Auth user has no displayName to extract from');
      }

      Logger.info('Profile data to use for update: ${profileData.keys}');

      // Update the existing user profile
      await _updateExistingUserProfile(currentCustomer, profileData);

      Logger.info(
        'Successfully completed manual profile update from Firebase Auth',
      );
      return true;
    } catch (e) {
      Logger.error('Error updating current user profile from auth', e);
      return false;
    }
  }

  /// Diagnose current user's profile and Firebase Auth state
  /// This method provides detailed logging to help debug profile issues
  Future<Map<String, dynamic>> diagnoseUserProfile() async {
    final diagnosis = <String, dynamic>{};

    try {
      final currentFirebaseUser = _auth.currentUser;
      final currentCustomer = CustomerController.logeInCustomer;

      Logger.info('=== USER PROFILE DIAGNOSIS ===');

      // Firebase Auth User Info
      diagnosis['firebaseUser'] = {
        'exists': currentFirebaseUser != null,
        'uid': currentFirebaseUser?.uid,
        'email': currentFirebaseUser?.email,
        'displayName': currentFirebaseUser?.displayName,
        'photoURL': currentFirebaseUser?.photoURL,
        'providers': currentFirebaseUser?.providerData
            .map((p) => p.providerId)
            .toList(),
        'emailVerified': currentFirebaseUser?.emailVerified,
      };

      Logger.info('Firebase Auth User: ${diagnosis['firebaseUser']}');

      // Customer Model Info
      diagnosis['customerModel'] = {
        'exists': currentCustomer != null,
        'uid': currentCustomer?.uid,
        'name': currentCustomer?.name,
        'email': currentCustomer?.email,
        'phoneNumber': currentCustomer?.phoneNumber,
        'profilePictureUrl': currentCustomer?.profilePictureUrl,
        'username': currentCustomer?.username,
        'age': currentCustomer?.age,
        'location': currentCustomer?.location,
        'occupation': currentCustomer?.occupation,
        'company': currentCustomer?.company,
      };

      Logger.info('Customer Model: ${diagnosis['customerModel']}');

      // Profile Completeness Analysis
      diagnosis['profileAnalysis'] = {
        'hasGoogleProvider':
            currentFirebaseUser?.providerData.any(
              (p) => p.providerId == 'google.com',
            ) ??
            false,
        'hasAppleProvider':
            currentFirebaseUser?.providerData.any(
              (p) => p.providerId == 'apple.com',
            ) ??
            false,
        'nameNeedsUpdate': _shouldUpdateName(currentCustomer),
        'hasFirebaseDisplayName':
            currentFirebaseUser?.displayName != null &&
            currentFirebaseUser!.displayName!.isNotEmpty,
        'canUpdateFromFirebaseAuth':
            currentFirebaseUser?.displayName != null &&
            currentFirebaseUser!.displayName!.isNotEmpty &&
            _shouldUpdateName(currentCustomer),
      };

      Logger.info('Profile Analysis: ${diagnosis['profileAnalysis']}');

      // Recommendations
      final recommendations = <String>[];
      if (diagnosis['profileAnalysis']['hasGoogleProvider'] ||
          diagnosis['profileAnalysis']['hasAppleProvider']) {
        recommendations.add('User signed in with social provider');
      }
      if (diagnosis['profileAnalysis']['canUpdateFromFirebaseAuth']) {
        recommendations.add(
          'Profile can be updated from Firebase Auth displayName',
        );
      }
      if (!diagnosis['profileAnalysis']['hasFirebaseDisplayName']) {
        recommendations.add(
          'Firebase Auth user has no displayName - need fresh sign-in',
        );
      }

      diagnosis['recommendations'] = recommendations;
      Logger.info('Recommendations: $recommendations');
    } catch (e) {
      diagnosis['error'] = e.toString();
      Logger.error('Error during profile diagnosis', e);
    }

    Logger.info('=== END DIAGNOSIS ===');
    return diagnosis;
  }

  /// Helper method to determine if a user's name should be updated
  bool _shouldUpdateName(CustomerModel? customer) {
    if (customer == null) return false;

    if (customer.name.isEmpty) return true;
    if (customer.name == customer.email.split('@')[0]) return true;
    if (customer.name.toLowerCase() == 'user' ||
        customer.name.toLowerCase() == 'unknown' ||
        customer.name.contains('@')) {
      return true;
    }

    return false;
  }

  /// Force refresh current user's profile by re-authenticating with the same provider
  /// This will re-trigger the Google/Apple sign-in to get fresh profile data
  Future<bool> refreshCurrentUserProfileFromProvider() async {
    try {
      final currentFirebaseUser = _auth.currentUser;
      if (currentFirebaseUser == null) {
        Logger.warning('No current user to refresh profile for');
        return false;
      }

      Logger.info('=== PROVIDER PROFILE REFRESH DEBUG ===');
      Logger.info(
        'Current user providers: ${currentFirebaseUser.providerData.map((p) => p.providerId)}',
      );

      // Check if user signed in with Google
      final googleProvider = currentFirebaseUser.providerData
          .where((provider) => provider.providerId == 'google.com')
          .firstOrNull;

      // Check if user signed in with Apple
      final appleProvider = currentFirebaseUser.providerData
          .where((provider) => provider.providerId == 'apple.com')
          .firstOrNull;

      if (googleProvider != null) {
        Logger.info(
          'User has Google provider, attempting fresh Google sign-in',
        );
        final helper = FirebaseGoogleAuthHelper();
        final profileData = await helper.loginWithGoogle();
        if (profileData != null) {
          await handleSocialLoginSuccessWithProfileData(profileData);
          Logger.info('Successfully refreshed profile from Google');
          return true;
        }
      } else if (appleProvider != null) {
        Logger.info('User has Apple provider, attempting fresh Apple sign-in');
        final helper = FirebaseGoogleAuthHelper();
        final profileData = await helper.loginWithApple();
        if (profileData != null) {
          await handleSocialLoginSuccessWithProfileData(profileData);
          Logger.info('Successfully refreshed profile from Apple');
          return true;
        }
      } else {
        Logger.warning(
          'User did not sign in with Google or Apple, cannot refresh from provider',
        );
        // Fallback to updating from existing Firebase Auth data
        return await updateCurrentUserProfileFromAuth();
      }

      return false;
    } catch (e) {
      Logger.error('Error refreshing user profile from provider', e);
      return false;
    }
  }

  /// Create enhanced user profile with extracted social login data
  Future<CustomerModel> _createEnhancedUserProfile(
    User user,
    Map<String, dynamic> profileData,
  ) async {
    // Use the full name from profile data, fallback to displayName, then email
    String displayName = '';
    if (profileData.containsKey('fullName') &&
        profileData['fullName'] != null) {
      displayName = profileData['fullName'];
    } else if (user.displayName != null && user.displayName!.isNotEmpty) {
      displayName = user.displayName!;
    } else {
      // Extract name from email as last resort
      displayName = user.email?.split('@')[0] ?? 'User';
    }

    return CustomerModel(
      uid: user.uid,
      name: displayName,
      email: user.email ?? '',
      phoneNumber:
          profileData['phoneNumber'], // Will be null for Google/Apple basic
      createdAt: DateTime.now(),
      isDiscoverable: true, // Default to discoverable
    );
  }

  /// Update existing user profile with any new information from social login
  /// Optimized to avoid blocking reload operations
  Future<void> _updateExistingUserProfile(
    CustomerModel existingUser,
    Map<String, dynamic> profileData,
  ) async {
    try {
      Map<String, dynamic> updates = {};
      final user = profileData['user'] as User;

      Logger.info('=== PROFILE UPDATE (Background) ===');
      Logger.info('Current customer name: "${existingUser.name}"');
      Logger.info('Profile data fullName: "${profileData['fullName']}"');
      Logger.info('Profile data keys: ${profileData.keys}');

      // Always try to get the best name available
      String? bestName;

      // Priority 1: fullName from profile data (from Google/Apple)
      if (profileData.containsKey('fullName') &&
          profileData['fullName'] != null &&
          profileData['fullName'].toString().trim().isNotEmpty) {
        bestName = profileData['fullName'].toString().trim();
        Logger.info('Using fullName from profile data: "$bestName"');
      }
      // Priority 2: Current Firebase Auth displayName (no reload needed)
      else if (user.displayName != null &&
          user.displayName!.trim().isNotEmpty) {
        bestName = user.displayName!.trim();
        Logger.info('Using Firebase displayName: "$bestName"');
      }

      // Update name if we found a better one or current one needs improvement
      bool needsNameUpdate =
          _shouldUpdateName(existingUser) ||
          (bestName != null &&
              bestName != existingUser.name &&
              bestName.length > existingUser.name.length &&
              !bestName.contains('@'));

      if (needsNameUpdate && bestName != null) {
        final oldName = existingUser.name;
        updates['name'] = bestName;
        existingUser.name = bestName;
        Logger.info('✅ Updating name from "$oldName" to "$bestName"');
      } else {
        Logger.info('Name update not needed or no better name found');
      }

      // Update phone number if it's empty and available from profile
      if (existingUser.phoneNumber == null &&
          profileData.containsKey('phoneNumber') &&
          profileData['phoneNumber'] != null &&
          profileData['phoneNumber'].toString().trim().isNotEmpty) {
        updates['phoneNumber'] = profileData['phoneNumber'].toString().trim();
        existingUser.phoneNumber = profileData['phoneNumber'].toString().trim();
      }

      // Ensure profile picture URL is preserved from Firebase Auth if missing
      if ((existingUser.profilePictureUrl == null ||
              existingUser.profilePictureUrl!.isEmpty) &&
          user.photoURL != null &&
          user.photoURL!.isNotEmpty) {
        updates['profilePictureUrl'] = user.photoURL;
        existingUser.profilePictureUrl = user.photoURL;
      }

      // Apply updates to Firestore if any (with timeout)
      if (updates.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection(CustomerModel.firebaseKey)
            .doc(existingUser.uid)
            .update(updates)
            .timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                Logger.warning('Profile update to Firestore timed out');
              },
            );

        Logger.info(
          'Updated existing user profile with: ${updates.keys.join(', ')}',
        );
      } else {
        Logger.info('No profile updates needed for existing user');
      }

      // Update the controller with the latest data
      CustomerController.logeInCustomer = existingUser;
      notifyListeners();
    } catch (e) {
      Logger.error('Error updating existing user profile', e);
      // Don't rethrow as this is not critical for login success
    }
  }

  /// Enhanced method to aggressively update user profile on every opportunity
  Future<bool> aggressiveProfileUpdate() async {
    try {
      final currentFirebaseUser = _auth.currentUser;
      final currentCustomer = CustomerController.logeInCustomer;

      Logger.info('=== AGGRESSIVE PROFILE UPDATE ===');

      if (currentFirebaseUser == null || currentCustomer == null) {
        Logger.warning('No current user/customer for aggressive update');
        return false;
      }

      // Force reload Firebase Auth user to get fresh data
      await currentFirebaseUser.reload();
      final refreshedUser = _auth.currentUser;

      if (refreshedUser != null) {
        Logger.info('Current displayName: "${refreshedUser.displayName}"');
        Logger.info('Current email: "${refreshedUser.email}"');
        Logger.info('Current photoURL: "${refreshedUser.photoURL}"');

        // Create comprehensive profile data
        Map<String, dynamic> profileData = {'user': refreshedUser};

        // Add all available name data
        if (refreshedUser.displayName != null &&
            refreshedUser.displayName!.isNotEmpty) {
          profileData['fullName'] = refreshedUser.displayName;
          Logger.info(
            'Added fullName to profile data: ${refreshedUser.displayName}',
          );

          // Split name into parts
          final nameParts = refreshedUser.displayName!.trim().split(' ');
          if (nameParts.isNotEmpty) {
            profileData['firstName'] = nameParts[0];
            if (nameParts.length > 1) {
              profileData['lastName'] = nameParts.sublist(1).join(' ');
            }
          }
        } else {
          Logger.warning('Firebase Auth displayName is null or empty');
        }

        // Force update the profile
        await _updateExistingUserProfile(currentCustomer, profileData);
        return true;
      }

      return false;
    } catch (e) {
      Logger.error('Error in aggressive profile update', e);
      return false;
    }
  }
}
