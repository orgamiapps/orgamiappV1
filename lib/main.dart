import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/widgets/auth_gate.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/Utils/theme_provider.dart';
import 'package:attendus/Services/subscription_service.dart';
import 'package:attendus/Services/creation_limit_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:attendus/Utils/error_handler.dart';
import 'package:firebase_messaging/firebase_messaging.dart' as fcm;
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
import 'package:attendus/Services/firebase_initializer.dart';

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
  // Made non-blocking to prevent startup delay
  EmulatorConfig.configureForEmulator();

  // Initialize Firebase BEFORE runApp to ensure it's ready when AuthGate loads
  // This prevents race conditions and ANR issues
  final Stopwatch startupStopwatch = Stopwatch()..start();
  Logger.info('Initializing Firebase before app startup...');

  try {
    await FirebaseInitializer.initializeOnce().timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        Logger.warning(
          'Firebase initialization timed out after 5 seconds, continuing anyway',
        );
      },
    );

    if (kDebugMode) {
      Logger.success('Firebase initialized successfully');
      Logger.info(
        'T+${startupStopwatch.elapsed.inMilliseconds}ms: Firebase ready',
      );
    }

    // Initialize Stripe after Firebase
    Stripe.publishableKey = 'pk_test_YOUR_PUBLISHABLE_KEY';
    if (kDebugMode) {
      Logger.info('Stripe initialized');
    }
  } catch (e) {
    Logger.warning('Firebase initialization failed, app will continue: $e');
    // Continue even if Firebase fails - app will handle gracefully
  }

  // Build the app after Firebase is ready
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
      ChangeNotifierProvider(
        create: (context) => CreationLimitService(),
        lazy: true, // Lazy load - only initialize when first accessed
      ),
    ],
    child: const MyApp(),
  );
  runApp(appWidget);

  // Initialize background services and theme after first frame
  WidgetsBinding.instance.addPostFrameCallback((_) async {
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

    // PERFORMANCE: Delay subscription service initialization to reduce startup time
    // Increased from 1s to 2s to prioritize UI rendering
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

          // PERFORMANCE: Initialize creation limit service with additional delay
          Future.delayed(const Duration(milliseconds: 500), () {
            final creationLimitService = Provider.of<CreationLimitService>(
              context,
              listen: false,
            );
            creationLimitService.initialize().catchError((e) {
              Logger.warning('Creation limit service initialization failed: $e');
            });
          });
        }
      } catch (e) {
        Logger.warning('Could not initialize services: $e');
      }
    });

    if (kDebugMode) {
      Logger.success('Background services initialization started');
      Logger.info(
        'T+${startupStopwatch.elapsed.inMilliseconds}ms: App fully rendered',
      );
    }
  });
}

/// Initialize background services after app startup
Future<void> _initializeBackgroundServices() async {
  try {
    // PERFORMANCE: Configure Firestore settings with aggressive memory optimization
    // Reduced cache size for faster startup and less memory pressure
    FirebaseFirestore.instance.settings = Settings(
      persistenceEnabled: true,
      // PERFORMANCE: Reduced cache size dramatically for faster app startup
      cacheSizeBytes: kDebugMode
          ? 20 *
                1024 *
                1024 // 20MB in debug mode (reduced from 40MB)
          : 40 * 1024 * 1024, // 40MB in release (reduced from 80MB)
    );

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

          // PERFORMANCE: Initialize notifications in background with minimal delay
          Future.delayed(const Duration(milliseconds: 500), () {
            NotificationService.initialize().catchError((e) {
              Logger.warning('Notification service initialization failed: $e');
              return;
            });
          });

          // PERFORMANCE: Initialize Firebase Messaging in background if online
          // Delayed further to reduce startup load
          if (isReachable) {
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
          // Add navigation observer for debugging
          navigatorObservers: [_NavigationLogger()],
        );
      },
    );
  }
}

/// Navigation observer for logging navigation events and catching errors
class _NavigationLogger extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (kDebugMode) {
      Logger.debug(
        'Navigation: Pushed ${route.settings.name ?? 'unnamed route'}',
      );
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (kDebugMode) {
      Logger.debug(
        'Navigation: Popped ${route.settings.name ?? 'unnamed route'}',
      );
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (kDebugMode) {
      Logger.debug(
        'Navigation: Removed ${route.settings.name ?? 'unnamed route'}',
      );
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (kDebugMode) {
      Logger.debug(
        'Navigation: Replaced ${oldRoute?.settings.name ?? 'unnamed'} with ${newRoute?.settings.name ?? 'unnamed'}',
      );
    }
  }
}
