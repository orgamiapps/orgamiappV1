import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:attendus/Utils/app_constants.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
// import 'package:flutter_facebook_auth/flutter_facebook_auth.dart'; // Temporarily disabled
// import 'package:twitter_login/twitter_login.dart'; // Disabled due to namespace issues

class FirebaseGoogleAuthHelper extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static bool lastGoogleCancelled = false;
  static bool lastAppleCancelled = false;

  Future<Map<String, dynamic>?> loginWithGoogle() async {
    try {
      lastGoogleCancelled = false;
      User? user;
      if (kIsWeb) {
        // Web uses popup auth flow
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope(
          'profile',
        ); // Add profile scope for better user info
        
        // Add custom parameter to force account selection on web
        googleProvider.setCustomParameters({
          'prompt': 'select_account', // Forces account picker
        });
        
        final UserCredential userCredential = await _auth
            .signInWithPopup(googleProvider)
            .timeout(const Duration(seconds: 30));
        user = userCredential.user;
      } else {
        // Mobile/desktop: use Firebase Auth's native provider sign-in
        try {
          Logger.info('🔵 Starting Google sign-in flow...');
          
          final GoogleAuthProvider googleProvider = GoogleAuthProvider();
          googleProvider.addScope('email');
          googleProvider.addScope('profile');
          
          // Add custom parameter to force account selection
          // This is the key - it forces the account picker without signing out
          googleProvider.setCustomParameters({
            'prompt': 'select_account', // Forces account picker every time
          });

          Logger.info('🔵 Calling signInWithProvider with account picker...');
          
          final UserCredential userCredential = await _auth
              .signInWithProvider(googleProvider)
              .timeout(const Duration(seconds: 60));
          user = userCredential.user;
          
          Logger.info('🔵 signInWithProvider completed');
          Logger.info('🔵 User: ${user?.email}');
        } on TimeoutException catch (e) {
          Logger.error('❌ Google sign-in timed out: $e');
          return null;
        } on FirebaseAuthException catch (e) {
          Logger.error('❌ FirebaseAuthException during Google sign-in');
          Logger.error('   Code: ${e.code}');
          Logger.error('   Message: ${e.message}');
          Logger.error('   Plugin: ${e.plugin}');
          Logger.error('   Stack trace: ${e.stackTrace}');
          
          // Heuristics for cancellation/back from provider UI on mobile
          final String code = e.code.toLowerCase();
          final String message = e.message?.toLowerCase() ?? '';
          if (code.contains('canceled') ||
              code.contains('cancelled') ||
              code.contains('aborted') ||
              code == 'web-context-canceled' ||
              message.contains('canceled') ||
              message.contains('cancelled') ||
              message.contains('aborted')) {
            Logger.info('ℹ️ Google sign-in cancelled by user');
            lastGoogleCancelled = true;
            return null;
          }
          return null;
        } catch (e) {
          Logger.error('❌ Unexpected error during Google sign-in: $e');
          Logger.error('   Error type: ${e.runtimeType}');
          Logger.error('   Error string: ${e.toString()}');
          return null;
        }
      }

      if (user != null) {
        // Extract profile information from Google user
        Map<String, dynamic> profileData = {'user': user};

        // Try multiple sources for display name (no reload needed)
        String? displayName = user.displayName;
        String? photoUrl = user.photoURL;
        String? phoneNumber = user.phoneNumber;

        // Check provider data for additional information
        for (final provider in user.providerData) {
          if (provider.providerId == 'google.com') {
            displayName = displayName ?? provider.displayName;
            photoUrl = photoUrl ?? provider.photoURL;
            phoneNumber = phoneNumber ?? provider.phoneNumber;

            // If we got a display name from provider, update Firebase user in background
            if (displayName != null &&
                displayName.isNotEmpty &&
                (user.displayName == null || user.displayName!.isEmpty)) {
              // Update display name in background (non-blocking)
              final userToUpdate = user;
              Future.microtask(() async {
                try {
                  await userToUpdate.updateDisplayName(displayName);
                  Logger.info(
                    'Updated Firebase displayName from Google provider',
                  );
                } catch (e) {
                  Logger.warning('Could not update displayName: $e');
                }
              });
            }
          }
        }

        // Extract name information from displayName
        if (displayName != null && displayName.isNotEmpty) {
          profileData['fullName'] = displayName;

          // Try to split full name into first and last name
          final nameParts = displayName.trim().split(' ');
          if (nameParts.isNotEmpty) {
            profileData['firstName'] = nameParts[0];
            if (nameParts.length > 1) {
              profileData['lastName'] = nameParts.sublist(1).join(' ');
            }
          }
        }

        // Add photo URL if available
        if (photoUrl != null && photoUrl.isNotEmpty) {
          profileData['photoUrl'] = photoUrl;
        }

        // Add phone number if available (rare for Google)
        if (phoneNumber != null && phoneNumber.isNotEmpty) {
          profileData['phoneNumber'] = phoneNumber;
        }

        Logger.info(
          'Google sign-in successful with profile data: ${profileData.keys}',
        );
        Logger.info('Display name extracted: "$displayName"');
        notifyListeners();
        return profileData;
      }

      return null;
    } on TimeoutException catch (error) {
      Logger.error('Google sign-in error: $error', error);
      return null;
    } catch (error) {
      final String message = error.toString().toLowerCase();
      if (message.contains('popup-closed-by-user') ||
          message.contains('canceled') ||
          message.contains('cancelled') ||
          message.contains('aborted')) {
        lastGoogleCancelled = true;
        Logger.info('Google sign-in cancelled (web or provider popup): $error');
        return null;
      }
      Logger.error('Google sign-in error: $error', error);
      return null;
    }
  }

  Future<Map<String, dynamic>?> loginWithApple() async {
    if (!AppConstants.enableAppleSignIn) {
      Logger.warning('Apple sign-in is disabled via feature flag');
      return null;
    }

    try {
      lastAppleCancelled = false;
      // Check if Apple Sign In is available
      if (!await SignInWithApple.isAvailable()) {
        Logger.warning('Apple Sign-In is not available on this device');
        return null;
      }

      // Request Apple ID credential with timeout
      final appleCredential =
          await SignInWithApple.getAppleIDCredential(
            scopes: [
              AppleIDAuthorizationScopes.email,
              AppleIDAuthorizationScopes.fullName,
            ],
            webAuthenticationOptions: WebAuthenticationOptions(
              clientId: 'com.stormdeve.orgami',
              redirectUri: Uri.parse(
                'https://orgamiapp.page.link/apple-signin',
              ),
            ),
          ).timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              Logger.error('Apple sign-in timed out');
              throw TimeoutException('Apple sign-in timed out');
            },
          );

      // Create OAuth credential for Firebase
      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      // Sign in with Firebase
      final UserCredential userCredential = await _auth
          .signInWithCredential(oauthCredential)
          .timeout(const Duration(seconds: 10));
      final User? user = userCredential.user;

      if (user != null) {
        // Extract profile information from Apple credentials
        Map<String, dynamic> profileData = {'user': user};

        // Extract first name and last name from Apple credential
        if (appleCredential.givenName != null) {
          profileData['firstName'] = appleCredential.givenName;
        }
        if (appleCredential.familyName != null) {
          profileData['lastName'] = appleCredential.familyName;
        }

        // Create full name from first and last name
        final fullName = [
          appleCredential.givenName,
          appleCredential.familyName,
        ].where((name) => name != null && name.isNotEmpty).join(' ');

        if (fullName.isNotEmpty) {
          profileData['fullName'] = fullName;

          // Update Firebase Auth display name in background if not set
          if (user.displayName == null || user.displayName!.isEmpty) {
            Future.microtask(() async {
              try {
                await user.updateDisplayName(fullName);
                Logger.info('Updated Firebase displayName from Apple');
              } catch (e) {
                Logger.warning('Could not update displayName: $e');
              }
            });
          }
        }

        Logger.info(
          'Apple sign-in successful with profile data: ${profileData.keys}',
        );
        notifyListeners();
        return profileData;
      }

      return null;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        Logger.info('Apple sign-in cancelled by user');
        lastAppleCancelled = true;
        return null;
      }
      Logger.error('Apple sign-in auth exception: $e', e);
      return null;
    } on TimeoutException catch (e) {
      Logger.error('Apple sign-in timeout: $e', e);
      return null;
    } catch (error) {
      Logger.error('Apple sign-in error: $error', error);
      return null;
    }
  }

  Future<User?> loginWithFacebook() async {
    // Facebook authentication temporarily disabled due to configuration issues
    Logger.warning('Facebook authentication is currently disabled');
    return null;

    /*
    try {
      // Trigger the Facebook authentication flow
      final LoginResult result = await FacebookAuth.instance.login(
        permissions: ['email', 'public_profile'],
      );

      if (result.status == LoginStatus.success) {
        // Get the access token
        final AccessToken accessToken = result.accessToken!;

        // Create a credential from the access token
        final OAuthCredential facebookAuthCredential =
            FacebookAuthProvider.credential(accessToken.tokenString);

        // Sign in with Firebase using the Facebook credential
        final UserCredential userCredential = await _auth.signInWithCredential(
          facebookAuthCredential,
        );
        final User? user = userCredential.user;

        if (user != null) {
          notifyListeners();
          return user;
        }
      } else if (result.status == LoginStatus.cancelled) {
        Logger.warning('Facebook sign-in was cancelled by user');
      } else if (result.status == LoginStatus.failed) {
        Logger.error('Facebook sign-in failed: ${result.message}', null);
      }

      return null;
    } catch (error) {
      Logger.error('Facebook sign-in error: $error', error);
      return null;
    }
    */
  }

  Future<User?> loginWithX() async {
    try {
      // X (Twitter) authentication using Firebase Auth provider directly
      // This requires server-side implementation or web-based OAuth flow

      if (kIsWeb) {
        // Web: Use popup-based authentication
        final TwitterAuthProvider twitterProvider = TwitterAuthProvider();
        final UserCredential userCredential = await _auth.signInWithPopup(
          twitterProvider,
        );
        final User? user = userCredential.user;

        if (user != null) {
          notifyListeners();
          return user;
        }
      } else {
        // Mobile: X authentication requires custom implementation
        // For now, show a message that it's not available on mobile
        Logger.warning(
          'X sign-in requires web-based authentication or custom server implementation',
        );
        return null;
      }

      return null;
    } catch (error) {
      Logger.error('X sign-in error: $error', error);
      return null;
    }
  }
}
