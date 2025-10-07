import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:attendus/screens/Home/dashboard_screen.dart';
import 'package:attendus/main.dart' show appNavigatorKey;
import 'package:attendus/screens/Splash/second_splash_screen.dart';
import 'package:attendus/Utils/logger.dart';

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
    try {
      return Navigator.push<T>(
        context,
        MaterialPageRoute(builder: (context) => page),
      );
    } catch (e) {
      Logger.error('Navigation error in nextScreenNormal', e);
      return Future.value(null);
    }
  }

  static Future<T?> nextScreenAndReplacement<T>(
    BuildContext context,
    Widget page,
  ) {
    try {
      return Navigator.pushReplacement<T, T>(
        context,
        MaterialPageRoute(builder: (context) => page),
      );
    } catch (e) {
      Logger.error('Navigation error in nextScreenAndReplacement', e);
      return Future.value(null);
    }
  }

  static Future<T?> nextScreenAndReplacementAndRemoveUntil<T>({
    required BuildContext context,
    required Widget page,
  }) {
    try {
      return Navigator.pushAndRemoveUntil<T>(
        context,
        MaterialPageRoute(builder: (context) => page),
        (route) => false,
      );
    } catch (e) {
      Logger.error('Navigation error in nextScreenAndReplacementAndRemoveUntil', e);
      return Future.value(null);
    }
  }
  
  /// Safely pop the navigation stack
  static void safelyPop(BuildContext context) {
    try {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        Logger.warning('Cannot pop - no routes in navigation stack');
      }
    } catch (e) {
      Logger.error('Error during navigation pop', e);
    }
  }
  
  /// Safely check if we can pop the navigation stack
  static bool canPop(BuildContext context) {
    try {
      return Navigator.of(context).canPop();
    } catch (e) {
      Logger.error('Error checking if can pop', e);
      return false;
    }
  }
}
