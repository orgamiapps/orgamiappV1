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
    show kIsWeb, kDebugMode, defaultTargetPlatform, TargetPlatform;
import 'package:attendus/Services/notification_service.dart';
import 'package:attendus/firebase/firebase_messaging_helper.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize global error handling
  ErrorHandler.initialize();

  if (kDebugMode) {
    Logger.info('Starting app initialization...');
  }

  // Run the app immediately with minimal setup
  runApp(
    ChangeNotifierProvider(
      create: (context) => ThemeProvider(), // Don't load theme yet
      child: const MyApp(),
    ),
  );

  // Initialize Firebase and other services after the app has started rendering
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final Stopwatch startupStopwatch = Stopwatch()..start();

    // Initialize Firebase in background
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
        .then((_) {
          if (kDebugMode) {
            Logger.success('Firebase core initialized');
            Logger.info(
              'T+${startupStopwatch.elapsed.inMilliseconds}ms: Firebase init done',
            );
          }

          // Initialize Stripe after Firebase
          Stripe.publishableKey = 'pk_test_YOUR_PUBLISHABLE_KEY';
          if (kDebugMode) {
            Logger.info('Stripe initialized');
          }

          // Load theme preference after app is running
          SharedPreferences.getInstance().then((prefs) {
            final isDarkMode = prefs.getBool('isDarkMode') ?? false;
            final context = appNavigatorKey.currentContext;
            if (context != null) {
              try {
                final themeProvider = Provider.of<ThemeProvider>(
                  context,
                  listen: false,
                );
                themeProvider.loadTheme(isDarkMode);
              } catch (e) {
                if (kDebugMode) {
                  Logger.warning('Failed to apply saved theme: $e');
                }
              }
            }
          });

          // Initialize background services
          _initializeBackgroundServices();

          if (kDebugMode) {
            Logger.success('App initialization complete');
            Logger.info(
              'T+${startupStopwatch.elapsed.inMilliseconds}ms: All services initialized',
            );
          }
        })
        .catchError((e, st) {
          if (kDebugMode) {
            Logger.error('Firebase initialization failed', e, st);
          }
        });
  });
}

/// Initialize background services after app startup
Future<void> _initializeBackgroundServices() async {
  try {
    // Configure Firestore settings immediately but don't wait
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    // Quick connectivity check without blocking
    Connectivity()
        .checkConnectivity()
        .then((connectivityResult) {
          bool isOffline = false;
          // Handle newer API returning List<ConnectivityResult>
          if (connectivityResult is List<ConnectivityResult>) {
            isOffline =
                connectivityResult.isEmpty ||
                connectivityResult.every((c) => c == ConnectivityResult.none);
          } else if (connectivityResult is ConnectivityResult) {
            // Handle older API returning single ConnectivityResult
            isOffline = connectivityResult == ConnectivityResult.none;
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
                  Logger.warning(
                    'Failed to request notification permission: $e',
                  );
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
        })
        .catchError((e) {
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
