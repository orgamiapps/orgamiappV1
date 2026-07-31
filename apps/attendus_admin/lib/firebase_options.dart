import 'package:firebase_core/firebase_core.dart';

class AdminFirebaseOptions {
  static const _apiKey = String.fromEnvironment('ATTENDUS_FIREBASE_API_KEY');
  static FirebaseOptions get windows {
    if (_apiKey.isEmpty) {
      throw StateError(
        'ATTENDUS_FIREBASE_API_KEY must be supplied at build time and API-restricted before distribution.',
      );
    }
    return const FirebaseOptions(
      apiKey: _apiKey,
      appId: '1:951311475019:web:c6d429ef1386b91d89c8ce',
      messagingSenderId: '951311475019',
      projectId: 'orgami-66nxok',
      authDomain: 'orgami-66nxok.firebaseapp.com',
      storageBucket: 'orgami-66nxok.appspot.com',
    );
  }
}
