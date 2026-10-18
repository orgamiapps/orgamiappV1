import 'package:attendus/widgets/deferred_shared_community_screen.dart';
import 'package:attendus/widgets/deferred_conversation_screen.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:attendus/Services/web_auth_session.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
import 'package:attendus/Services/guest_mode_service.dart';
import 'package:attendus/Services/pending_auth_intent_service.dart';
import 'package:attendus/widgets/deferred_premium_event_creation.dart';
import 'package:attendus/widgets/deferred_shared_event_screen.dart';

/// Resolves the persistent entry state before the gate selects a destination.
/// Explicit Discover applies before both guest and signed-in navigation.
class AuthGateNavigation {
  const AuthGateNavigation({
    required this.restoreNavigation,
    this.pendingIntent,
  });

  final bool restoreNavigation;
  final PendingAuthIntent? pendingIntent;
  int get initialTab => pendingIntent?.dashboardTab ?? 0;

  static Future<AuthGateNavigation> resolve({
    bool forceDiscover = false,
    bool restoreNavigation = true,
  }) async {
    try {
      if (forceDiscover) {
        await PendingAuthIntentService.clear();
        await NavigationStateService().clearNavigationState();
        return const AuthGateNavigation(restoreNavigation: false);
      }
      final pending = await PendingAuthIntentService.consume();
      final restore = restoreNavigation && pending == null;
      if (!restore) await NavigationStateService().clearNavigationState();
      return AuthGateNavigation(
        restoreNavigation: restore,
        pendingIntent: pending,
      );
    } catch (error) {
      // Saved navigation is optional. A blocked browser preference store must
      // not prevent entry or discard the authoritative Firebase identity.
      Logger.warning('AuthGate: Saved navigation unavailable: $error');
      return const AuthGateNavigation(restoreNavigation: false);
    }
  }
}

