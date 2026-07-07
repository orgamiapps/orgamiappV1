import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:attendus/screens/Splash/splash_screen.dart';
import 'package:attendus/screens/Home/dashboard_screen.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/Services/auth_service.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/Services/subscription_service.dart';
import 'package:attendus/Services/navigation_state_service.dart';
import 'package:attendus/Utils/route_builder.dart';
import 'package:provider/provider.dart';

/// AuthGate determines the initial screen based on Firebase Auth state
/// This ensures persistent login works immediately after force-close
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isChecking = true;
  bool _isLoggedIn = false;
  Widget? _restoredWidget;
  StreamSubscription<User?>? _authStateSubscription;
  final NavigationStateService _navStateService = NavigationStateService();

  @override
  void initState() {
    super.initState();
    Logger.debug('🚀 AuthGate: initState called');
    // Initialize navigation state service
    _navStateService.initialize();
    // Delay auth check to ensure Firebase is initialized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthState();
    });
  }

  Future<void> _checkAuthState() async {
    try {
      Logger.debug('🔄 AuthGate: Checking Firebase Auth state...');

      // Firebase should already be initialized in main.dart
      // Skip redundant initialization to speed up startup
      
      // First, check if Firebase Auth is immediately available
      final firebaseUser = FirebaseAuth.instance.currentUser;
      Logger.debug(
        '🔍 AuthGate: Initial Firebase user check: ${firebaseUser?.uid ?? 'null'}',
      );

      if (firebaseUser != null) {
        Logger.debug(
          '✅ AuthGate: Firebase user found immediately: ${firebaseUser.uid}',
        );
        _setUserAndNavigate(firebaseUser);
        return;
      }

      // If no immediate user, we need to wait briefly for auth state
      // But immediately show not logged in if still no user after short wait
      Logger.debug('🔄 AuthGate: No immediate user, checking auth state...');

      bool authChecked = false;

      // Listen for the first auth state change
      _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen((
        User? user,
      ) {
        if (!mounted || authChecked) return;
        authChecked = true;
        
        Logger.debug('🔍 AuthGate: Auth state changed: ${user?.uid ?? 'null'}');

        if (user != null) {
          Logger.debug(
            '✅ AuthGate: Firebase user found via state change: ${user.uid}',
          );
          _setUserAndNavigate(user);
        } else {
          Logger.debug('❌ AuthGate: No user found via state change');
          setState(() {
            _isLoggedIn = false;
            _isChecking = false;
          });
        }
        
        _authStateSubscription?.cancel();
      });

      // Much shorter timeout - if no user after 300ms, show login screen
      // OPTIMIZATION: Reduced from 500ms to 300ms for faster initial screen display
      Timer(const Duration(milliseconds: 300), () {
        if (mounted && _isChecking && !authChecked) {
          Logger.debug('⏰ AuthGate: Quick timeout - showing login screen');
          _authStateSubscription?.cancel();
          setState(() {
            _isLoggedIn = false;
            _isChecking = false;
          });
        }
      });
    } catch (e) {
      Logger.error('AuthGate: Error checking auth state', e);
      setState(() {
        _isLoggedIn = false;
        _isChecking = false;
      });
    }
  }

  void _setUserAndNavigate(User user) async {
    if (!mounted || !_isChecking) return;

    // Set minimal customer model for immediate navigation
    CustomerController.logeInCustomer ??= CustomerModel(
      uid: user.uid,
      name: user.displayName ?? '',
      email: user.email ?? '',
      createdAt: DateTime.now(),
      profilePictureUrl: user.photoURL,
    );

    // Try to restore navigation state
    Widget? restoredScreen;
    try {
      final shouldRestore = await _navStateService.shouldRestore();
      if (shouldRestore) {
        Logger.info('AuthGate: Attempting to restore navigation state');
        final savedRoute = await _navStateService.restoreNavigationState();
        
        if (savedRoute != null) {
          restoredScreen = await RouteBuilder.buildRouteFromConfig(savedRoute);
          Logger.success('AuthGate: Successfully restored route: ${savedRoute.routeName}');
        }
      } else {
        Logger.debug('AuthGate: No valid navigation state to restore');
      }
    } catch (e) {
      Logger.warning('AuthGate: Failed to restore navigation state: $e');
    }

    if (!mounted) return;

    setState(() {
      _isLoggedIn = true;
      _isChecking = false;
      _restoredWidget = restoredScreen;
    });

    // Initialize AuthService and SubscriptionService in background for full functionality
    Future.microtask(() async {
      try {
        Logger.info('AuthGate: Initializing AuthService in background');
        await AuthService().initialize();

        // After initialization, try to refresh user data
        Logger.info('AuthGate: Refreshing user data');
        final authService = AuthService();
        await authService.refreshUserData();

        // If data is still incomplete, try aggressive update
        final currentUser = CustomerController.logeInCustomer;
        if (currentUser != null &&
            (currentUser.name.isEmpty ||
                currentUser.name == currentUser.email.split('@')[0])) {
          Logger.info('AuthGate: Running aggressive profile update');
          await authService.aggressiveProfileUpdate();
        }

        // Initialize SubscriptionService to load subscription data early
        if (mounted) {
          try {
            Logger.info('AuthGate: Initializing SubscriptionService');
            final subscriptionService = Provider.of<SubscriptionService>(
              context,
              listen: false,
            );
            await subscriptionService.initialize();
            Logger.info(
              'AuthGate: SubscriptionService initialized - hasPremium: ${subscriptionService.hasPremium}',
            );
          } catch (e) {
            Logger.warning(
              'AuthGate: Failed to initialize SubscriptionService: $e',
            );
          }
        }

        Logger.info('AuthGate: Background initialization complete');
      } catch (e) {
        Logger.warning('Background AuthService init failed: $e');
      }
    });
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      // Show minimal loading while checking auth state
      return const Scaffold(
        backgroundColor: Color(0xFF667EEA),
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );
    }

    if (_isLoggedIn) {
      // Return restored widget if available, otherwise default to dashboard
      if (_restoredWidget != null) {
        Logger.debug('🔄 AuthGate: Returning restored screen');
        return _restoredWidget!;
      } else {
        Logger.debug('🏠 AuthGate: Navigating to Dashboard (no restored state)');
        return const DashboardScreen();
      }
    } else {
      Logger.debug('🔍 AuthGate: Navigating to Splash');
      return const SplashScreen();
    }
  }
}
