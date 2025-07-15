import 'package:flutter/material.dart';
import 'package:orgami/Screens/Authentication/LoginScreen.dart';
import 'package:orgami/Screens/Authentication/SignupScreen.dart';
import 'package:orgami/Screens/QRScanner/QrScannerWithoutLoginScreen.dart';
import 'package:orgami/Screens/Splash/Widgets/SocialIconsView.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Images.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/dimensions.dart';

class SecondSplashScreen extends StatefulWidget {
  const SecondSplashScreen({super.key});

  @override
  State<SecondSplashScreen> createState() => _SecondSplashScreenState();
}

class _SecondSplashScreenState extends State<SecondSplashScreen>
    with SingleTickerProviderStateMixin {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  late AnimationController logoAnimation;

  _handleAnimation() {
    logoAnimation = AnimationController(
      upperBound: 250,
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    logoAnimation.forward();
    logoAnimation.addListener(() {
      setState(() {});
    });
  }

  @override
  void initState() {
    _handleAnimation();

    super.initState();
  }

  @override
  void dispose() {
    logoAnimation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _bodyView(),
    );
  }

  Widget _bodyView() {
    return Container(
      width: _screenWidth,
      height: _screenHeight,
      decoration: const BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
      ),
      padding: const EdgeInsets.all(25),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(),
          Image.asset(
            Images.inAppLogo,
            width: logoAnimation.value,
          ),
          _labelView(),
          _centerImageView(),
          const SizedBox(),
          _buttonsView(),
        ],
      ),
    );
  }

  Widget _centerImageView() {
    return GestureDetector(
      onTap: () => RouterClass.nextScreenNormal(
        context,
        QRScannerWithoutLoginScreen(),
      ),
      child: Image.asset(
        Images.qrCode,
        height: _screenHeight / 3.5,
      ),
    );
  }

  Widget _buttonsView() {
    return Column(
      children: [
        GestureDetector(
          onTap: () => RouterClass.nextScreenNormal(
            context,
            const SignupScreen(),
          ),
          child: _singleButtonView(label: 'Sign Up'),
        ),
        GestureDetector(
          onTap: () => RouterClass.nextScreenNormal(
            context,
            const LoginScreen(),
          ),
          child: _singleButtonView(label: 'Login'),
        ),
        const SizedBox(
          height: 20,
        ),
        const Text(
          'Continue With',
          style: TextStyle(
            color: AppThemeColor.pureBlackColor,
            fontSize: Dimensions.fontSizeExtraSmall,
          ),
        ),
        const SocialLoginView(),
      ],
    );
  }

  Widget _singleButtonView({required String label}) {
    return Container(
      decoration: BoxDecoration(
        color: AppThemeColor.darkBlueColor,
        borderRadius: BorderRadius.circular(20),
      ),
      width: 200,
      height: 40,
      margin: const EdgeInsets.only(bottom: 15),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: AppThemeColor.pureWhiteColor,
            fontSize: Dimensions.fontSizeLarge,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _labelView() {
    return const Column(
      children: [
        Text(
          'Welcome!',
          style: TextStyle(
            color: AppThemeColor.darkBlueColor,
            fontSize: 34,
            fontWeight: FontWeight.w700,
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 15.0),
          child: Text(
            'Thanks for joining! Access or create your account below, and get started on your journey!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppThemeColor.dullFontColor,
              fontSize: Dimensions.fontSizeLarge,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
