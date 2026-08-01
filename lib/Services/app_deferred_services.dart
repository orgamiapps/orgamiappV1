import 'dart:async';

import 'package:attendus/Services/notification_service.dart';
import 'package:attendus/Utils/app_constants.dart';
import 'package:attendus/Utils/google_maps_bootstrap.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/Utils/platform_helper.dart';
import 'package:attendus/firebase/firebase_messaging_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart' as fcm;
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
    final connectivityResult = await Connectivity().checkConnectivity();
    final isOffline =
        connectivityResult.isEmpty ||
        connectivityResult.every((c) => c == ConnectivityResult.none);
    final isReachable = !isOffline;

    if (!isReachable) {
      unawaited(
        FirebaseFirestore.instance.disableNetwork().catchError((e) {
          Logger.warning('Failed to disable network: $e');
        }),
      );
    }

    if (kIsWeb || defaultTargetPlatform == TargetPlatform.iOS) {
      unawaited(
        fcm.FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
              alert: true,
              badge: true,
              sound: true,
            )
            .catchError((e) {
              Logger.warning('Failed to set notification options: $e');
            }),
      );
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(_requestAndroidNotificationPermission());
    }

    Future.delayed(const Duration(milliseconds: 300), () {
      NotificationService.initialize().catchError((e) {
        Logger.warning('Notification service initialization failed: $e');
      });
    });

    if (isReachable) {
      Future.delayed(const Duration(seconds: 2), () {
        FirebaseMessagingHelper().initialize().catchError((e) {
          Logger.warning('Firebase Messaging initialization failed: $e');
        });
      });
    }

    Logger.success('Optional background services initialized');
  } catch (e, st) {
    Logger.error('Optional services initialization failed: $e');
    Logger.error('Optional services stack trace: ${st.toString()}');
  }
}

Future<void> _requestAndroidNotificationPermission() async {
  if (await PlatformHelper.isEmulator()) {
    Logger.info('Skipping Android notification permission on emulator');
    return;
  }

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.requestNotificationsPermission();
}
