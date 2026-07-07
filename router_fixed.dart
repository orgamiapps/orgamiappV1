import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:attendus/screens/Home/analytics_dashboard_screen.dart';
import 'package:attendus/screens/Splash/second_splash_screen.dart';

class RouterClass {
  static late BuildContext splashContext;
  Future<T?> appLogout<T>({required BuildContext context}) =>
      Navigator.of(context, rootNavigator: false).pushAndRemoveUntil(
        CupertinoPageRoute(
          builder: (BuildContext context) {
            return const SecondSplashScreen();
          },
        ),
        (_) => false,
      );

  Future<T?> appRest<T>({required BuildContext context}) =>
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const SecondSplashScreen()),
        (route) => false,
      );

  Future<T?> secondSplashScreenRoute<T>({required BuildContext context}) =>
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (splashContext) => const SecondSplashScreen(),
        ),
      );
  Future<T?> homeScreenRoute<T>({required BuildContext context}) =>
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (splashContext) => const AnalyticsDashboardScreen(),
        ),
        (route) => false,
      );

  static Future<T?> nextScreenNormal<T>(BuildContext context, Widget page) {
    return Navigator.push<T>(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
  }

  static Future<T?> nextScreenAndReplacement<T>(
    BuildContext context,
    Widget page,
  ) {
    return Navigator.pushReplacement<T, T>(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
  }

  static Future<T?> nextScreenAndReplacementAndRemoveUntil<T>({
    required BuildContext context,
    required Widget page,
  }) {
    return Navigator.pushAndRemoveUntil<T>(
      context,
      MaterialPageRoute(builder: (context) => page),
      (route) => false,
    );
  }
}
