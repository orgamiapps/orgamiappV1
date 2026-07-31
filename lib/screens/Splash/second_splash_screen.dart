import 'package:attendus/Services/auth_service.dart';
import 'package:attendus/Services/guest_mode_service.dart';
import 'package:attendus/Utils/app_constants.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/firebase/firebase_google_auth_helper.dart';
import 'package:attendus/screens/Authentication/create_account/create_account_screen.dart';
import 'package:attendus/screens/Authentication/login_screen.dart';
import 'package:attendus/widgets/attendus_auth_layout.dart';
import 'package:attendus/widgets/attendus_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class SecondSplashScreen extends StatefulWidget {
  const SecondSplashScreen({super.key});

  @override
  State<SecondSplashScreen> createState() => _SecondSplashScreenState();
}

class _SecondSplashScreenState extends State<SecondSplashScreen> {
  bool _googleLoading = false;
  bool _appleLoading = false;
  bool _guestLoading = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    if (_googleLoading) return;
    setState(() => _googleLoading = true);

    try {
      final helper = FirebaseGoogleAuthHelper();
      final profileData = await helper.loginWithGoogle();
      if (profileData != null) {
        await AuthService().handleSocialLoginSuccessWithProfileData(
          profileData,
        );
        if (!mounted) return;
        await AuthService().ensureInMemoryUserModel();
        await Future.delayed(const Duration(milliseconds: 120));
        if (mounted) RouterClass().homeScreenRoute(context: context);
      } else if (!FirebaseGoogleAuthHelper.lastGoogleCancelled) {
        ShowToast().showNormalToast(
          msg:
              FirebaseGoogleAuthHelper.lastGoogleErrorMessage ??
              'Google sign-in failed.',
        );
      }
    } catch (e) {
      ShowToast().showNormalToast(
        msg:
            FirebaseGoogleAuthHelper.lastGoogleErrorMessage ??
            'Google sign-in failed.',
      );
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _signInWithApple() async {
    if (_appleLoading) return;

    if (!AppConstants.enableAppleSignIn) {
      ShowToast().showNormalToast(
        msg: 'Apple sign-in is unavailable in this build',
      );
      return;
    }

    setState(() => _appleLoading = true);
    try {
      final helper = FirebaseGoogleAuthHelper();
      final profileData = await helper.loginWithApple();
      if (profileData != null) {
        await AuthService().handleSocialLoginSuccessWithProfileData(
          profileData,
        );
        if (!mounted) return;
        await AuthService().ensureInMemoryUserModel();
        await Future.delayed(const Duration(milliseconds: 120));
        if (mounted) RouterClass().homeScreenRoute(context: context);
      } else if (!FirebaseGoogleAuthHelper.lastAppleCancelled) {
        ShowToast().showNormalToast(
          msg:
              FirebaseGoogleAuthHelper.lastAppleErrorMessage ??
              'Apple sign-in is not available on this device',
        );
      }
    } catch (e) {
      ShowToast().showNormalToast(
        msg:
            FirebaseGoogleAuthHelper.lastAppleErrorMessage ??
            'Apple sign-in failed.',
      );
    } finally {
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  Future<void> _handleContinueAsGuest() async {
    if (_guestLoading) return;
    setState(() => _guestLoading = true);
    try {
      await GuestModeService().enableGuestMode();
      if (!mounted) return;
      ShowToast().showNormalToast(msg: 'Welcome. You are browsing as a guest.');
      RouterClass().homeScreenRoute(context: context);
    } catch (e) {
      ShowToast().showNormalToast(
        msg: 'Error entering guest mode: ${e.toString()}',
      );
    } finally {
      if (mounted) setState(() => _guestLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AttendUsAuthLayout(
      title: 'Welcome to Attendus',
      subtitle:
          'Discover events, manage attendance, and check in securely from one professional workspace.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AttendUsButton.primary(
            label: 'Create account',
            icon: Icons.person_add_alt_1_outlined,
            onPressed: () => RouterClass.nextScreenNormal(
              context,
              const CreateAccountScreen(),
            ),
          ),
          const SizedBox(height: 10),
          AttendUsButton.secondary(
            label: 'Sign in',
            icon: Icons.login,
            onPressed: () =>
                RouterClass.nextScreenNormal(context, const LoginScreen()),
          ),
          const SizedBox(height: 18),
          const _DividerLabel(),
          const SizedBox(height: 18),
          AttendUsSocialButton(
            icon: const FaIcon(
              FontAwesomeIcons.google,
              color: Color(0xFF4285F4),
              size: 18,
            ),
            label: 'Continue with Google',
            loading: _googleLoading,
            onPressed: _signInWithGoogle,
          ),
          if (AppConstants.enableAppleSignIn) ...[
            const SizedBox(height: 10),
            AttendUsSocialButton(
              icon: const Icon(Icons.apple, color: Colors.black),
              label: 'Continue with Apple',
              loading: _appleLoading,
              onPressed: _signInWithApple,
            ),
          ],
          const SizedBox(height: 18),
          AttendUsActionTile(
            icon: Icons.explore_outlined,
            title: 'Continue as guest',
            subtitle:
                'Browse public events first. Creating and managing events requires an account.',
            actionLabel: _guestLoading ? null : 'Browse',
            tone: AttendUsStatusTone.neutral,
            onTap: _guestLoading ? null : _handleContinueAsGuest,
          ),
        ],
      ),
    );
  }
}

class _DividerLabel extends StatelessWidget {
  const _DividerLabel();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or use single sign-on',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
