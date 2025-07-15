import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:orgami/Controller/CustomerController.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Images.dart';
import 'package:orgami/Utils/Router.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  double screenWidth = 1000;
  double screenHeight = 1000;

  // final User? _userData = FirebaseAuth.instance.currentUser;

  late AnimationController logoAnimation;

  _handleAnimation() {
    logoAnimation = AnimationController(
      upperBound: 500,
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    logoAnimation.forward();
    logoAnimation.addListener(() {
      setState(() {});
    });
  }

  Future<void> _getUser() async {
    User? firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser != null) {
      await FirebaseFirestoreHelper()
          .getSingleCustomer(customerId: firebaseUser.uid)
          .then((userData) {
        if (userData != null) {
          setState(() {
            CustomerController.logeInCustomer = userData;
          });
          RouterClass().homeScreenRoute(context: context);
        } else {
          FirebaseAuth.instance.signOut();
          Timer(const Duration(seconds: 3), () {
            RouterClass().secondSplashScreenRoute(context: context);
          });
        }
      });
    } else {
      Timer(const Duration(seconds: 5), () {
        RouterClass().secondSplashScreenRoute(context: context);
      });
    }
  }

  @override
  void initState() {
    _handleAnimation();

    // Timer(const Duration(seconds: 2), () {
    //   RouterClass().secondSplashScreenRoute(context: context);
    // });
    _getUser();

    super.initState();
  }

  @override
  void dispose() {
    logoAnimation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    screenWidth = MediaQuery.of(context).size.width;
    screenHeight = MediaQuery.of(context).size.height;
    return Scaffold(
      body: _bodyView(),
    );
  }

  Widget _bodyView() {
    return Container(
      width: screenWidth,
      height: screenHeight,
      decoration: const BoxDecoration(
        color: AppThemeColor.backGroundColor,
      ),
      child: Container(
        padding: const EdgeInsets.all(25),
        alignment: Alignment.center,
        child: Image.asset(
          Images.inAppLogo,
          width: logoAnimation.value,
        ),
      ),
    );
  }
}
