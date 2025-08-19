import 'package:flutter/material.dart';
import 'dart:io' show InternetAddress;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:orgami/firebase_options.dart';
import 'package:orgami/Screens/Splash/splash_screen.dart';
import 'package:orgami/Utils/logger.dart';
import 'package:orgami/Utils/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orgami/Utils/error_handler.dart';
import 'package:firebase_messaging/firebase_messaging.dart' as fcm;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:orgami/Services/notification_service.dart';
import 'package:orgami/firebase/firebase_messaging_helper.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize global error handling
  ErrorHandler.initialize();

  Logger.info('Starting app initialization...');

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Enable Firestore offline persistence to keep app usable without network
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } catch (e, st) {
      Logger.warning('Configuring Firestore settings failed: $e');
      Logger.debug(st.toString());
    }

    // Detect connectivity and configure Firestore accordingly
    final connectivityResult = await Connectivity().checkConnectivity();
    bool isOffline = connectivityResult == ConnectivityResult.none;

    // Extra DNS checks to detect captive portals/DNS failures on emulator
    Future<bool> _dnsOkFor(String host) async {
      try {
        final lookup = await InternetAddress.lookup(host);
        return lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
      } catch (_) {
        return false;
      }
    }

    final bool dnsOk =
        await _dnsOkFor('firestore.googleapis.com') &&
        await _dnsOkFor('firebaseappcheck.googleapis.com') &&
        await _dnsOkFor('firebasestorage.googleapis.com');

    final bool isReachable = !isOffline && dnsOk;

    // App Check: only activate when network is reachable to avoid noisy DNS/AppCheck warnings
    if (isReachable) {
      try {
        await FirebaseAppCheck.instance.activate(
          androidProvider: AndroidProvider.debug,
          appleProvider: AppleProvider.debug,
        );
      } catch (e, st) {
        Logger.warning(
          'App Check activation failed, continuing without it: $e',
        );
        Logger.debug(st.toString());
      }
    } else {
      Logger.warning(
        'Skipping App Check activation while offline/DNS unavailable.',
      );
      try {
        await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(false);
      } catch (_) {}
    }

    if (!isReachable) {
      // Prevent Firestore from repeatedly attempting network calls when offline
      await FirebaseFirestore.instance.disableNetwork();
      Logger.warning(
        'No internet connection detected. Running in offline mode.',
      );
    } else {
      // Ensure network is enabled when connectivity is available
      await FirebaseFirestore.instance.enableNetwork();
    }

    // iOS/web foreground presentation options
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.iOS) {
      await fcm.FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );
    }

    // Android 13+ notifications permission
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }

    // Initialize local notifications and messaging helper
    await NotificationService.initialize();

    // Only initialize Firebase Messaging (which talks to Firestore) when online
    if (isReachable) {
      await FirebaseMessagingHelper().initialize();
    } else {
      Logger.warning(
        'Skipping Firebase Messaging initialization while offline.',
      );
    }

    Logger.success('Firebase initialized successfully');
  } catch (e, st) {
    Logger.error('Firebase initialization failed', e, st);
  }

  // Load theme preference
  final prefs = await SharedPreferences.getInstance();
  final isDarkMode = prefs.getBool('isDarkMode') ?? false;

  Logger.success('App initialization complete');

  runApp(
    ChangeNotifierProvider(
      create: (context) => ThemeProvider()..loadTheme(isDarkMode),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.homeOverride});

  // Allows tests to inject a simple home to avoid heavy initialization in widgets
  final Widget? homeOverride;

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Orgami',
          theme: themeProvider.lightTheme,
          darkTheme: themeProvider.darkTheme,
          themeMode: themeProvider.themeMode,
          navigatorKey: appNavigatorKey,
          home: homeOverride ?? const SplashScreen(),
        );
      },
    );
  }
}
