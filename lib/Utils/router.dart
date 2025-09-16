import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:attendus/screens/Home/dashboard_screen.dart';
import 'package:attendus/main.dart' show appNavigatorKey;
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

  Future<T?> homeScreenRoute<T>({required BuildContext context}) {
    final navigator =
        appNavigatorKey.currentState ??
        Navigator.of(context, rootNavigator: true);
    return navigator.pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (ctx, a, b) => const DashboardScreen(),
        transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation.drive(CurveTween(curve: Curves.easeInOut)),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 200),
      ),
      (route) => false,
    );
  }

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
