import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:attendus/Utils/app_constants.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
// import 'package:twitter_login/twitter_login.dart'; // Disabled due to namespace issues

class FirebaseGoogleAuthHelper extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<User?> loginWithGoogle() async {
    User? user;
    try {
      if (kIsWeb) {
        // Web uses popup auth flow
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        final UserCredential userCredential = await _auth.signInWithPopup(
          googleProvider,
        );
        user = userCredential.user;
        notifyListeners();
        return user;
      }

      // Mobile/desktop: use Firebase Auth's native provider sign-in
      final GoogleAuthProvider googleProvider = GoogleAuthProvider();
      googleProvider.addScope('email');
      final UserCredential userCredential = await _auth.signInWithProvider(
        googleProvider,
      );
      user = userCredential.user;
      notifyListeners();
      return user;
    } catch (error) {
      Logger.error('Google sign-in error: $error', error);
      return null;
    }
  }

  Future<User?> loginWithApple() async {
    if (!AppConstants.enableAppleSignIn) {
      Logger.warning('Apple sign-in is disabled via feature flag');
      return null;
    }

    try {
      // Check if Apple Sign In is available
      if (!await SignInWithApple.isAvailable()) {
        Logger.warning('Apple Sign-In is not available on this device');
        return null;
      }

      // Request Apple ID credential
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        webAuthenticationOptions: WebAuthenticationOptions(
          clientId: 'com.stormdeve.orgami',
          redirectUri: Uri.parse('https://orgamiapp.page.link/apple-signin'),
        ),
      );

      // Create OAuth credential for Firebase
      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      // Sign in with Firebase
      final UserCredential userCredential = await _auth.signInWithCredential(
        oauthCredential,
      );
      final User? user = userCredential.user;

      if (user != null) {
        // Update display name if it's not set and we have name info from Apple
        if (user.displayName == null || user.displayName!.isEmpty) {
          final fullName =
              appleCredential.givenName != null &&
                  appleCredential.familyName != null
              ? '${appleCredential.givenName} ${appleCredential.familyName}'
              : null;

          if (fullName != null && fullName.isNotEmpty) {
            await user.updateDisplayName(fullName);
          }
        }

        notifyListeners();
        return user;
      }

      return null;
    } catch (error) {
      Logger.error('Apple sign-in error: $error', error);
      return null;
    }
  }

  Future<User?> loginWithFacebook() async {
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
