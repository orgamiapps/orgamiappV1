import 'package:flutter/material.dart';
import 'package:attendus/screens/Authentication/login_screen.dart';
import 'package:attendus/screens/Authentication/create_account/create_account_screen.dart';
import 'package:attendus/screens/Splash/Widgets/social_icons_view.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/images.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/screens/QRScanner/qr_scanner_flow_screen.dart';

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

  late Animation<double> _logoScaleAnimation;
  late Animation<double> _fadeInAnimation;
  late Animation<Offset> _slideUpAnimation;
  late Animation<double> _buttonScaleAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    // Logo animation
    _logoAnimation = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _logoScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoAnimation, curve: Curves.elasticOut),
    );

    // Fade animation
    _fadeAnimation = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeInAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeAnimation, curve: Curves.easeInOut));

    // Slide animation
    _slideAnimation = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _slideUpAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideAnimation, curve: Curves.easeOutCubic),
        );

    // Button animation
    _buttonAnimation = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _buttonScaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _buttonAnimation, curve: Curves.elasticOut),
    );

    // Start animations in sequence
    _logoAnimation.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      _fadeAnimation.forward();
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      _slideAnimation.forward();
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      _buttonAnimation.forward();
    });
  }

  @override
  void dispose() {
    _logoAnimation.dispose();
    _fadeAnimation.dispose();
    _slideAnimation.dispose();
    _buttonAnimation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8FAFF), Color(0xFFFFFFFF)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
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
                          const SizedBox(height: 25),
                          _buildWelcomeSection(),
                          const SizedBox(height: 12),
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
      ),
    );
  }

  Widget _buildLogoSection() {
    return ScaleTransition(
      scale: _logoScaleAnimation,
      child: RepaintBoundary(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppThemeColor.darkBlueColor.withAlpha(18),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(
              color: AppThemeColor.borderColor.withAlpha(180),
              width: 0.8,
            ),
          ),
          child: Image.asset(
            Images.inAppLogo,
            height: 50,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeSection() {
    return FadeTransition(
      opacity: _fadeInAnimation,
      child: Column(
        children: [
          Text(
            'Create account or login to discover events and sign-in when you arrive at a location.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppThemeColor.dullFontColor,
              fontSize: 20,
              fontWeight: FontWeight.w400,
              height: 1.4,
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
        child: RepaintBoundary(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppThemeColor.lightBlueColor, Colors.white],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppThemeColor.darkBlueColor.withAlpha(20),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppThemeColor.darkBlueColor.withAlpha(25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: 0.75,
                      child: Image.asset(
                        Images.qrCode,
                        height: 220,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'Or, ',
                        style: TextStyle(
                          color: AppThemeColor.dullFontColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      TextSpan(
                        text: 'tap here',
                        style: TextStyle(
                          color: AppThemeColor.deepGreenColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text:
                            ' to scan a QR code or enter an event code for quick-sign in without an account.',
                        style: TextStyle(
                          color: AppThemeColor.dullFontColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
          _buildPrimaryButton(
            label: 'Create Account',
            onTap: () => RouterClass.nextScreenNormal(
              context,
              const CreateAccountScreen(),
            ),
            isPrimary: true,
          ),
          const SizedBox(height: 12),
          _buildPrimaryButton(
            label: 'Login',
            onTap: () =>
                RouterClass.nextScreenNormal(context, const LoginScreen()),
            isPrimary: false,
          ),
          const SizedBox(height: 18),
          _buildSocialLoginSection(),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required VoidCallback onTap,
    required bool isPrimary,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          gradient: isPrimary
              ? const LinearGradient(
                  colors: [AppThemeColor.darkBlueColor, Color(0xFF1E4A8C)],
                )
              : null,
          color: isPrimary ? null : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: isPrimary
              ? null
              : Border.all(
                  color: AppThemeColor.darkBlueColor.withAlpha(51),
                  width: 1.5,
                ),
          boxShadow: [
            BoxShadow(
              color: isPrimary
                  ? AppThemeColor.darkBlueColor.withAlpha(63)
                  : Colors.transparent,
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isPrimary
                  ? AppThemeColor.pureWhiteColor
                  : AppThemeColor.darkBlueColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSocialLoginSection() {
    return Column(
      children: [
        Text(
          'Continue With',
          style: TextStyle(
            color: AppThemeColor.dullFontColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        const SocialLoginView(),
      ],
    );
  }
}
