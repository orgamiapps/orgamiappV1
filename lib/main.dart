import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:orgami/firebase_options.dart';
import 'package:orgami/Screens/Splash/splash_screen.dart';
import 'package:orgami/Utils/logger.dart';
import 'package:orgami/Utils/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orgami/utils/error_handler.dart';
import 'package:firebase_messaging/firebase_messaging.dart' as fcm;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:orgami/Services/notification_service.dart';
import 'package:orgami/firebase/firebase_messaging_helper.dart';

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

    // iOS/web foreground presentation options
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.iOS) {
      await fcm.FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    // Android 13+ notifications permission
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }

    // Initialize local notifications and messaging helper
    await NotificationService.initialize();
    await FirebaseMessagingHelper().initialize();

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
