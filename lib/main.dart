import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'package:attendus/widgets/auth_gate.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/Utils/theme_provider.dart';
import 'package:attendus/Services/subscription_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:attendus/Utils/error_handler.dart';
import 'package:firebase_messaging/firebase_messaging.dart' as fcm;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, kDebugMode, defaultTargetPlatform, TargetPlatform;
import 'package:attendus/Services/notification_service.dart';
import 'package:attendus/firebase/firebase_messaging_helper.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:attendus/Utils/platform_helper.dart';
import 'package:attendus/Utils/emulator_config.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize global error handling with better crash reporting
  ErrorHandler.initialize();

  // Add additional memory and crash protection
  if (kDebugMode) {
    Logger.info('Debug mode: Enhanced error reporting enabled');
  }

  if (kDebugMode) {
    Logger.info('Starting app initialization...');
  }

  // Configure for emulator if needed (prevents Geolocator hanging)
  await EmulatorConfig.configureForEmulator();

  // Build the app immediately to keep UI responsive
  // Use lazy initialization for providers to improve startup time
  final Widget appWidget = MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create: (context) => ThemeProvider(),
        lazy: false, // Load immediately as it affects initial render
      ),
      ChangeNotifierProvider(
        create: (context) => SubscriptionService(),
        lazy: true, // Lazy load - only initialize when first accessed
      ),
    ],
    child: const MyApp(),
  );
  runApp(appWidget);

  // Initialize Firebase and services after first frame to avoid ANR
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final Stopwatch startupStopwatch = Stopwatch()..start();
    Logger.info('Starting Firebase initialization with timeout...');
    await PlatformHelper.isEmulator();

    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
        .timeout(
          PlatformHelper.getFirebaseTimeout(),
          onTimeout: () {
            Logger.warning(
              'Firebase initialization timed out, continuing anyway',
            );
            throw TimeoutException('Firebase initialization timeout');
          },
        )
        .then((_) async {
          if (kDebugMode) {
            Logger.success('Firebase core initialized');
            Logger.info(
              'T+${startupStopwatch.elapsed.inMilliseconds}ms: Firebase init done',
            );
          }

          // Activate Firebase App Check deterministically
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
              providerWeb: kDebugMode
                  ? ReCaptchaV3Provider('recaptcha-v3-site-key')
                  : ReCaptchaV3Provider('recaptcha-v3-site-key'),
            );

            Logger.info(
              'Firebase App Check activated (${kDebugMode ? 'debug' : 'playIntegrity'})',
            );
          } catch (e) {
            Logger.warning('App Check activation failed: $e');
          }

          // Initialize Stripe
          Stripe.publishableKey = 'pk_test_YOUR_PUBLISHABLE_KEY';
          if (kDebugMode) {
            Logger.info('Stripe initialized');
          }

          // Load theme preference
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

          // Initialize background services (non-blocking)
          _initializeBackgroundServices();

          // Delay subscription service initialization to reduce startup time
          // It will auto-initialize when first accessed due to lazy: true
          Future.delayed(const Duration(seconds: 2), () {
            try {
              final context = appNavigatorKey.currentContext;
              if (context != null) {
                final subscriptionService = Provider.of<SubscriptionService>(
                  context,
                  listen: false,
                );
                subscriptionService.initialize().catchError((e) {
                  Logger.warning('Subscription service initialization failed: $e');
                });
              }
            } catch (e) {
              Logger.warning('Could not initialize subscription service: $e');
            }
          });

          if (kDebugMode) {
            Logger.success('App initialization complete');
            Logger.info(
              'T+${startupStopwatch.elapsed.inMilliseconds}ms: All services initialized',
            );
          }
        })
        .catchError((e, st) {
          if (kDebugMode) {
            if (e is TimeoutException) {
              Logger.warning(
                'Firebase initialization timed out, app will continue',
              );
            } else {
              Logger.error('Firebase initialization failed', e, st);
            }
          }
          Logger.error('Stack trace context: ${st.toString()}');
        });
  });
}

/// Initialize background services after app startup
Future<void> _initializeBackgroundServices() async {
  try {
    // Configure Firestore settings with aggressive memory optimization
    FirebaseFirestore.instance.settings = Settings(
      persistenceEnabled: true,
      // Optimize cache size for better memory management
      cacheSizeBytes: kDebugMode
          ? 40 * 1024 * 1024  // 40MB in debug mode
          : 80 * 1024 * 1024, // 80MB in release (reduced from 100MB)
    );"}, {"old_string": "          // Initialize notifications in background\n          NotificationService.initialize().catchError((e) {\n            Logger.warning('Notification service initialization failed: $e');\n            return;\n          });\n\n          // Initialize Firebase Messaging in background if online\n          if (isReachable) {\n            // Delay messaging initialization to avoid blocking\n            Future.delayed(const Duration(seconds: 3), () {\n              FirebaseMessagingHelper().initialize().catchError((e) {\n                Logger.warning('Firebase Messaging initialization failed: $e');\n              });\n            });\n          }", "new_string": "          // Initialize notifications in background (delayed for faster startup)\n          Future.delayed(const Duration(milliseconds: 500), () {\n            NotificationService.initialize().catchError((e) {\n              Logger.warning('Notification service initialization failed: $e');\n              return;\n            });\n          });\n\n          // Initialize Firebase Messaging in background if online (increased delay)\n          if (isReachable) {\n            // Further delay messaging initialization to prioritize UI\n            Future.delayed(const Duration(seconds: 5), () {\n              FirebaseMessagingHelper().initialize().catchError((e) {\n                Logger.warning('Firebase Messaging initialization failed: $e');\n              });\n            });\n          }"}]

    // Quick connectivity check without blocking
    Connectivity()
        .checkConnectivity()
        .then((connectivityResult) {
          // Handle connectivity result (List<ConnectivityResult> in newer API)
          final bool isOffline =
              connectivityResult.isEmpty ||
              connectivityResult.every((c) => c == ConnectivityResult.none);

          final bool isReachable = !isOffline;

          // App Check is already activated above; avoid duplicate activation here

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

          // Android notifications permission - avoid prompting on emulator
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
            PlatformHelper.isEmulator().then((isEmulator) {
              if (isEmulator) {
                Logger.info(
                  'Skipping Android notification permission on emulator',
                );
                return;
              }
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
            });
          }

          // Initialize notifications in background (delayed for faster startup)
          Future.delayed(const Duration(milliseconds: 500), () {
            NotificationService.initialize().catchError((e) {
              Logger.warning('Notification service initialization failed: $e');
              return;
            });
          });

          // Initialize Firebase Messaging in background if online (increased delay)
          if (isReachable) {
            // Further delay messaging initialization to prioritize UI
            Future.delayed(const Duration(seconds: 5), () {
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
  } catch (e, st) {
    Logger.error('Background services initialization failed: $e');
    Logger.error('Background services stack trace: ${st.toString()}');

    // Attempt to continue with minimal functionality
    try {
      // Ensure basic Firestore functionality even if other services fail
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false, // Disable persistence if causing issues
        cacheSizeBytes: 10 * 1024 * 1024, // Minimal cache
      );
      Logger.info('Fallback to minimal Firestore configuration');
    } catch (fallbackError) {
      Logger.error('Even fallback configuration failed: $fallbackError');
    }
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
          home: homeOverride ?? const AuthGate(),
        );
      },
    );
  }
}
