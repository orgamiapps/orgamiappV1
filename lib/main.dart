import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:orgami/firebase_options.dart';
import 'package:orgami/Screens/Splash/splash_screen.dart';
import 'package:orgami/Utils/logger.dart';

import 'package:orgami/Utils/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orgami/utils/error_handler.dart';
import 'package:firebase_dynamic_links/firebase_dynamic_links.dart';
import 'package:orgami/Screens/Events/single_event_screen.dart';
import 'package:orgami/models/event_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

    Logger.success('Firebase initialized successfully');
  } catch (e) {
    Logger.error('Firebase initialization failed', e);
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

/// Initialize dynamic links after app start
class DynamicLinksInitializer {
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Handle when app is opened from a terminated state
    final PendingDynamicLinkData? initialLink =
        await FirebaseDynamicLinks.instance.getInitialLink();
    if (initialLink != null) {
      _handleLink(initialLink.link);
    }

    // Handle when app is in foreground/background
    FirebaseDynamicLinks.instance.onLink.listen((data) {
      _handleLink(data.link);
    }).onError((error) {
      Logger.error('Dynamic link error', error);
    });
  }

  static Future<void> _handleLink(Uri link) async {
    try {
      if (link.host.contains('orgami.app') && link.pathSegments.contains('invite')) {
        final eventId = link.queryParameters['eventId'];
        if (eventId != null && appNavigatorKey.currentState != null) {
          // Fetch event and navigate
          final snap = await FirebaseFirestore.instance
              .collection(EventModel.firebaseKey)
              .doc(eventId)
              .get();
          if (snap.exists) {
            final data = snap.data()!;
            data['id'] = snap.id;
            final event = EventModel.fromJson(data);
            appNavigatorKey.currentState!.push(
              MaterialPageRoute(
                builder: (_) => SingleEventScreen(eventModel: event),
              ),
            );
          }
        }
      }
    } catch (e) {
      Logger.error('Failed to handle dynamic link', e);
    }
  }
}
