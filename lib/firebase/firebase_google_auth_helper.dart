import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:orgami/Utils/logger.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class FirebaseGoogleAuthHelper extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<User?> loginWithGoogle() async {
    User? user;
    try {
      if (kIsWeb) {
        // Web uses popup auth flow
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        final UserCredential userCredential =
            await _auth.signInWithPopup(googleProvider);
        user = userCredential.user;
        notifyListeners();
        return user;
      }

      // Mobile/desktop: use Firebase Auth's native provider sign-in
      final GoogleAuthProvider googleProvider = GoogleAuthProvider();
      googleProvider.addScope('email');
      final UserCredential userCredential =
          await _auth.signInWithProvider(googleProvider);
      user = userCredential.user;
      notifyListeners();
      return user;
    } catch (error) {
      Logger.error('Google sign-in error: $error', error);
      return null;
    }
  }
}