/// AuthGate determines the initial screen based on Firebase Auth state
/// This ensures persistent login works immediately after force-close
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.forceDiscover = false});

  /// Explicit Discover navigation takes precedence over an older restored tab
  /// or pending login destination, while keeping guest access contextual.
  final bool forceDiscover;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isChecking = true;
  bool _restorationDelayed = false;
  bool _restorationFailed = false;
  bool _checkInFlight = false;
  Timer? _restorationTimer;
  StreamSubscription<User?>? _webAuthChanges;
  String? _visibleUid;
  bool _showingAccount = false;

  void _watchWebAccount() {
    if (!kIsWeb) return;
    _webAuthChanges ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted ||
          _isChecking ||
          !_showingAccount ||
          user?.uid == _visibleUid) {
        return;
      }
      // Another tab can sign out or switch accounts while private routes are open.
      Navigator.of(
        context,
        rootNavigator: true,
      ).popUntil((route) => route.isFirst);
      CustomerController.logeInCustomer = null;
      setState(() {
        _isChecking = true;
        _restoredWidget = null;
        _restorationDelayed = false;
      });
      _checkAuthState();
    });
  }

  @override
  void dispose() {
    _restorationTimer?.cancel();
    _webAuthChanges?.cancel();
    super.dispose();
  }

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
    if (_checkInFlight) return;
    _checkInFlight = true;
    if (mounted) {
      setState(() {
        _restorationFailed = false;
      });
    }
    _restorationTimer?.cancel();
    _restorationTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _isChecking) {
        setState(() {
          _restorationDelayed = true;
        });
      }
    });
    try {
      if (kIsWeb) await WebAuthSession.instance.ready();
      if (widget.forceDiscover) {
        await AuthGateNavigation.resolve(forceDiscover: true);
        if (!mounted) return;
      }
      await GuestModeService().initialize();
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
        await _setUserAndNavigate(redirectUser, restoreNavigation: false);
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
        if (firebaseUser.isAnonymous) {
          _setGuestAndNavigate();
        } else {
          await _setUserAndNavigate(firebaseUser);
        }
        return;
      }

      // Restoring a durable web session from browser storage is asynchronous.
      // Wait for Firebase's authoritative initial event instead of racing it
      // with a short UI timer.
      Logger.debug('🔄 AuthGate: Waiting for initial auth state...');
      final restoredUser = kIsWeb
          ? FirebaseAuth.instance.currentUser
          : await FirebaseAuth.instance.authStateChanges().first.timeout(
              const Duration(seconds: 10),
              onTimeout: () => FirebaseAuth.instance.currentUser,
            );

      if (!mounted || !_isChecking) return;

      Logger.debug(
        '🔍 AuthGate: Initial auth state: ${restoredUser?.uid ?? 'null'}',
      );
      if (restoredUser != null) {
        if (restoredUser.isAnonymous) {
          _setGuestAndNavigate();
        } else {
          await _setUserAndNavigate(restoredUser);
        }
        return;
      }

      try {
        await GuestModeService().ensureGuestSession();
      } catch (error) {
        Logger.warning(
          'AuthGate: Guest session will retry from Discover: $error',
        );
      }
      _setGuestAndNavigate();
    } catch (e) {
      Logger.error('AuthGate: Error checking auth state', e);
      if (!mounted) return;
      setState(() {
        _restorationFailed = true;
      });
    } finally {
      _checkInFlight = false;
      _restorationTimer?.cancel();
    }
  }

  void _setGuestAndNavigate() {
    if (!mounted || !_isChecking) return;
    CustomerController.logeInCustomer = null;
    _showingAccount = false;
    _visibleUid = FirebaseAuth.instance.currentUser?.uid;
    _watchWebAccount();
    setState(() {
      _isChecking = false;
      _restoredWidget = DeferredScreenLoader(
        loadLibrary: dashboard.loadLibrary,
        recoveryKey: 'dashboard',
        loadingLabel: 'Loading Discover',
        builder: () => dashboard.DashboardScreen(restoreSavedTab: false),
      );
    });
  }

  Future<void> _setUserAndNavigate(
    User user, {
    bool restoreNavigation = true,
  }) async {
    if (!mounted || !_isChecking) return;

    // Set minimal customer model for immediate navigation
    if (CustomerController.logeInCustomer?.uid != user.uid) {
      CustomerController.logeInCustomer = CustomerModel(
        uid: user.uid,
        name: user.displayName ?? '',
        email: user.email ?? '',
        createdAt: DateTime.now(),
        profilePictureUrl: user.photoURL,
      );
    }

    final entry = widget.forceDiscover
        ? const AuthGateNavigation(restoreNavigation: false)
        : await AuthGateNavigation.resolve(
            restoreNavigation: restoreNavigation,
          );
    final pendingIntent = entry.pendingIntent;
    restoreNavigation = entry.restoreNavigation;

    // Try to restore navigation state
    Widget? restoredScreen;
    try {
      final shouldRestore =
          restoreNavigation && await _navStateService.shouldRestore();
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
      recoveryKey: 'dashboard',
      loadingLabel: 'Loading dashboard',
      builder: () => dashboard.DashboardScreen(
        initialIndex: entry.initialTab,
        restoreSavedTab: restoreNavigation,
      ),
    );

    if (!mounted) return;
    if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
      Future<void>.delayed(Duration.zero, () {
        if (mounted) _checkAuthState();
      });
      return;
    }
    _showingAccount = true;
    _visibleUid = user.uid;
    _watchWebAccount();
    setState(() {
      _isChecking = false;
      _restoredWidget = restoredScreen;
    });

    if (pendingIntent?.action == PendingAuthAction.createEvent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(milliseconds: 250), () {
          if (!mounted) return;
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              builder: (_) => const DeferredPremiumEventCreation(),
            ),
          );
        });
      });
    } else if (pendingIntent?.action == PendingAuthAction.sharedCommunity &&
        pendingIntent?.communityId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => DeferredSharedCommunityScreen(
              organizationId: pendingIntent!.communityId!,
            ),
          ),
        );
      });
    } else if (pendingIntent?.action == PendingAuthAction.sharedConversation &&
        pendingIntent?.conversationId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => DeferredConversationScreen(
              conversationId: pendingIntent!.conversationId!,
            ),
          ),
        );
      });
    } else if (pendingIntent?.action == PendingAuthAction.sharedEvent &&
        pendingIntent?.eventId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(milliseconds: 250), () {
          if (!mounted) return;
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              builder: (_) => DeferredSharedEventScreen(
                eventId: pendingIntent!.eventId!,
                initialAction: pendingIntent.eventAction,
              ),
            ),
          );
        });
      });
    }

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
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_restorationFailed) const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                _restorationFailed
                    ? 'Unable to restore your session. Check your connection.'
                    : _restorationDelayed
                    ? 'Restoring your session is taking longer than usual.'
                    : 'Checking your session...',
              ),
              if (_restorationDelayed || _restorationFailed)
                TextButton(
                  onPressed: _checkAuthState,
                  child: const Text('Retry'),
                ),
            ],
          ),
        ),
      );
    }

    Logger.debug('AuthGate: Returning resolved destination');
    if (!kIsWeb) return _restoredWidget!;
    return ValueListenableBuilder<bool>(
      valueListenable: WebAuthSession.instance.temporaryStorage,
      child: _restoredWidget!,
      builder: (context, temporary, child) => Column(
        children: [
          if (temporary)
            const Material(
              color: Color(0xFFFFF3CD),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Your browser cannot save this sign-in. You may need to sign in again after closing it.',
                  ),
                ),
              ),
            ),
          Expanded(child: child!),
        ],
      ),
    );
  }
}
