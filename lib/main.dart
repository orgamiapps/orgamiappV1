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
import 'package:attendus/Services/navigation_state_service.dart';

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
  // OPTIMIZATION: Create ThemeProvider synchronously to avoid async SharedPreferences call on startup
  final themeProvider = ThemeProvider();

  final Widget appWidget = MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: themeProvider),
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
    // OPTIMIZATION: Load theme preference asynchronously without blocking UI
    // The ThemeProvider is already initialized, just load the saved preference
    Future.microtask(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final isDarkMode = prefs.getBool('isDarkMode') ?? false;
        if (isDarkMode != themeProvider.isDarkMode) {
          themeProvider.loadTheme(isDarkMode);
        }
      } catch (e) {
        if (kDebugMode) {
          Logger.warning('Failed to load saved theme: $e');
        }
      }
    });

    // Initialize background services (non-blocking)
    _initializeBackgroundServices();

    // PERFORMANCE: Delay subscription service initialization to reduce startup time
    // OPTIMIZATION: Reduced from 2s to 1.5s to improve user experience
    Future.delayed(const Duration(milliseconds: 1500), () {
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
          // OPTIMIZATION: Reduced from 500ms to 300ms
          Future.delayed(const Duration(milliseconds: 300), () {
            final creationLimitService = Provider.of<CreationLimitService>(
              context,
              listen: false,
            );
            creationLimitService.initialize().catchError((e) {
              Logger.warning(
                'Creation limit service initialization failed: $e',
              );
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
      // OPTIMIZATION: Further reduced cache sizes for even faster app startup
      cacheSizeBytes: kDebugMode
          ? 10 *
                1024 *
                1024 // 10MB in debug mode (reduced from 20MB)
          : 20 * 1024 * 1024, // 20MB in release (reduced from 40MB)
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
          // OPTIMIZATION: Reduced from 500ms to 300ms
          Future.delayed(const Duration(milliseconds: 300), () {
            NotificationService.initialize().catchError((e) {
              Logger.warning('Notification service initialization failed: $e');
              return;
            });
          });

          // PERFORMANCE: Initialize Firebase Messaging in background if online
          // OPTIMIZATION: Reduced delay from 3s to 2s
          if (isReachable) {
            Future.delayed(const Duration(seconds: 2), () {
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

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.homeOverride});

  // Allows tests to inject a simple home to avoid heavy initialization in widgets
  final Widget? homeOverride;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final NavigationStateService _navStateService = NavigationStateService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Initialize navigation state service
    _navStateService.initialize();
    Logger.debug('MyApp: Added lifecycle observer');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Logger.debug('MyApp: Removed lifecycle observer');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (kDebugMode) {
      Logger.debug('App lifecycle state changed to: $state');
    }

    switch (state) {
      case AppLifecycleState.paused:
        // App is going to background - navigation state is already saved by observer
        Logger.info('App paused - navigation state should be saved');
        break;
      case AppLifecycleState.resumed:
        // App is coming back to foreground
        Logger.info('App resumed - navigation state will be restored on next launch');
        break;
      case AppLifecycleState.inactive:
        // App is inactive (e.g., during phone call)
        Logger.debug('App inactive');
        break;
      case AppLifecycleState.detached:
        // App is detached
        Logger.debug('App detached');
        break;
      case AppLifecycleState.hidden:
        // App is hidden
        Logger.debug('App hidden');
        break;
    }
  }

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
          home: widget.homeOverride ?? const AuthGate(),
          // Add navigation observer for debugging and state tracking
          navigatorObservers: [_NavigationLogger()],
        );
      },
    );
  }
}

/// Navigation observer for logging navigation events and saving state
class _NavigationLogger extends NavigatorObserver {
  final NavigationStateService _navStateService = NavigationStateService();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (kDebugMode) {
      Logger.debug(
        'Navigation: Pushed ${route.settings.name ?? 'unnamed route'}',
      );
    }
    
    // Save navigation state
    _saveRouteState(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (kDebugMode) {
      Logger.debug(
        'Navigation: Popped ${route.settings.name ?? 'unnamed route'}',
      );
    }
    
    // Save previous route state when popping
    if (previousRoute != null) {
      _saveRouteState(previousRoute);
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
    
    // Save new route state
    if (newRoute != null) {
      _saveRouteState(newRoute);
    }
  }

  /// Save route state to NavigationStateService
  void _saveRouteState(Route<dynamic> route) {
    try {
      // Skip modal routes and dialog routes
      if (route is! ModalRoute || route is PopupRoute) {
        return;
      }
      
      _navStateService.trackRoute(route);
    } catch (e) {
      if (kDebugMode) {
        Logger.error('Error saving route state: $e');
      }
    }
  }
}
