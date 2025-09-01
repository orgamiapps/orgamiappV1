import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/screens/Authentication/forgot_password_screen.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/images.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/Utils/app_constants.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';
import 'package:attendus/firebase/firebase_google_auth_helper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final double _screenWidth = MediaQuery.of(context).size.width;
  late final double _screenHeight = MediaQuery.of(context).size.height;

  final _btnCtlr = RoundedLoadingButtonController();

  final TextEditingController _emailEdtController = TextEditingController();
  final TextEditingController _passwordEdtController = TextEditingController();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _isEmailFocused = false;
  bool _isPasswordFocused = false;

  late AnimationController logoAnimation;
  late Animation<double> fadeAnimation;
  late Animation<Offset> slideAnimation;

  void _makeLogin() async {
    try {
      String email = _emailEdtController.text,
          password = _passwordEdtController.text;

      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password)
          .then((UserCredential signInCustomer) async {
            final User? user = signInCustomer.user;
            if (user != null) {
              final fireStoreCustomer = await FirebaseFirestoreHelper()
                  .getSingleCustomer(customerId: user.uid);
              // Ensure user profile has all required fields
              await FirebaseFirestoreHelper().ensureUserProfileCompleteness(
                user.uid,
              );

              if (!mounted) return;
              setState(() {
                CustomerController.logeInCustomer = fireStoreCustomer;
              });
              RouterClass().homeScreenRoute(context: context);
              _btnCtlr.success();
            }
          });
    } on FirebaseAuthException catch (e) {
      Logger.warning('Firebase Auth Exception: ${e.code}');
      switch (e.code) {
        case "invalid-credential":
          ShowToast().showNormalToast(
            msg: "Invalid email or password. Please check your credentials.",
          );
          break;
        case "network-request-failed":
          ShowToast().showNormalToast(
            msg:
                "Network error. Please check your internet connection and try again.",
          );
          break;
        case "ERROR_WRONG_PASSWORD":
        case "wrong-password":
          ShowToast().showNormalToast(msg: "Your password is wrong.");
          break;
        case "ERROR_USER_NOT_FOUND":
        case "user-not-found":
          ShowToast().showNormalToast(
            msg: "User with this email doesn't exist.",
          );
          break;
        case "ERROR_USER_DISABLED":
        case "user-disabled":
          ShowToast().showNormalToast(
            msg: "User with this email has been disabled.",
          );
          break;
        case "ERROR_TOO_MANY_REQUESTS":
        case "too-many-requests":
          ShowToast().showNormalToast(
            msg: "Too many requests. Try again later.",
          );
          break;
        case "ERROR_OPERATION_NOT_ALLOWED":
        case "operation-not-allowed":
          ShowToast().showNormalToast(
            msg: "Signing in with Email and Password is not enabled.",
          );
          break;
        default:
          ShowToast().showNormalToast(
            msg: "Login failed: ${e.message ?? 'An undefined error happened.'}",
          );
      }
      _btnCtlr.reset();
    } catch (e) {
      _btnCtlr.reset();
      Logger.error('Error Making Login', e);
    }
  }

  void _handleAnimation() {
    logoAnimation = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: logoAnimation, curve: Curves.easeInOut));

    slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: logoAnimation, curve: Curves.easeOutCubic),
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
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              const SizedBox(height: 80),
              _logoSection(),
              const SizedBox(height: 40),
              _welcomeSection(),
              const SizedBox(height: 40),
              _loginFormSection(),
              const SizedBox(height: 30),
              _forgotPasswordSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logoSection() {
    return FadeTransition(
      opacity: fadeAnimation,
      child: SlideTransition(
        position: slideAnimation,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).shadowColor.withValues(alpha: 0.08),
                blurRadius: 30,
                offset: const Offset(0, 12),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Image.asset(Images.inAppLogo, width: 120, height: 120),
        ),
      ),
    );
  }

  Widget _welcomeSection() {
    return FadeTransition(
      opacity: fadeAnimation,
      child: Column(
        children: [
          Text(
            'Welcome Back!',
            style: TextStyle(
              color: AppThemeColor.darkBlueColor,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Sign in to continue to your account',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppThemeColor.dullFontColor,
              fontSize: 16,
              fontWeight: FontWeight.w400,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _loginFormSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
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
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sign In',
              style: TextStyle(
                color: AppThemeColor.darkBlueColor,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 28),
            _buildEmailField(),
            const SizedBox(height: 24),
            _buildPasswordField(),
            const SizedBox(height: 36),
            _buildLoginButton(),
            const SizedBox(height: 16),
            if (AppConstants.enableAppleSignIn) _buildAppleSignInButton(),
          ],
        ),
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
        Focus(
          onFocusChange: (hasFocus) {
            setState(() {
              _isEmailFocused = hasFocus;
            });
          },
          child: TextFormField(
            controller: _emailEdtController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            decoration: InputDecoration(
              hintText: 'Enter your email',
              hintStyle: TextStyle(
                color: AppThemeColor.lightGrayColor,
                fontSize: 16,
              ),
              filled: true,
              fillColor: _isEmailFocused
                  ? AppThemeColor.lightBlueColor.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.04),
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
                color: _isEmailFocused
                    ? AppThemeColor.darkBlueColor
                    : AppThemeColor.lightGrayColor,
                size: 22,
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your email';
              }
              if (!RegExp(
                r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
              ).hasMatch(value)) {
                return 'Please enter a valid email address';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Password',
          style: TextStyle(
            color: AppThemeColor.darkBlueColor,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Focus(
          onFocusChange: (hasFocus) {
            setState(() {
              _isPasswordFocused = hasFocus;
            });
          },
          child: TextFormField(
            controller: _passwordEdtController,
            obscureText: _obscurePassword,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            decoration: InputDecoration(
              hintText: 'Enter your password',
              hintStyle: TextStyle(
                color: AppThemeColor.lightGrayColor,
                fontSize: 16,
              ),
              filled: true,
              fillColor: _isPasswordFocused
                  ? AppThemeColor.lightBlueColor.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.04),
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
                Icons.lock_outline,
                color: _isPasswordFocused
                    ? AppThemeColor.darkBlueColor
                    : AppThemeColor.lightGrayColor,
                size: 22,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: AppThemeColor.lightGrayColor,
                  size: 22,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your password';
              }
              if (value.length < 6) {
                return 'Password must be at least 6 characters';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: RoundedLoadingButton(
        animateOnTap: true,
        borderRadius: 16,
        controller: _btnCtlr,
        onPressed: () {
          _btnCtlr.start();
          if (_formKey.currentState!.validate()) {
            _makeLogin();
          } else {
            _btnCtlr.reset();
          }
        },
        color: AppThemeColor.darkBlueColor,
        elevation: 0,
        child: const Text(
          'Sign In',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _forgotPasswordSection() {
    return Center(
      child: TextButton(
        onPressed: () =>
            RouterClass.nextScreenNormal(context, const ForgotPasswordScreen()),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        child: Text(
          'Forgot Password?',
          style: TextStyle(
            color: AppThemeColor.darkBlueColor,
            fontSize: 16,
            fontWeight: FontWeight.w500,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }

  Widget _buildAppleSignInButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: AppThemeColor.darkBlueColor.withValues(alpha: 0.3),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: () async {
          final helper = FirebaseGoogleAuthHelper();
          final user = await helper.loginWithApple();
          if (user != null) {
            try {
              await FirebaseFirestoreHelper().ensureUserProfileCompleteness(
                user.uid,
              );
              if (!mounted) return;
              RouterClass().homeScreenRoute(context: context);
            } catch (_) {}
          } else {
            ShowToast().showNormalToast(msg: 'Apple sign-in failed');
          }
        },
        icon: const Icon(Icons.apple, size: 22, color: Colors.black),
        label: const Text(
          'Continue with Apple',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}
