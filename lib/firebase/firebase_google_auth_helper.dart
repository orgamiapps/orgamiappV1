import 'dart:async';

import 'package:attendus/Utils/app_constants.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class FirebaseGoogleAuthHelper extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static bool lastGoogleCancelled = false;
  static bool lastGoogleRedirectStarted = false;
  static bool lastAppleCancelled = false;
  static String? lastGoogleErrorMessage;
  static String? lastAppleErrorMessage;

  Future<Map<String, dynamic>?> loginWithGoogle() async {
    lastGoogleCancelled = false;
    lastGoogleRedirectStarted = false;
    lastGoogleErrorMessage = null;

    try {
      final provider = GoogleAuthProvider()
        ..addScope('email')
        ..addScope('profile')
        ..setCustomParameters({'prompt': 'select_account'});

      // Mobile browsers can replace the current tab while completing a popup
      // sign-in. Use Firebase's redirect flow there so the result can be
      // recovered reliably when Attendus is loaded again.
      if (_usesGoogleRedirectFlow) {
        Logger.info('Starting Google redirect sign-in for mobile web');
        lastGoogleRedirectStarted = true;
        await _auth.signInWithRedirect(provider);
        return null;
      }

      final UserCredential credential = kIsWeb
          ? await _auth
                .signInWithPopup(provider)
                .timeout(const Duration(seconds: 45))
          : await _auth
                .signInWithProvider(provider)
                .timeout(const Duration(seconds: 60));

      final user = credential.user;
      if (user == null) {
        lastGoogleErrorMessage =
            'Google sign-in did not return an account. Please try again.';
        return null;
      }

      final profileData = _profileDataFromUser(user, providerId: 'google.com');
      Logger.info(
        'Google sign-in successful with profile data: ${profileData.keys}',
      );
      notifyListeners();
      return profileData;
    } on FirebaseAuthException catch (error) {
      if (_isAuthCancellation(error)) {
        lastGoogleCancelled = true;
        Logger.info('Google sign-in cancelled: ${error.code}');
        return null;
      }

      lastGoogleErrorMessage = _googleAuthErrorMessage(error);
      Logger.error(
        'Google sign-in FirebaseAuthException: ${error.code} ${error.message}',
        error,
      );
      return null;
    } on TimeoutException catch (error) {
      lastGoogleErrorMessage = 'Google sign-in timed out. Please try again.';
      Logger.error('Google sign-in timed out', error);
      return null;
    } catch (error) {
      final message = error.toString().toLowerCase();
      if (_isCancellationMessage(message)) {
        lastGoogleCancelled = true;
        Logger.info('Google sign-in cancelled: $error');
        return null;
      }

      lastGoogleErrorMessage = _googleUnknownErrorMessage(error);
      Logger.error('Google sign-in error: $error', error);
      return null;
    }
  }

  /// Completes a Google redirect after a mobile web OAuth round trip.
  ///
  /// A successful redirect reloads the Flutter app, so the original button
  /// callback no longer exists. The startup auth gate calls this before it
  /// decides whether to show onboarding or the authenticated app.
  Future<Map<String, dynamic>?> completeGoogleRedirectSignIn() async {
    if (!kIsWeb) return null;

    try {
      final credential = await _auth.getRedirectResult().timeout(
        const Duration(seconds: 45),
      );
      final user = credential.user;
      if (user == null) return null;

      final isGoogleSignIn = user.providerData.any(
        (provider) => provider.providerId == 'google.com',
      );
      if (!isGoogleSignIn) return null;

      Logger.info('Completed Google redirect sign-in: ${user.uid}');
      return _profileDataFromUser(user, providerId: 'google.com');
    } on FirebaseAuthException catch (error) {
      if (_isAuthCancellation(error)) {
        Logger.info('Google redirect sign-in cancelled: ${error.code}');
        return null;
      }
      Logger.error(
        'Google redirect sign-in failed: ${error.code} ${error.message}',
        error,
      );
      return null;
    } on TimeoutException catch (error) {
      Logger.error('Google redirect result timed out', error);
      return null;
    } catch (error) {
      Logger.error('Could not complete Google redirect sign-in', error);
      return null;
    }
  }

  static bool get _usesGoogleRedirectFlow =>
      kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<Map<String, dynamic>?> loginWithApple() async {
    lastAppleCancelled = false;
    lastAppleErrorMessage = null;

    if (!AppConstants.enableAppleSignIn) {
      lastAppleErrorMessage = 'Apple sign-in is not available yet.';
      Logger.warning('Apple sign-in is disabled via feature flag');
      return null;
    }

    if (AppConstants.appleServiceId.isEmpty ||
        AppConstants.appleRedirectUrl.isEmpty) {
      lastAppleErrorMessage =
          'Apple sign-in is not configured for this release.';
      Logger.warning(
        'Apple sign-in requested without ATTENDUS_APPLE_SERVICE_ID and ATTENDUS_APPLE_REDIRECT_URL',
      );
      return null;
    }

    try {
      if (!await SignInWithApple.isAvailable()) {
        lastAppleErrorMessage =
            'Apple sign-in is not available on this device or browser.';
        Logger.warning('Apple Sign-In is not available on this device');
        return null;
      }

      final appleCredential =
          await SignInWithApple.getAppleIDCredential(
            scopes: [
              AppleIDAuthorizationScopes.email,
              AppleIDAuthorizationScopes.fullName,
            ],
            webAuthenticationOptions: WebAuthenticationOptions(
              clientId: AppConstants.appleServiceId,
              redirectUri: Uri.parse(AppConstants.appleRedirectUrl),
            ),
          ).timeout(
            const Duration(seconds: 45),
            onTimeout: () {
              throw TimeoutException('Apple sign-in timed out');
            },
          );

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      final credential = await _auth
          .signInWithCredential(oauthCredential)
          .timeout(const Duration(seconds: 20));
      final user = credential.user;
      if (user == null) {
        lastAppleErrorMessage =
            'Apple sign-in did not return an account. Please try again.';
        return null;
      }

      final profileData = _profileDataFromAppleCredential(
        user,
        appleCredential,
      );
      Logger.info(
        'Apple sign-in successful with profile data: ${profileData.keys}',
      );
      notifyListeners();
      return profileData;
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        lastAppleCancelled = true;
        Logger.info('Apple sign-in cancelled by user');
        return null;
      }

      lastAppleErrorMessage =
          'Apple sign-in could not be completed. Please try again.';
      Logger.error('Apple sign-in auth exception: $error', error);
      return null;
    } on FirebaseAuthException catch (error) {
      if (_isAuthCancellation(error)) {
        lastAppleCancelled = true;
        Logger.info('Apple sign-in cancelled: ${error.code}');
        return null;
      }

      lastAppleErrorMessage = _appleAuthErrorMessage(error);
      Logger.error(
        'Apple sign-in FirebaseAuthException: ${error.code} ${error.message}',
        error,
      );
      return null;
    } on TimeoutException catch (error) {
      lastAppleErrorMessage = 'Apple sign-in timed out. Please try again.';
      Logger.error('Apple sign-in timeout', error);
      return null;
    } catch (error) {
      lastAppleErrorMessage =
          'Apple sign-in could not be completed. Please try again.';
      Logger.error('Apple sign-in error: $error', error);
      return null;
    }
  }

  Future<User?> loginWithFacebook() async {
    Logger.warning('Facebook authentication is unavailable in this build');
    return null;
  }

  Future<User?> loginWithX() async {
    try {
      if (kIsWeb) {
        final twitterProvider = TwitterAuthProvider();
        final credential = await _auth.signInWithPopup(twitterProvider);
        final user = credential.user;

        if (user != null) {
          notifyListeners();
          return user;
        }
      } else {
        Logger.warning(
          'X sign-in requires web-based authentication or custom server implementation',
        );
      }

      return null;
    } catch (error) {
      Logger.error('X sign-in error: $error', error);
      return null;
    }
  }

  Map<String, dynamic> _profileDataFromUser(
    User user, {
    required String providerId,
  }) {
    final profileData = <String, dynamic>{'user': user};
    String? displayName = user.displayName;
    String? photoUrl = user.photoURL;
    String? phoneNumber = user.phoneNumber;

    for (final provider in user.providerData) {
      if (provider.providerId != providerId) continue;
      displayName = _firstNonEmpty(displayName, provider.displayName);
      photoUrl = _firstNonEmpty(photoUrl, provider.photoURL);
      phoneNumber = _firstNonEmpty(phoneNumber, provider.phoneNumber);
    }

    if (displayName != null && displayName.isNotEmpty) {
      profileData['fullName'] = displayName;
      final nameParts = displayName.trim().split(RegExp(r'\s+'));
      if (nameParts.isNotEmpty) {
        profileData['firstName'] = nameParts.first;
        if (nameParts.length > 1) {
          profileData['lastName'] = nameParts.skip(1).join(' ');
        }
      }

      if (user.displayName == null || user.displayName!.isEmpty) {
        Future.microtask(() async {
          try {
            await user.updateDisplayName(displayName);
            Logger.info('Updated Firebase displayName from provider data');
          } catch (error) {
            Logger.warning('Could not update displayName: $error');
          }
        });
      }
    }

    if (photoUrl != null && photoUrl.isNotEmpty) {
      profileData['photoUrl'] = photoUrl;
    }
    if (phoneNumber != null && phoneNumber.isNotEmpty) {
      profileData['phoneNumber'] = phoneNumber;
    }

    return profileData;
  }

  Map<String, dynamic> _profileDataFromAppleCredential(
    User user,
    AuthorizationCredentialAppleID appleCredential,
  ) {
    final profileData = _profileDataFromUser(user, providerId: 'apple.com');

    if (appleCredential.givenName != null &&
        appleCredential.givenName!.isNotEmpty) {
      profileData['firstName'] = appleCredential.givenName;
    }
    if (appleCredential.familyName != null &&
        appleCredential.familyName!.isNotEmpty) {
      profileData['lastName'] = appleCredential.familyName;
    }

    final fullName = [
      appleCredential.givenName,
      appleCredential.familyName,
    ].whereType<String>().where((name) => name.isNotEmpty).join(' ');

    if (fullName.isNotEmpty) {
      profileData['fullName'] = fullName;
      if (user.displayName == null || user.displayName!.isEmpty) {
        Future.microtask(() async {
          try {
            await user.updateDisplayName(fullName);
            Logger.info('Updated Firebase displayName from Apple');
          } catch (error) {
            Logger.warning('Could not update displayName: $error');
          }
        });
      }
    }

    return profileData;
  }

  static String? _firstNonEmpty(String? current, String? candidate) {
    if (current != null && current.isNotEmpty) return current;
    if (candidate != null && candidate.isNotEmpty) return candidate;
    return null;
  }

  static bool _isAuthCancellation(FirebaseAuthException error) {
    final code = error.code.toLowerCase();
    final message = error.message?.toLowerCase() ?? '';
    return code.contains('canceled') ||
        code.contains('cancelled') ||
        code.contains('aborted') ||
        code == 'web-context-canceled' ||
        code == 'popup-closed-by-user' ||
        _isCancellationMessage(message);
  }

  static bool _isCancellationMessage(String message) {
    return message.contains('popup-closed-by-user') ||
        message.contains('canceled') ||
        message.contains('cancelled') ||
        message.contains('aborted');
  }

  static String _googleAuthErrorMessage(FirebaseAuthException error) {
    switch (error.code.toLowerCase()) {
      case 'unauthorized-domain':
        return 'This domain is not authorized for Google sign-in.';
      case 'popup-blocked':
        return 'The Google sign-in popup was blocked. Allow popups and try again.';
      case 'operation-not-allowed':
        return 'Google sign-in is not enabled for this Firebase project.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email using a different sign-in method.';
      case 'network-request-failed':
        return 'Network error during Google sign-in. Check your connection and try again.';
      case 'invalid-api-key':
      case 'app-not-authorized':
      case 'invalid-credential':
        return 'Google sign-in is not configured correctly for this app.';
      default:
        final message = error.message?.trim();
        if (message != null && message.isNotEmpty) {
          return 'Google sign-in failed: $message';
        }
        return 'Google sign-in could not be completed. Please try again.';
    }
  }

  static String _appleAuthErrorMessage(FirebaseAuthException error) {
    switch (error.code.toLowerCase()) {
      case 'operation-not-allowed':
        return 'Apple sign-in is not enabled for this Firebase project.';
      case 'unauthorized-domain':
        return 'This domain is not authorized for Apple sign-in.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email using a different sign-in method.';
      default:
        final message = error.message?.trim();
        if (message != null && message.isNotEmpty) {
          return 'Apple sign-in failed: $message';
        }
        return 'Apple sign-in could not be completed. Please try again.';
    }
  }

  static String _googleUnknownErrorMessage(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('unauthorized-domain')) {
      return 'This domain is not authorized for Google sign-in.';
    }
    if (message.contains('popup') && message.contains('blocked')) {
      return 'The Google sign-in popup was blocked. Allow popups and try again.';
    }
    if (message.contains('operation-not-allowed')) {
      return 'Google sign-in is not enabled for this Firebase project.';
    }
    return 'Google sign-in could not be completed. Please try again.';
  }
}
