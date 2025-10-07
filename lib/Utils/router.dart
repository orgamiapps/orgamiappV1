import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:attendus/screens/Home/dashboard_screen.dart';
import 'package:attendus/main.dart' show appNavigatorKey;
import 'package:attendus/screens/Splash/second_splash_screen.dart';
import 'package:attendus/Utils/logger.dart';

/// Optimized router class with faster transitions and better performance
class RouterClass {
  static late BuildContext splashContext;

  // Optimized transition duration constants
  static const Duration _transitionDuration = Duration(milliseconds: 180);
  static const Duration _reverseTransitionDuration = Duration(milliseconds: 150);

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
          // Optimized fade transition with faster curve
          return FadeTransition(
            opacity: animation.drive(
              CurveTween(curve: Curves.easeOut), // Faster curve
            ),
            child: child,
          );
        },
        transitionDuration: _transitionDuration,
        reverseTransitionDuration: _reverseTransitionDuration,
      ),
      (route) => false,
    );
  }

/// Optimized page route with faster transitions
  static PageRouteBuilder<T> optimizedPageRoute<T>(
    Widget page, {
    bool useSlideTransition = false,
  }) {
    return PageRouteBuilder<T>(
      pageBuilder: (ctx, animation, secondaryAnimation) => page,
      transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
        if (useSlideTransition) {
          // Slide from right with optimized curve
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;

          final tween = Tween(begin: begin, end: end)
              .chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        } else {
          // Fast fade transition
          return FadeTransition(
            opacity: animation.drive(
              CurveTween(curve: Curves.easeOut),
            ),
            child: child,
          );
        }
      },
      transitionDuration: _transitionDuration,
      reverseTransitionDuration: _reverseTransitionDuration,
    );
  }

  static Future<T?> nextScreenNormal<T>(
    BuildContext context,
    Widget page, {
    bool useSlideTransition = false,
  }) {
    try {
      // Use optimized page route for better performance
      return Navigator.push<T>(
        context,
        optimizedPageRoute<T>(page, useSlideTransition: useSlideTransition),
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
