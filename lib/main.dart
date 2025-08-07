import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:orgami/firebase_options.dart';
import 'package:orgami/Screens/Splash/splash_screen.dart';
import 'package:orgami/Utils/logger.dart';

import 'package:orgami/Utils/theme_provider.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Logger.info('Starting app initialization...');

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    Logger.success('Firebase initialized successfully');
  } catch (e) {
    Logger.error('Firebase initialization failed', e);
  }

  Logger.success('App initialization complete');

  runApp(
    ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Orgami',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const SplashScreen(),
    );
  }
}
