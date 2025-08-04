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
    try {
      User? firebaseUser = FirebaseAuth.instance.currentUser;

      if (firebaseUser != null) {
        print('🔍 User found: ${firebaseUser.uid}');

        // Add timeout to prevent infinite loading
        final userData = await FirebaseFirestoreHelper()
            .getSingleCustomer(customerId: firebaseUser.uid)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                print('⏰ Timeout getting user data');
                return null;
              },
            );

        if (userData != null) {
          setState(() {
            CustomerController.logeInCustomer = userData;
          });
          print('✅ User data loaded successfully');
          RouterClass().homeScreenRoute(context: context);
        } else {
          print('❌ User data is null');
          _showErrorDialog();
        }
      } else {
        print('🔍 No user found, navigating to second splash');
        Timer(const Duration(seconds: 2), () {
          RouterClass().secondSplashScreenRoute(context: context);
        });
      }
    } catch (e) {
      print('❌ Error in _getUser: $e');
      _showErrorDialog();
    }
  }

  void _showErrorDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Error'),
          content: const Text('Failed to load user data. Please try again.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _getUser(); // Retry
              },
              child: const Text('Retry'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                FirebaseAuth.instance.signOut();
                Timer(const Duration(seconds: 1), () {
                  RouterClass().secondSplashScreenRoute(context: context);
                });
              },
              child: const Text('Sign Out'),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _handleAnimation();

    // Add a timeout to prevent infinite loading
    Timer(const Duration(seconds: 15), () {
      if (mounted) {
        print('⏰ Splash screen timeout - forcing navigation');
        RouterClass().secondSplashScreenRoute(context: context);
      }
    });

    _getUser();
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
    return Scaffold(body: _bodyView());
  }

  Widget _bodyView() {
    return Container(
      width: screenWidth,
      height: screenHeight,
      decoration: const BoxDecoration(color: AppThemeColor.backGroundColor),
      child: Container(
        padding: const EdgeInsets.all(25),
        alignment: Alignment.center,
        child: Image.asset(Images.inAppLogo, width: logoAnimation.value),
      ),
    );
  }
}
