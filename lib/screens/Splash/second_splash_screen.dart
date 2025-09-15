import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:attendus/screens/Authentication/login_screen.dart';
import 'package:attendus/screens/Authentication/create_account/create_account_screen.dart';

import 'package:attendus/Utils/images.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/screens/QRScanner/qr_scanner_flow_screen.dart';
import 'package:attendus/firebase/firebase_google_auth_helper.dart';

import 'package:attendus/Utils/toast.dart';
import 'package:attendus/Utils/app_constants.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:attendus/services/auth_service.dart';

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

  Future<void> _handleSuccessfulLogin(user) async {
    try {
      await AuthService().handleSocialLoginSuccess(user);
      if (!mounted) return;
      RouterClass().homeScreenRoute(context: context);
    } catch (e) {
      ShowToast().showNormalToast(
        msg: 'Error loading user data: ${e.toString()}',
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
              const Color(0xFFF0F4F8).withValues(alpha: 0.5),
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
                          const Color(0xFF7B61FF).withValues(
                            alpha: _shimmerOpacityAnimation.value * 0.1,
                          ),
                          const Color(0xFF00BCD4).withValues(
                            alpha: _shimmerOpacityAnimation.value * 0.05,
                          ),
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
                          const Color(0xFF00BCD4).withValues(
                            alpha: _shimmerOpacityAnimation.value * 0.08,
                          ),
                          const Color(0xFF7B61FF).withValues(
                            alpha: _shimmerOpacityAnimation.value * 0.04,
                          ),
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Calculate responsive spacing based on screen height
                  final screenHeight = MediaQuery.of(context).size.height;
                  final isSmallScreen = screenHeight < 700;
                  final isMediumScreen =
                      screenHeight >= 700 && screenHeight < 800;

                  // Adaptive spacing values
                  final topSpacing = isSmallScreen
                      ? 20.0
                      : isMediumScreen
                      ? 25.0
                      : 30.0;
                  final sectionSpacing = isSmallScreen
                      ? 20.0
                      : isMediumScreen
                      ? 25.0
                      : 30.0;
                  final welcomeSpacing = isSmallScreen
                      ? 15.0
                      : isMediumScreen
                      ? 20.0
                      : 25.0;
                  final bottomSpacing = isSmallScreen
                      ? 20.0
                      : isMediumScreen
                      ? 25.0
                      : 30.0;

                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            children: [
                              SizedBox(height: topSpacing),
                              _buildLogoSection(),
                              SizedBox(height: sectionSpacing),
                              _buildWelcomeSection(),
                              SizedBox(height: welcomeSpacing),
                              _buildQRCodeSection(),
                              // Flexible spacing that adjusts to available space
                              Flexible(
                                child: SizedBox(
                                  height: isSmallScreen
                                      ? 20
                                      : isMediumScreen
                                      ? 40
                                      : 60,
                                ),
                              ),
                              _buildActionButtons(),
                              SizedBox(height: bottomSpacing),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
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
        final screenHeight = MediaQuery.of(context).size.height;
        final isSmallScreen = screenHeight < 700;
        final logoHeight = isSmallScreen ? 80.0 : 100.0;
        final logoWidth = isSmallScreen ? 150.0 : 180.0;
        final logoPaddingH = isSmallScreen ? 24.0 : 32.0;
        final logoPaddingV = isSmallScreen ? 18.0 : 24.0;

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
                      color: const Color(0xFF7B61FF).withValues(alpha: 0.25),
                      blurRadius: 24,
                      offset: const Offset(-8, 12),
                      spreadRadius: -2,
                    ),
                    BoxShadow(
                      color: const Color(0xFF00BCD4).withValues(alpha: 0.25),
                      blurRadius: 24,
                      offset: const Offset(8, 12),
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: logoPaddingH,
                    vertical: logoPaddingV,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Image.asset(
                    Images.inAppLogo,
                    height: logoHeight,
                    width: logoWidth,
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
      child: Builder(
        builder: (context) {
          final screenHeight = MediaQuery.of(context).size.height;
          final isSmallScreen = screenHeight < 700;
          final titleSize = isSmallScreen ? 24.0 : 28.0;
          final subtitleSize = isSmallScreen ? 14.0 : 16.0;

          return Column(
            children: [
              Text(
                'Welcome to Attendus',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1F36),
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: isSmallScreen ? 8 : 12),
              Text(
                'Your gateway to seamless event experiences',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: subtitleSize,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildQRCodeSection() {
    return SlideTransition(
      position: _slideUpAnimation,
      child: GestureDetector(
        onTap: () =>
            RouterClass.nextScreenNormal(context, const QRScannerFlowScreen()),
        child: Builder(
          builder: (context) {
            final screenHeight = MediaQuery.of(context).size.height;
            final isSmallScreen = screenHeight < 700;
            final padding = isSmallScreen ? 16.0 : 20.0;
            final iconSize = isSmallScreen ? 50.0 : 60.0;
            final iconInnerSize = isSmallScreen ? 28.0 : 32.0;
            final titleSize = isSmallScreen ? 16.0 : 18.0;
            final subtitleSize = isSmallScreen ? 12.0 : 14.0;

            return Container(
              padding: EdgeInsets.all(padding),
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
                    color: Colors.black.withValues(alpha: 0.04),
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
                    width: iconSize,
                    height: iconSize,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF7B61FF), Color(0xFF00BCD4)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7B61FF).withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.qr_code_scanner,
                      color: Colors.white,
                      size: iconInnerSize,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Text content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quick Sign-In',
                          style: TextStyle(
                            fontSize: titleSize,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1A1F36),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Scan QR code for instant event access',
                          style: TextStyle(
                            fontSize: subtitleSize,
                            color: Colors.grey[600],
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Arrow icon
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 18,
                    color: Colors.grey[400],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return ScaleTransition(
      scale: _buttonScaleAnimation,
      child: Builder(
        builder: (context) {
          final screenHeight = MediaQuery.of(context).size.height;
          final isSmallScreen = screenHeight < 700;
          final buttonHeight = isSmallScreen ? 50.0 : 56.0;
          final fontSize = isSmallScreen ? 15.0 : 17.0;
          final socialButtonSize = isSmallScreen ? 50.0 : 60.0;
          final socialIconSize = isSmallScreen ? 18.0 : 22.0;

          return Column(
            children: [
              // Create Account Button
              GestureDetector(
                onTap: () => RouterClass.nextScreenNormal(
                  context,
                  const CreateAccountScreen(),
                ),
                child: Container(
                  width: double.infinity,
                  height: buttonHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF7B61FF), Color(0xFF5B3FDB)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7B61FF).withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      'Create Account',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              // Login Button
              GestureDetector(
                onTap: () =>
                    RouterClass.nextScreenNormal(context, const LoginScreen()),
                child: Container(
                  width: double.infinity,
                  height: buttonHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.white,
                    border: Border.all(color: Colors.grey[300]!, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      'Log In',
                      style: TextStyle(
                        color: const Color(0xFF1A1F36),
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: isSmallScreen ? 16 : 24),
              // Divider with text
              Row(
                children: [
                  Expanded(
                    child: Container(height: 1, color: Colors.grey[300]),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'or continue with',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: isSmallScreen ? 12 : 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(height: 1, color: Colors.grey[300]),
                  ),
                ],
              ),
              SizedBox(height: isSmallScreen ? 12 : 20),
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
                    size: socialButtonSize,
                    iconSize: socialIconSize,
                  ),
                  const SizedBox(width: 12),
                  _buildSocialButton(
                    icon: FontAwesomeIcons.apple,
                    color: Colors.white,
                    backgroundColor: Colors.black,
                    isLoading: _appleLoading,
                    onTap: _signInWithApple,
                    size: socialButtonSize,
                    iconSize: socialIconSize,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSocialButton({
    required IconData icon,
    required Color color,
    required Color backgroundColor,
    required bool isLoading,
    required Future<void> Function() onTap,
    required double size,
    required double iconSize,
  }) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size,
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
                  ? Colors.black.withValues(alpha: isLoading ? 0.02 : 0.08)
                  : backgroundColor.withValues(alpha: isLoading ? 0.3 : 0.4),
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
              : FaIcon(icon, color: color, size: iconSize),
        ),
      ),
    );
  }
}
