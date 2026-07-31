import 'dart:async';

import 'package:attendus/Services/auth_service.dart';
import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/Utils/images.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoAnimationController;
  late final AnimationController _fadeAnimationController;
  late final Animation<double> _logoScaleAnimation;
  late final Animation<double> _logoOpacityAnimation;
  late final Animation<double> _fadeAnimation;

  bool _isLoading = false;
  bool _hasNavigated = false;
  String _loadingText = 'Preparing Attendus...';
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startLoadingSequence();
    });

    _timeoutTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_hasNavigated) _navigateToSecondSplash();
    });
  }

  void _initializeAnimations() {
    _logoAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _logoScaleAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _logoAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );
    _logoOpacityAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _logoAnimationController,
        curve: const Interval(0, 0.6, curve: Curves.easeIn),
      ),
    );

    _fadeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fadeAnimationController, curve: Curves.easeIn),
    );
  }

  void _startLoadingSequence() {
    _logoAnimationController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _fadeAnimationController.forward();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _hasNavigated) return;
      await _getUser();
    });
  }

  Future<void> _getUser() async {
    if (!mounted || _hasNavigated) return;

    setState(() {
      _isLoading = true;
      _loadingText = 'Checking your session...';
    });

    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        CustomerController.logeInCustomer ??= CustomerModel(
          uid: firebaseUser.uid,
          name: firebaseUser.displayName ?? '',
          email: firebaseUser.email ?? '',
          createdAt: DateTime.now(),
        );
        await _welcomeAndNavigateHome();

        Future.microtask(() async {
          try {
            await AuthService().initialize();
            await AuthService().updateCurrentUserProfileFromAuth();
          } catch (e) {
            debugPrint('Background AuthService init failed: $e');
          }
        });
        return;
      }

      await AuthService().initialize().timeout(
        const Duration(milliseconds: 800),
        onTimeout: () => debugPrint('AuthService initialization timed out'),
      );

      if (!mounted || _hasNavigated) return;
      if (AuthService().isLoggedIn) {
        await _welcomeAndNavigateHome();
        Future.microtask(() async {
          try {
            final success = await AuthService().aggressiveProfileUpdate();
            if (!success) {
              await AuthService().updateCurrentUserProfileFromAuth();
            }
          } catch (e) {
            debugPrint('Background profile update failed: $e');
          }
        });
      } else {
        setState(() => _loadingText = 'Welcome to Attendus');
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted && !_hasNavigated) _navigateToSecondSplash();
      }
    } catch (e) {
      debugPrint('Error checking auth state: $e');
      if (mounted && !_hasNavigated) _navigateToSecondSplash();
    }
  }

  Future<void> _welcomeAndNavigateHome() async {
    if (!mounted || _hasNavigated) return;
    setState(() => _loadingText = 'Welcome back');
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted && !_hasNavigated) _navigateToHome();
  }

  void _navigateToHome() {
    if (_hasNavigated) return;
    _hasNavigated = true;
    _timeoutTimer?.cancel();
    RouterClass().homeScreenRoute(context: context);
  }

  void _navigateToSecondSplash() {
    if (_hasNavigated) return;
    _hasNavigated = true;
    _timeoutTimer?.cancel();
    RouterClass().secondSplashScreenRoute(context: context);
  }

  @override
  void dispose() {
    _hasNavigated = true;
    _timeoutTimer?.cancel();
    _logoAnimationController.dispose();
    _fadeAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _logoAnimationController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _logoScaleAnimation.value,
                        child: Opacity(
                          opacity: _logoOpacityAnimation.value,
                          child: Container(
                            width: 116,
                            height: 116,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(
                                AttendUsTokens.radiusLg,
                              ),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                              boxShadow: AttendUsTokens.softShadow(
                                dark: theme.brightness == Brightness.dark,
                              ),
                            ),
                            child: Image.asset(
                              Images.inAppLogo,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  Icons.event_available,
                                  size: 52,
                                  color: theme.colorScheme.primary,
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  AnimatedBuilder(
                    animation: _fadeAnimationController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _fadeAnimation.value,
                        child: Column(
                          children: [
                            Text(
                              'Attendus',
                              style: theme.textTheme.headlineMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Discover events, manage attendance, and check in securely.',
                              style: theme.textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 40),
                  Text(
                    _loadingText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  if (_isLoading)
                    const SizedBox.square(
                      dimension: 34,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
