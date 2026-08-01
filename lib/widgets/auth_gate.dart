import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:attendus/screens/Splash/second_splash_screen.dart';
import 'package:attendus/screens/Home/dashboard_screen.dart'
    deferred as dashboard;
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/Services/auth_service.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/Services/subscription_service.dart';
import 'package:attendus/Services/navigation_state_service.dart';
import 'package:attendus/firebase/firebase_google_auth_helper.dart';
import 'package:attendus/Utils/route_builder.dart' deferred as route_builder;
import 'package:attendus/widgets/deferred_screen_loader.dart';
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

      // Mobile web Google OAuth returns by reloading Attendus. Consume the
      // redirect before checking currentUser so startup cannot incorrectly
      // send the newly signed-in user back to onboarding.
      final redirectProfile = await FirebaseGoogleAuthHelper()
          .completeGoogleRedirectSignIn();
      if (redirectProfile != null) {
        final redirectUser = redirectProfile['user'] as User;
        try {
          await AuthService().handleSocialLoginSuccessWithProfileData(
            redirectProfile,
          );
        } catch (error) {
          // Authentication already succeeded. A temporary profile persistence
          // failure must not send the user back to Welcome.
          Logger.warning(
            'AuthGate: Google profile setup will retry in background: $error',
          );
          await AuthService().ensureInMemoryUserModel();
        }
        _setUserAndNavigate(redirectUser, restoreNavigation: false);
        return;
      }

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

      // Restoring a durable web session from browser storage is asynchronous.
      // Wait for Firebase's authoritative initial event instead of racing it
      // with a short UI timer.
      Logger.debug('🔄 AuthGate: Waiting for initial auth state...');
      User? restoredUser;
      try {
        restoredUser = await FirebaseAuth.instance
            .authStateChanges()
            .first
            .timeout(const Duration(seconds: 10));
      } on TimeoutException {
        // Do not discard a user that became available while waiting for an
        // unusually delayed stream event.
        restoredUser = FirebaseAuth.instance.currentUser;
        Logger.warning('AuthGate: Initial auth-state check timed out');
      }

      if (!mounted || !_isChecking) return;

      Logger.debug(
        '🔍 AuthGate: Initial auth state: ${restoredUser?.uid ?? 'null'}',
      );
      if (restoredUser != null) {
        _setUserAndNavigate(restoredUser);
        return;
      }

      setState(() {
        _isLoggedIn = false;
        _isChecking = false;
      });
    } catch (e) {
      Logger.error('AuthGate: Error checking auth state', e);
      if (!mounted) return;
      setState(() {
        _isLoggedIn = false;
        _isChecking = false;
      });
    }
  }

  void _setUserAndNavigate(User user, {bool restoreNavigation = true}) async {
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
      if (!restoreNavigation) {
        await _navStateService.clearNavigationState();
      }
      final shouldRestore = await _navStateService.shouldRestore();
      if (restoreNavigation && shouldRestore) {
        Logger.info('AuthGate: Attempting to restore navigation state');
        final savedRoute = await _navStateService.restoreNavigationState();

        if (savedRoute != null) {
          await route_builder.loadLibrary();
          restoredScreen =
              await route_builder.RouteBuilder.buildRouteFromConfig(savedRoute);
          Logger.success(
            'AuthGate: Successfully restored route: ${savedRoute.routeName}',
          );
        }
      } else {
        Logger.debug('AuthGate: No valid navigation state to restore');
      }
    } catch (e) {
      Logger.warning('AuthGate: Failed to restore navigation state: $e');
    }

    restoredScreen ??= DeferredScreenLoader(
      loadLibrary: dashboard.loadLibrary,
      loadingLabel: 'Loading dashboard',
      builder: () =>
          dashboard.DashboardScreen(restoreSavedTab: restoreNavigation),
    );

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
      Logger.debug('AuthGate: Returning authenticated destination');
      return _restoredWidget!;
    } else {
      Logger.debug('AuthGate: Navigating directly to onboarding');
      return const SecondSplashScreen();
    }
  }
}
