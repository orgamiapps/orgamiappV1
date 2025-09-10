import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/firebase_options.dart';
import 'package:attendus/Utils/platform_helper.dart';

/// Centralized, idempotent Firebase initialization with App Check.
class FirebaseInitializer {
  static Completer<void>? _completer;

  static Future<void> initializeOnce() async {
    if (_completer != null) return _completer!.future;
    _completer = Completer<void>();

    try {
      await PlatformHelper.isEmulator();

      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(
        PlatformHelper.getFirebaseTimeout(),
        onTimeout: () {
          Logger.warning(
            'Firebase initialization timed out, continuing anyway',
          );
          throw TimeoutException('Firebase initialization timeout');
        },
      );

      if (kDebugMode) {
        Logger.success('Firebase core initialized');
      }

      try {
        final AndroidProvider androidProvider = kDebugMode
            ? AndroidProvider.debug
            : AndroidProvider.playIntegrity;
        final AppleProvider appleProvider = kDebugMode
            ? AppleProvider.debug
            : AppleProvider.deviceCheck;

        await FirebaseAppCheck.instance.activate(
          androidProvider: androidProvider,
          appleProvider: appleProvider,
          webProvider: kDebugMode
              ? ReCaptchaV3Provider('recaptcha-v3-site-key')
              : ReCaptchaV3Provider('recaptcha-v3-site-key'),
        );

        Logger.info(
          'Firebase App Check activated (${kDebugMode ? 'debug' : 'playIntegrity'})',
        );
      } catch (e) {
        Logger.warning('App Check activation failed: $e');
      }

      _completer!.complete();
    } catch (e, st) {
      Logger.error('Firebase initialization failed', e, st);
      _completer!.completeError(e);
    }

    return _completer!.future;
  }
}
