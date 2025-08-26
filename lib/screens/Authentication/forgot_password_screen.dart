import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:orgami/Utils/colors.dart';
import 'package:orgami/Utils/images.dart';
import 'package:flutter/foundation.dart';
import 'package:orgami/Utils/toast.dart';
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
      backgroundColor: Colors.white,
      body: Stack(children: [_bodyView(), _modernAppBar()]),
    );
  }

  Widget _modernAppBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppThemeColor.darkBlueColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppThemeColor.darkBlueColor.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(context),
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: AppThemeColor.darkBlueColor,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bodyView() {
    return Container(
      width: _screenWidth,
      height: _screenHeight,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            AppThemeColor.lightBlueColor.withValues(alpha: 0.4),
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                children: [
                  const SizedBox(height: 60),
                  _logoSection(),
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

  Widget _logoSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppThemeColor.darkBlueColor.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, 12),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Image.asset(Images.inAppLogo, width: logoAnimation.value),
    );
  }

  Widget _labelView() {
    return Column(
      children: [
        Text(
          'Forgot Password?',
          style: TextStyle(
            color: AppThemeColor.darkBlueColor,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'No worries! Enter your email and we\'ll send you reset instructions.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppThemeColor.dullFontColor,
            fontSize: 16,
            fontWeight: FontWeight.w400,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _loginDetailsView() {
    return Container(
      width: _screenWidth,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppThemeColor.darkBlueColor.withValues(alpha: 0.06),
            blurRadius: 40,
            offset: const Offset(0, 8),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reset Password',
            style: TextStyle(
              color: AppThemeColor.darkBlueColor,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 28),
          _buildEmailField(),
          const SizedBox(height: 36),
          _buildResetButton(),
        ],
      ),
    );
  }

  Widget _buildEmailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Email Address',
          style: TextStyle(
            color: AppThemeColor.darkBlueColor,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _emailEdtController,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
          decoration: InputDecoration(
            hintText: 'Enter your email address',
            hintStyle: TextStyle(
              color: AppThemeColor.lightGrayColor,
              fontSize: 16,
            ),
            filled: true,
            fillColor: Colors.grey.withValues(alpha: 0.04),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: AppThemeColor.darkBlueColor,
                width: 2,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: Colors.grey.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 18,
            ),
            prefixIcon: Icon(
              Icons.email_outlined,
              color: AppThemeColor.lightGrayColor,
              size: 22,
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your email';
            }
            if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
              return 'Please enter a valid email address';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildResetButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: RoundedLoadingButton(
        animateOnTap: true,
        borderRadius: 16,
        controller: _btnCtlr,
        onPressed: () {
          _btnCtlr.start();
          _resetPassword();
        },
        color: AppThemeColor.darkBlueColor,
        elevation: 0,
        child: const Text(
          'Send Reset Link',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  void _resetPassword() async {
    try {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: _emailEdtController.text)
          .then((value) {
            ShowToast().showNormalToast(
              msg: 'Password reset link sent to your email!',
            );
            _btnCtlr.success();
            Timer(const Duration(seconds: 2), () {
              Navigator.pop(context);
            });
          });
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        debugPrint(e.code);
      }
      switch (e.code) {
        case "user-not-found":
          ShowToast().showNormalToast(
            msg: "No user found with this email address.",
          );
          break;
        case "invalid-email":
          ShowToast().showNormalToast(
            msg: "Please enter a valid email address.",
          );
          break;
        case "too-many-requests":
          ShowToast().showNormalToast(
            msg: "Too many requests. Please try again later.",
          );
          break;
        default:
          ShowToast().showNormalToast(
            msg: "An error occurred. Please try again.",
          );
      }
      _btnCtlr.reset();
    } catch (e) {
      _btnCtlr.reset();
      if (kDebugMode) {
        debugPrint('Error resetting password: $e');
      }
      ShowToast().showNormalToast(msg: "An error occurred. Please try again.");
    }
  }
}
