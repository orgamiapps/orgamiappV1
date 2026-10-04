import 'dart:async';

import 'package:attendus/Services/notification_service.dart';
import 'package:attendus/Utils/app_constants.dart';
import 'package:attendus/Utils/google_maps_bootstrap.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/firebase/firebase_messaging_helper.dart';
import 'package:firebase_messaging/firebase_messaging.dart' as fcm;
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// Loads optional integrations after Flutter has rendered its first frame.
///
/// Keeping this behind a deferred entry point lets the useful UI render before
/// these integrations perform network requests or other initialization work.
Future<void> initializeGoogleMaps() async {
  try {
    await GoogleMapsBootstrap.initialize(AppConstants.googleMapsWebApiKey);
    if (!GoogleMapsBootstrap.isAvailable &&
        GoogleMapsBootstrap.errorMessage != null) {
      Logger.warning(GoogleMapsBootstrap.errorMessage!);
    }
  } catch (e) {
    Logger.warning('Google Maps initialization failed: $e');
  }
}

Future<void> initializeOptionalServices() async {
  try {
    // Firestore handles offline/reconnection itself. Explicitly disabling its
    // network here left offline launches disconnected for the whole session.
    // Optional services are scheduled without waiting for network availability.
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.iOS) {
      unawaited(
        fcm.FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
              // The account-scoped foreground handler applies recipient and
              // preference checks before displaying exactly one local alert.
              alert: false,
              badge: false,
              sound: false,
            )
            .catchError((e) {
              Logger.warning('Failed to set notification options: $e');
            }),
      );
    }

    Future.delayed(const Duration(milliseconds: 300), () {
      NotificationService.initialize().catchError((e) {
        Logger.warning('Notification service initialization failed: $e');
      });
    });

    // Register auth/connectivity listeners even when launch is offline. The
    // helper bounds network work and retries registration after reconnection.
    Future.delayed(const Duration(seconds: 2), () {
      FirebaseMessagingHelper().initialize().catchError((e) {
        Logger.warning('Firebase Messaging initialization failed: $e');
      });
    });

    Logger.success('Optional background services initialized');
  } catch (e, st) {
    Logger.error('Optional services initialization failed: $e');
    Logger.error('Optional services stack trace: ${st.toString()}');
  }
}
