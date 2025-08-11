import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:orgami/Utils/logger.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class FirebaseGoogleAuthHelper extends ChangeNotifier {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
    ],
  );
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

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        ShowToast().showNormalToast(msg: 'Canceled!');

        return null; // The user canceled the sign-in
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );
      user = userCredential.user;
      notifyListeners();
      return user;
    } catch (error) {
      Logger.error('Google sign-in error: $error', error);
      return null;
    }
  }
}
