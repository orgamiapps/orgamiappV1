import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:orgami/screens/Home/home_screen.dart';
import 'package:orgami/screens/Splash/second_splash_screen.dart';

class RouterClass {
  static late BuildContext splashContext;
  appLogout({required BuildContext context}) =>
      Navigator.of(context, rootNavigator: false).pushAndRemoveUntil(
        CupertinoPageRoute(
          builder: (BuildContext context) {
            return const SecondSplashScreen();
          },
        ),
        (_) => false,
      );

  appRest({required BuildContext context}) => Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (context) => const SecondSplashScreen()),
    (route) => false,
  );

  secondSplashScreenRoute({required BuildContext context}) =>
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (splashContext) => const SecondSplashScreen(),
        ),
      );
  homeScreenRoute({required BuildContext context}) =>
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (splashContext) => const HomeScreen()),
        (route) => false,
      );

  static void nextScreenNormal(context, page) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }

  static void nextScreenAndReplacement(context, page) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
  }

  static nextScreenAndReplacementAndRemoveUntil({
    required BuildContext context,
    required Widget page,
  }) => Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (context) => page),
    (route) => false,
  );
}
