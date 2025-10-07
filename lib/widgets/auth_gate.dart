import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:attendus/screens/Splash/splash_screen.dart';
import 'package:attendus/screens/Home/dashboard_screen.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/Services/auth_service.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/Services/firebase_initializer.dart';

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
  StreamSubscription<User?>? _authStateSubscription;

  @override
  void initState() {
    super.initState();
    Logger.debug('🚀 AuthGate: initState called');
    // Delay auth check to ensure Firebase is initialized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthState();
    });
  }

  Future<void> _checkAuthState() async {
    try {
      Logger.debug('🔄 AuthGate: Checking Firebase Auth state...');

      // Ensure Firebase is initialized first (centralized + idempotent)
      try {
        await FirebaseInitializer.initializeOnce();
        Logger.debug('✅ AuthGate: Firebase initialized');
      } catch (e) {
        Logger.debug(
          'ℹ️ AuthGate: Firebase init failed or timed out, continuing: $e',
        );
      }

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

      // If no immediate user, wait for Firebase Auth to initialize and check again
      Logger.debug(
        '🔄 AuthGate: No immediate user, waiting for Firebase Auth initialization...',
      );

      // Listen for the first auth state change (this delivers persisted user on cold start)
      _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen((
        User? user,
      ) {
        Logger.debug('🔍 AuthGate: Auth state changed: ${user?.uid ?? 'null'}');

        if (mounted) {
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
        }
      });

      // Timeout after 3 seconds to prevent hanging
      Timer(const Duration(seconds: 3), () {
        if (mounted && _isChecking) {
          Logger.warning('⏰ AuthGate: Timeout waiting for Firebase Auth state');
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

  void _setUserAndNavigate(User user) {
    if (!mounted || !_isChecking) return;

    // Set minimal customer model for immediate navigation
    CustomerController.logeInCustomer ??= CustomerModel(
      uid: user.uid,
      name: user.displayName ?? '',
      email: user.email ?? '',
      createdAt: DateTime.now(),
      profilePictureUrl: user.photoURL,
    );

    setState(() {
      _isLoggedIn = true;
      _isChecking = false;
    });

    // Initialize AuthService in background for full functionality
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
      Logger.debug('🏠 AuthGate: Navigating to Dashboard');
      return const DashboardScreen();
    } else {
      Logger.debug('🔍 AuthGate: Navigating to Splash');
      return const SplashScreen();
    }
  }
}
