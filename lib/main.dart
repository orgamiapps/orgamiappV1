import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:orgami/firebase_options.dart';
import 'package:orgami/Screens/Splash/splash_screen.dart';
import 'package:orgami/Utils/logger.dart';

import 'package:orgami/Utils/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:orgami/utils/error_handler.dart';

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
          home: homeOverride ?? const SplashScreen(),
        );
      },
    );
  }
}
