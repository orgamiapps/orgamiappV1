import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/Utils/app_constants.dart';
import 'package:attendus/firebase_options.dart';
import 'package:attendus/Utils/platform_helper.dart';

/// Centralized, idempotent Firebase initialization with App Check.
class FirebaseInitializer {
  static Completer<void>? _completer;
  static bool _completedSuccessfully = false;

  static Future<void> initializeOnce() async {
    if (_completer != null) return _completer!.future;
    _completer = Completer<void>();
    _completedSuccessfully = false;

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
        if (kIsWeb) {
          final siteKey = AppConstants.appCheckWebRecaptchaSiteKey.trim();
          if (!AppConstants.enableWebAppCheck || siteKey.isEmpty) {
            Logger.info(
              'Web App Check skipped. Configure ATTENDUS_RECAPTCHA_V3_SITE_KEY '
              'and ATTENDUS_ENABLE_WEB_APP_CHECK=true before enabling enforcement.',
            );
          } else {
            await FirebaseAppCheck.instance.activate(
              webProvider: ReCaptchaV3Provider(siteKey),
            );
            Logger.info('Firebase App Check activated for web');
          }

          _completedSuccessfully = true;
          _completer!.complete();
          return;
        }

        final AndroidProvider androidProvider = kDebugMode
            ? AndroidProvider.debug
            : AndroidProvider.playIntegrity;
        final AppleProvider appleProvider = kDebugMode
            ? AppleProvider.debug
            : AppleProvider.deviceCheck;

        await FirebaseAppCheck.instance.activate(
          androidProvider: androidProvider,
          appleProvider: appleProvider,
        );

        Logger.info(
          'Firebase App Check activated (${kDebugMode ? 'debug' : 'playIntegrity'})',
        );
      } catch (e) {
        Logger.warning('App Check activation failed: $e');
      }

      _completedSuccessfully = true;
      _completer!.complete();
    } catch (e, st) {
      Logger.error('Firebase initialization failed', e, st);
      _completer!.completeError(e);
    }

    return _completer!.future;
  }

  /// Retries a failed initialization without starting duplicate concurrent
  /// attempts. A successful or in-flight initialization is reused.
  static Future<void> retry() {
    final completer = _completer;
    if (_completedSuccessfully ||
        (completer != null && !completer.isCompleted)) {
      return completer?.future ?? initializeOnce();
    }

    _completer = null;
    return initializeOnce();
  }
}
