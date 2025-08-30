import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/firebase_options.dart';
import 'package:attendus/screens/Splash/splash_screen.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/Utils/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:attendus/Utils/error_handler.dart';
import 'package:firebase_messaging/firebase_messaging.dart' as fcm;
// import 'package:firebase_app_check/firebase_app_check.dart'; // Commented out until App Check API is enabled
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:attendus/Services/notification_service.dart';
import 'package:attendus/firebase/firebase_messaging_helper.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize global error handling
  ErrorHandler.initialize();

  Logger.info('Starting app initialization...');

  // Initialize Firebase first (critical for app functionality)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    Logger.success('Firebase core initialized');
  } catch (e, st) {
    Logger.error('Firebase initialization failed', e, st);
  }

  // Initialize Stripe
  // TODO: Replace with your actual Stripe publishable key
  // For testing, you can use Stripe's test publishable key
  Stripe.publishableKey = 'pk_test_YOUR_PUBLISHABLE_KEY';
  Logger.info('Stripe initialized');

  // Run the app with minimal initialization
  runApp(
    ChangeNotifierProvider(
      create: (context) => ThemeProvider()..loadTheme(false), // Use default theme initially
      child: const MyApp(),
    ),
  );

  Logger.success('App initialization complete');

  // Defer heavy initialization to after first frame
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // Load theme preference and update if needed
    SharedPreferences.getInstance().then((prefs) {
      final isDarkMode = prefs.getBool('isDarkMode') ?? false;
      if (isDarkMode) {
        // Only update if not default
        ThemeProvider().loadTheme(isDarkMode);
      }
    });

    // Defer heavy initialization to after the app starts
    _initializeBackgroundServices();
  });
}

/// Initialize background services after app startup
Future<void> _initializeBackgroundServices() async {
  try {
    // Defer Firestore settings configuration
    Future.delayed(const Duration(seconds: 1), () {
      try {
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
      } catch (e) {
        Logger.warning('Configuring Firestore settings failed: $e');
      }
    });

    // Quick connectivity check without blocking
    Connectivity().checkConnectivity().then((connectivityResult) {
      bool isOffline = false;
      if (connectivityResult is ConnectivityResult) {
        isOffline = connectivityResult == ConnectivityResult.none;
      } else {
        // Handle newer API returning List<ConnectivityResult>
        final list = List<ConnectivityResult>.from(
          (connectivityResult as Iterable).cast<ConnectivityResult>(),
        );
        isOffline =
            list.isEmpty || list.every((c) => c == ConnectivityResult.none);
      }

      final bool isReachable = !isOffline;

    // Initialize App Check in background if reachable
    // TEMPORARILY DISABLED: App Check API needs to be enabled in Firebase Console
    // Uncomment this block after enabling the API at:
    // https://console.developers.google.com/apis/api/firebaseappcheck.googleapis.com/overview?project=951311475019
    /*
    if (isReachable) {
      FirebaseAppCheck.instance.activate(
        androidProvider: AndroidProvider.debug,
        appleProvider: AppleProvider.debug,
      ).catchError((e) {
        Logger.warning('App Check activation failed: $e');
      });
    }
    */

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
        Future.delayed(const Duration(seconds: 3), () {
          FirebaseMessagingHelper().initialize().catchError((e) {
            Logger.warning('Firebase Messaging initialization failed: $e');
          });
        });
      }
    }).catchError((e) {
      Logger.warning('Connectivity check failed: $e');
    });

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
