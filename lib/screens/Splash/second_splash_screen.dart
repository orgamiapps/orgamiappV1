import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:attendus/screens/Authentication/login_screen.dart';
import 'package:attendus/screens/Authentication/create_account/create_account_screen.dart';

import 'package:attendus/Utils/images.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/screens/QRScanner/qr_scanner_flow_screen.dart';
import 'package:attendus/firebase/firebase_google_auth_helper.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/Utils/app_constants.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class SecondSplashScreen extends StatefulWidget {
  const SecondSplashScreen({super.key});

  @override
  State<SecondSplashScreen> createState() => _SecondSplashScreenState();
}

class _SecondSplashScreenState extends State<SecondSplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoAnimation;
  late AnimationController _fadeAnimation;
  late AnimationController _slideAnimation;
  late AnimationController _buttonAnimation;
  late AnimationController _floatAnimation;
  late AnimationController _shimmerAnimation;

  late Animation<double> _logoScaleAnimation;
  late Animation<double> _logoRotateAnimation;
  late Animation<double> _fadeInAnimation;
  late Animation<Offset> _slideUpAnimation;
  late Animation<double> _buttonScaleAnimation;
  late Animation<double> _floatUpDownAnimation;
  late Animation<double> _shimmerOpacityAnimation;

  // Social login loading states
  bool _googleLoading = false;
  bool _appleLoading = false;
  bool _facebookLoading = false;
  bool _xLoading = false;

  @override
  void initState() {
    super.initState();
    // Set status bar style for better aesthetics
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    _initializeAnimations();
  }

  void _initializeAnimations() {
    // Logo animation with rotation
    _logoAnimation = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _logoScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoAnimation,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );
    _logoRotateAnimation = Tween<double>(begin: -0.1, end: 0.0).animate(
      CurvedAnimation(
        parent: _logoAnimation,
        curve: const Interval(0.3, 0.8, curve: Curves.easeOutBack),
      ),
    );

    // Floating animation for logo
    _floatAnimation = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);
    _floatUpDownAnimation = Tween<double>(begin: -5.0, end: 5.0).animate(
      CurvedAnimation(parent: _floatAnimation, curve: Curves.easeInOut),
    );

    // Shimmer animation
    _shimmerAnimation = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _shimmerOpacityAnimation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _shimmerAnimation, curve: Curves.easeInOut),
    );

    // Fade animation
    _fadeAnimation = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeInAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeAnimation, curve: Curves.easeIn));

    // Slide animation
    _slideAnimation = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _slideUpAnimation =
        Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideAnimation, curve: Curves.easeOutQuart),
        );

    // Button animation
    _buttonAnimation = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _buttonScaleAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _buttonAnimation, curve: Curves.easeOutBack),
    );

    // Start animations in sequence
    _logoAnimation.forward();
    Future.delayed(const Duration(milliseconds: 400), () {
      _fadeAnimation.forward();
    });
    Future.delayed(const Duration(milliseconds: 700), () {
      _slideAnimation.forward();
    });
    Future.delayed(const Duration(milliseconds: 1000), () {
      _buttonAnimation.forward();
    });
  }

  @override
  void dispose() {
    _logoAnimation.dispose();
    _fadeAnimation.dispose();
    _slideAnimation.dispose();
    _buttonAnimation.dispose();
    _floatAnimation.dispose();
    _shimmerAnimation.dispose();
    super.dispose();
  }

  // Social authentication methods
  Future<void> _signInWithGoogle() async {
    if (_googleLoading) return;

    setState(() {
      _googleLoading = true;
    });

    try {
      final helper = FirebaseGoogleAuthHelper();
      final user = await helper.loginWithGoogle();

      if (user != null) {
        await _handleSuccessfulLogin(user);
      } else {
        ShowToast().showNormalToast(msg: 'Google sign-in failed');
      }
    } catch (e) {
      ShowToast().showNormalToast(msg: 'Google sign-in error: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _googleLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithApple() async {
    if (_appleLoading) return;

    if (!AppConstants.enableAppleSignIn) {
      ShowToast().showNormalToast(msg: 'Apple sign-in is currently disabled');
      return;
    }

    setState(() {
      _appleLoading = true;
    });

    try {
      final helper = FirebaseGoogleAuthHelper();
      final user = await helper.loginWithApple();

      if (user != null) {
        await _handleSuccessfulLogin(user);
      } else {
        ShowToast().showNormalToast(
          msg: 'Apple sign-in is not available on this device',
        );
      }
    } catch (e) {
      String errorMessage = 'Apple sign-in failed';
      if (e.toString().contains('not available')) {
        errorMessage = 'Apple sign-in is only available on iOS devices';
      } else if (e.toString().contains('webAuthenticationOptions')) {
        errorMessage = 'Apple sign-in configuration error';
      }
      ShowToast().showNormalToast(msg: errorMessage);
    } finally {
      if (mounted) {
        setState(() {
          _appleLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithFacebook() async {
    if (_facebookLoading) return;

    setState(() {
      _facebookLoading = true;
    });

    try {
      final helper = FirebaseGoogleAuthHelper();
      final user = await helper.loginWithFacebook();

      if (user != null) {
        await _handleSuccessfulLogin(user);
      } else {
        ShowToast().showNormalToast(msg: 'Facebook sign-in failed');
      }
    } catch (e) {
      ShowToast().showNormalToast(
        msg: 'Facebook sign-in error: ${e.toString()}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _facebookLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithX() async {
    if (_xLoading) return;

    setState(() {
      _xLoading = true;
    });

    try {
      final helper = FirebaseGoogleAuthHelper();
      final user = await helper.loginWithX();

      if (user != null) {
        await _handleSuccessfulLogin(user);
      } else {
        ShowToast().showNormalToast(
          msg: 'X sign-in is only available on web platform',
        );
      }
    } catch (e) {
      String errorMessage = 'X sign-in failed';
      if (e.toString().contains('web-based')) {
        errorMessage = 'X sign-in is only available on web platform';
      }
      ShowToast().showNormalToast(msg: errorMessage);
    } finally {
      if (mounted) {
        setState(() {
          _xLoading = false;
        });
      }
    }
  }

  Future<void> _handleSuccessfulLogin(user) async {
    try {
      // Check if user exists in Firestore
      final userData = await FirebaseFirestoreHelper().getSingleCustomer(
        customerId: user.uid,
      );

      if (userData != null) {
        // Existing user
        setState(() {
          CustomerController.logeInCustomer = userData;
        });
        if (!mounted) return;
        RouterClass().homeScreenRoute(context: context);
      } else {
        // New user - create profile
        final newCustomerModel = CustomerModel(
          uid: user.uid,
          name: user.displayName ?? '',
          email: user.email ?? '',
          createdAt: DateTime.now(),
        );
        await _createNewUser(newCustomerModel);
      }
    } catch (e) {
      ShowToast().showNormalToast(
        msg: 'Error loading user data: ${e.toString()}',
      );
    }
  }

  Future<void> _createNewUser(CustomerModel newCustomerModel) async {
    try {
      await FirebaseFirestore.instance
          .collection(CustomerModel.firebaseKey)
          .doc(newCustomerModel.uid)
          .set(CustomerModel.getMap(newCustomerModel));

      ShowToast().showNormalToast(msg: 'Welcome to ${AppConstants.appName}!');

      setState(() {
        CustomerController.logeInCustomer = newCustomerModel;
      });

      if (!mounted) return;
      RouterClass().homeScreenRoute(context: context);
    } catch (e) {
      ShowToast().showNormalToast(
        msg: 'Error creating account: ${e.toString()}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFF5F7FB),
              const Color(0xFFFFFFFF),
              const Color(0xFFF0F4F8).withOpacity(0.5),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Decorative background elements
            Positioned(
              top: -100,
              right: -100,
              child: AnimatedBuilder(
                animation: _shimmerAnimation,
                builder: (context, child) {
                  return Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(
                            0xFF7B61FF,
                          ).withOpacity(_shimmerOpacityAnimation.value * 0.1),
                          const Color(
                            0xFF00BCD4,
                          ).withOpacity(_shimmerOpacityAnimation.value * 0.05),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              bottom: -150,
              left: -100,
              child: AnimatedBuilder(
                animation: _shimmerAnimation,
                builder: (context, child) {
                  return Container(
                    width: 350,
                    height: 350,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(
                            0xFF00BCD4,
                          ).withOpacity(_shimmerOpacityAnimation.value * 0.08),
                          const Color(
                            0xFF7B61FF,
                          ).withOpacity(_shimmerOpacityAnimation.value * 0.04),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // Main content
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: SizedBox(
                          height: constraints.maxHeight,
                          child: Column(
                            children: [
                              const SizedBox(height: 30),
                              _buildLogoSection(),
                              const SizedBox(height: 30),
                              _buildWelcomeSection(),
                              const SizedBox(height: 25),
                              _buildQRCodeSection(),
                              const Spacer(),
                              _buildActionButtons(),
                              const SizedBox(height: 30),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoSection() {
    return AnimatedBuilder(
      animation: Listenable.merge([_logoAnimation, _floatAnimation]),
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _floatUpDownAnimation.value),
          child: Transform.rotate(
            angle: _logoRotateAnimation.value,
            child: Transform.scale(
              scale: _logoScaleAnimation.value,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF7B61FF), Color(0xFF00BCD4)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7B61FF).withOpacity(0.25),
                      blurRadius: 24,
                      offset: const Offset(-8, 12),
                      spreadRadius: -2,
                    ),
                    BoxShadow(
                      color: const Color(0xFF00BCD4).withOpacity(0.25),
                      blurRadius: 24,
                      offset: const Offset(8, 12),
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 24,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Image.asset(
                    Images.inAppLogo,
                    height: 100,
                    width: 180,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWelcomeSection() {
    return FadeTransition(
      opacity: _fadeInAnimation,
      child: Column(
        children: [
          const Text(
            'Welcome to Attendus',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1F36),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your gateway to seamless event experiences',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQRCodeSection() {
    return SlideTransition(
      position: _slideUpAnimation,
      child: GestureDetector(
        onTap: () =>
            RouterClass.nextScreenNormal(context, const QRScannerFlowScreen()),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Colors.grey[50]!],
            ),
            border: Border.all(color: Colors.grey[200]!, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 20,
                offset: const Offset(0, 10),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Row(
            children: [
              // QR Icon
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF7B61FF), Color(0xFF00BCD4)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7B61FF).withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.qr_code_scanner,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quick Check-In',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1F36),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Scan QR code for instant event access',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              // Arrow icon
              Icon(Icons.arrow_forward_ios, size: 18, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return ScaleTransition(
      scale: _buttonScaleAnimation,
      child: Column(
        children: [
          // Create Account Button
          GestureDetector(
            onTap: () => RouterClass.nextScreenNormal(
              context,
              const CreateAccountScreen(),
            ),
            child: Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF7B61FF), Color(0xFF5B3FDB)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7B61FF).withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'Create Account',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Login Button
          GestureDetector(
            onTap: () =>
                RouterClass.nextScreenNormal(context, const LoginScreen()),
            child: Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.white,
                border: Border.all(color: Colors.grey[300]!, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'Sign In',
                  style: TextStyle(
                    color: Color(0xFF1A1F36),
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Divider with text
          Row(
            children: [
              Expanded(child: Container(height: 1, color: Colors.grey[300])),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'or continue with',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(child: Container(height: 1, color: Colors.grey[300])),
            ],
          ),
          const SizedBox(height: 20),
          // Social login buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSocialButton(
                icon: FontAwesomeIcons.google,
                color: const Color(0xFF4285F4),
                backgroundColor: Colors.white,
                isLoading: _googleLoading,
                onTap: _signInWithGoogle,
              ),
              const SizedBox(width: 12),
              _buildSocialButton(
                icon: FontAwesomeIcons.apple,
                color: Colors.white,
                backgroundColor: Colors.black,
                isLoading: _appleLoading,
                onTap: _signInWithApple,
              ),
              const SizedBox(width: 12),
              _buildSocialButton(
                icon: FontAwesomeIcons.facebookF,
                color: Colors.white,
                backgroundColor: const Color(0xFF1877F2),
                isLoading: _facebookLoading,
                onTap: _signInWithFacebook,
              ),
              const SizedBox(width: 12),
              _buildSocialButton(
                icon: FontAwesomeIcons.xTwitter,
                color: Colors.white,
                backgroundColor: Colors.black,
                isLoading: _xLoading,
                onTap: _signInWithX,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSocialButton({
    required IconData icon,
    required Color color,
    required Color backgroundColor,
    required bool isLoading,
    required Future<void> Function() onTap,
  }) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: backgroundColor == Colors.white
              ? Border.all(
                  color: isLoading ? Colors.grey[400]! : Colors.grey[300]!,
                  width: 1,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: backgroundColor == Colors.white
                  ? Colors.black.withOpacity(isLoading ? 0.02 : 0.08)
                  : backgroundColor.withOpacity(isLoading ? 0.3 : 0.4),
              blurRadius: 12,
              offset: const Offset(0, 6),
              spreadRadius: 0,
            ),
          ],
        ),
        child: Center(
          child: isLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      backgroundColor == Colors.white
                          ? Colors.grey[600]!
                          : Colors.white,
                    ),
                  ),
                )
              : FaIcon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}
