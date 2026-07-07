import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:attendus/Services/auth_service.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/models/customer_model.dart';

import 'package:attendus/Utils/images.dart';
import 'package:attendus/Utils/router.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoAnimationController;
  late AnimationController _fadeAnimationController;
  late AnimationController _loadingAnimationController;

  late Animation<double> _logoScaleAnimation;
  late Animation<double> _logoOpacityAnimation;
  late Animation<double> _fadeAnimation;
  // Removed unused `_loadingAnimation` to satisfy analyzer warnings

  bool _isLoading = false;
  bool _hasNavigated = false;
  String _loadingText = "Initializing...";
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    // Delay the loading sequence to ensure Firebase is initialized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startLoadingSequence();
    });

    // Fail-safe: navigate if we haven't moved within 5 seconds (reduced from 8s)
    _timeoutTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_hasNavigated) {
        debugPrint('⏰ Global timeout - forcing navigation to prevent hanging');
        _navigateToSecondSplash();
      }
    });
  }

  void _initializeAnimations() {
    // Logo scale and opacity animation - simplified for better performance
    _logoAnimationController = AnimationController(
      duration: const Duration(
        milliseconds: 400,
      ), // Further reduced for faster startup
      vsync: this,
    );

    _logoScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoAnimationController,
        curve: Curves.easeOutCubic, // Simpler curve than elasticOut
      ),
    );

    _logoOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoAnimationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
      ),
    );

    // Fade animation for text
    _fadeAnimationController = AnimationController(
      duration: const Duration(
        milliseconds: 300,
      ), // Further reduced for faster startup
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeAnimationController, curve: Curves.easeIn),
    );

    // Loading animation
    _loadingAnimationController = AnimationController(
      duration: const Duration(
        milliseconds: 600,
      ), // Further reduced for faster startup
      vsync: this,
    );

    // Using controller directly for the loading indicator; no separate animation needed
  }

  void _startLoadingSequence() async {
    try {
      // Start all animations in parallel for faster startup
      _logoAnimationController.forward();

      // Start fade animation with minimal delay
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _fadeAnimationController.forward();
      });

      // Start loading animation
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _loadingAnimationController.repeat();
      });

      // Firebase is already initialized in main.dart
      // Start auth check immediately without redundant initialization
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _hasNavigated) return;
        // Start auth check immediately
        await _getUser();
      });
    } catch (e) {
      debugPrint('❌ Error in loading sequence: $e');
      if (mounted && !_hasNavigated) {
        _navigateToSecondSplash();
      }
    }
  }

  Future<void> _getUser() async {
    if (!mounted || _hasNavigated) return;

    setState(() {
      _isLoading = true;
      _loadingText = "Checking authentication...";
    });

    try {
      debugPrint('🔄 Checking Firebase Auth state directly...');

      // Firebase is already initialized in main.dart - skip redundant check
      // Direct Firebase Auth check - this is immediately available
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        debugPrint('🔍 Firebase user found directly: ${firebaseUser.uid}');

        // Set minimal customer model immediately for fast navigation
        CustomerController.logeInCustomer ??= CustomerModel(
          uid: firebaseUser.uid,
          name: firebaseUser.displayName ?? '',
          email: firebaseUser.email ?? '',
          createdAt: DateTime.now(),
        );

        setState(() {
          _loadingText = "Welcome back!";
        });

        // Very brief pause to show welcome message
        await Future.delayed(const Duration(milliseconds: 100));

        if (!mounted || _hasNavigated) return;
        _navigateToHome();

        // Initialize AuthService in background for full functionality
        Future.microtask(() async {
          try {
            await AuthService().initialize();
            // Try to update current user profile from Firebase Auth if incomplete
            await AuthService().updateCurrentUserProfileFromAuth();
          } catch (e) {
            debugPrint('Background AuthService init failed: $e');
          }
        });

        return;
      }

      debugPrint('🔄 No direct Firebase user, initializing AuthService...');

      // Initialize AuthService with shorter timeout for faster startup
      await AuthService().initialize().timeout(
        const Duration(milliseconds: 800),
        onTimeout: () {
          debugPrint('⚠️ AuthService initialization timed out');
          // Continue without auth service if it times out
        },
      );

      debugPrint('✅ AuthService initialized');

      if (!mounted || _hasNavigated) return;

      // Check if user is logged in through AuthService
      if (AuthService().isLoggedIn) {
        debugPrint('🔍 User found via AuthService');

        if (!mounted || _hasNavigated) return;
        setState(() {
          _loadingText = "Welcome back!";
        });

        debugPrint('✅ User session restored successfully');

        // Very brief pause to show welcome message
        await Future.delayed(const Duration(milliseconds: 100));

        if (!mounted || _hasNavigated) return;
        _navigateToHome();

        // Try to update user profile from Firebase Auth in background
        Future.microtask(() async {
          try {
            // Run aggressive profile update on app startup
            bool success = await AuthService().aggressiveProfileUpdate();
            if (!success) {
              // Fallback to regular update
              await AuthService().updateCurrentUserProfileFromAuth();
            }
            debugPrint('Background profile update completed');
          } catch (e) {
            debugPrint('Background profile update failed: $e');
          }
        });
      } else {
        debugPrint('🔍 No user session found, navigating to second splash');
        if (!mounted || _hasNavigated) return;

        setState(() {
          _loadingText = "Welcome to Attendus";
        });

        await Future.delayed(const Duration(milliseconds: 100));
        if (!mounted || _hasNavigated) return;
        _navigateToSecondSplash();
      }
    } catch (e) {
      debugPrint('❌ Error in _getUser: $e');
      if (mounted && !_hasNavigated) {
        // On any error, just navigate to second splash
        _navigateToSecondSplash();
      }
    }
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
    _loadingAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF667EEA),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top section with logo and app name
              Expanded(
                flex: 3,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo with animation
                      AnimatedBuilder(
                        animation: _logoAnimationController,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _logoScaleAnimation.value,
                            child: Opacity(
                              opacity: _logoOpacityAnimation.value,
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.1,
                                      ),
                                      blurRadius: 20,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(20),
                                child: Image.asset(
                                  Images.inAppLogo,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    debugPrint('❌ Error loading logo: $error');
                                    return const Icon(
                                      Icons.event,
                                      size: 60,
                                      color: Color(0xFF667EEA),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 32),

                      // App name with fade animation
                      AnimatedBuilder(
                        animation: _fadeAnimationController,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _fadeAnimation.value,
                            child: const Column(
                              children: [
                                Text(
                                  'ATTENDUS',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 2.0,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Discover Amazing Events',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom section with loading indicator
              Expanded(
                flex: 1,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Loading text
                    AnimatedBuilder(
                      animation: _fadeAnimationController,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _fadeAnimation.value,
                          child: Text(
                            _loadingText,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white70,
                              fontWeight: FontWeight.w400,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    // Loading indicator
                    if (_isLoading)
                      AnimatedBuilder(
                        animation: _loadingAnimationController,
                        builder: (context, child) {
                          return SizedBox(
                            width: 40,
                            height: 40,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white.withValues(alpha: 0.8),
                              ),
                              strokeWidth: 3,
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),

              // Bottom padding
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
