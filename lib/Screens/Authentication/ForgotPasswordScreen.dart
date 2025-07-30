import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:orgami/Utils/AppAppBarView.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Images.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  final _btnCtlr = RoundedLoadingButtonController();
  final TextEditingController _emailEdtController = TextEditingController();
  late AnimationController logoAnimation;

  @override
  void initState() {
    super.initState();
    _handleAnimation();
  }

  @override
  void dispose() {
    logoAnimation.dispose();
    super.dispose();
  }

  void _handleAnimation() {
    logoAnimation = AnimationController(
      upperBound: 140,
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    logoAnimation.forward();
    logoAnimation.addListener(() {
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _bodyView(),
          AppAppBarView.appBarWithOnlyBackButton(context: context),
        ],
      ),
    );
  }

  Widget _bodyView() {
    return Container(
      width: _screenWidth,
      height: _screenHeight,
      decoration: const BoxDecoration(),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                children: [
                  Image.asset(
                    Images.inAppLogo,
                    width: logoAnimation.value,
                  ),
                  const SizedBox(height: 30),
                  _labelView(),
                ],
              ),
              _loginDetailsView(),
              const SizedBox(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loginDetailsView() {
    return Container(
      width: _screenWidth,
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.grey[300]!,
            spreadRadius: 1,
            blurRadius: 7,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      padding: const EdgeInsets.all(15),
      child: Column(
        children: [
          Text(
            'Enter Your valid email Address',
            style: TextStyle(
              color: AppThemeColor.pureBlackColor,
              fontSize: Dimensions.fontSizeLarge,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 15),
          TextFormField(
            controller: _emailEdtController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              hintText: 'example@mail.com',
              labelText: 'Email',
              hintStyle: const TextStyle(
                color: AppThemeColor.lightGrayColor,
              ),
            ),
          ),
          const SizedBox(height: 25),
          RoundedLoadingButton(
            animateOnTap: true,
            borderRadius: 13,
            width: _screenWidth,
            controller: _btnCtlr,
            onPressed: () async {
              _btnCtlr.start();
              if (_emailEdtController.text.isNotEmpty) {
                try {
                  await FirebaseAuth.instance
                      .sendPasswordResetEmail(email: _emailEdtController.text);
                  _btnCtlr.success();
                  ShowToast().showSnackBar(
                    'Please Check Your Email!',
                    context,
                  );
                  Timer(const Duration(seconds: 2), () {
                    RouterClass().appRest(context: context);
                  });
                } catch (e) {
                  _btnCtlr.error();
                  ShowToast().showSnackBar(
                    'Error: ${e.toString()}',
                    context,
                  );
                }
              }
            },
            color: AppThemeColor.darkGreenColor,
            elevation: 0,
            child: const Text(
              'Recover My Password',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _labelView() {
    return Column(
      children: [
        const Text(
          'Welcome Back!',
          style: TextStyle(
            color: AppThemeColor.darkBlueColor,
            fontSize: 34,
            fontWeight: FontWeight.w700,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15.0),
          child: Text(
            'Fill out the information below for recover your account.',
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
