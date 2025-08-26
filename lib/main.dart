import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:orgami/firebase_options.dart';
import 'package:orgami/screens/Splash/splash_screen.dart';
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
import 'package:flutter_localizations/flutter_localizations.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize global error handling
  ErrorHandler.initialize();

  Logger.info('Starting app initialization...');

  // Quick Firebase initialization
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    Logger.success('Firebase core initialized');
  } catch (e, st) {
    Logger.error('Firebase initialization failed', e, st);
  }

  // Load theme preference in parallel
  final themeFuture = SharedPreferences.getInstance().then(
    (prefs) => prefs.getBool('isDarkMode') ?? false,
  );

  // Get theme result
  final isDarkMode = await themeFuture;

  Logger.success('App initialization complete');

  // Run the app immediately
  runApp(
    ChangeNotifierProvider(
      create: (context) => ThemeProvider()..loadTheme(isDarkMode),
      child: const MyApp(),
    ),
  );

  // Defer heavy initialization to after the app starts
  _initializeBackgroundServices();
}

/// Initialize background services after app startup
Future<void> _initializeBackgroundServices() async {
  try {
    // Configure Firestore settings
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } catch (e) {
      Logger.warning('Configuring Firestore settings failed: $e');
    }

    // Quick connectivity check without DNS lookups
    final dynamic connectivityResult = await Connectivity().checkConnectivity();
    bool isOffline = false;
    if (connectivityResult is ConnectivityResult) {
      isOffline = connectivityResult == ConnectivityResult.none;
    } else if (connectivityResult is Iterable) {
      final list = List<ConnectivityResult>.from(
        connectivityResult.cast<ConnectivityResult>(),
      );
      isOffline =
          list.isEmpty || list.every((c) => c == ConnectivityResult.none);
    }

    // Skip DNS checks - they're blocking the main thread
    // Instead, just use connectivity status
    final bool isReachable = !isOffline;

    // Initialize App Check in background if reachable
    if (isReachable) {
      FirebaseAppCheck.instance.activate(
        androidProvider: AndroidProvider.debug,
        appleProvider: AppleProvider.debug,
      ).catchError((e) {
        Logger.warning('App Check activation failed: $e');
      });
    }

    // Configure Firestore network based on connectivity
    if (!isReachable) {
      FirebaseFirestore.instance.disableNetwork().catchError((e) {
        Logger.warning('Failed to disable network: $e');
      });
    }

    // iOS/web foreground presentation options
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.iOS) {
      fcm.FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          )
          .catchError((e) {
            Logger.warning('Failed to set notification options: $e');
          });
    }

    // Android notifications permission - non-blocking
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final plugin = FlutterLocalNotificationsPlugin();
      plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission()
          .catchError((e) {
            Logger.warning('Failed to request notification permission: $e');
            return false;
          });
    }

    // Initialize notifications in background
    NotificationService.initialize().catchError((e) {
      Logger.warning('Notification service initialization failed: $e');
      return;
    });

    // Initialize Firebase Messaging in background if online
    if (isReachable) {
      // Delay messaging initialization to avoid blocking
      Future.delayed(const Duration(seconds: 2), () {
        FirebaseMessagingHelper().initialize().catchError((e) {
          Logger.warning('Firebase Messaging initialization failed: $e');
        });
      });
    }

    Logger.success('Background services initialized');
  } catch (e) {
    Logger.error('Background services initialization failed: $e');
  }
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
          // Localization scaffolding removed until ARB/gen is configured
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          home: homeOverride ?? const SplashScreen(),
        );
      },
    );
  }
}
