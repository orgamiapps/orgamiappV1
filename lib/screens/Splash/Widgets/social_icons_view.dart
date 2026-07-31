import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:attendus/firebase/firebase_google_auth_helper.dart';
import 'package:attendus/Services/auth_service.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/widgets/attendus_auth_layout.dart';

class SocialLoginView extends StatefulWidget {
  const SocialLoginView({super.key});

  @override
  State<SocialLoginView> createState() => _SocialLoginViewState();
}

class _SocialLoginViewState extends State<SocialLoginView> {
  bool _googleBtnLoading = false;

  @override
  Widget build(BuildContext context) {
    return AttendUsSocialButton(
      icon: const FaIcon(
        FontAwesomeIcons.google,
        color: Color(0xFF4285F4),
        size: 18,
      ),
      label: 'Continue with Google',
      loading: _googleBtnLoading,
      onPressed: () async {
        try {
          if (!_googleBtnLoading) {
            setState(() {
              _googleBtnLoading = true;
            });
            final helper = FirebaseGoogleAuthHelper();
            final profileData = await helper.loginWithGoogle();
            if (profileData != null) {
              try {
                await AuthService().handleSocialLoginSuccessWithProfileData(
                  profileData,
                );
                if (!mounted) return;
                // Ensure in-memory session model is ready before navigating
                await AuthService().ensureInMemoryUserModel();
                await Future.delayed(const Duration(milliseconds: 120));
                if (!mounted) return;
                RouterClass().homeScreenRoute(context: context);
              } catch (e) {
                ShowToast().showNormalToast(
                  msg: 'Error setting up profile: ${e.toString()}',
                );
              }
            } else {
              if (!FirebaseGoogleAuthHelper.lastGoogleCancelled) {
                ShowToast().showNormalToast(
                  msg:
                      FirebaseGoogleAuthHelper.lastGoogleErrorMessage ??
                      'Google sign-in failed.',
                );
              }
            }
          }
        } catch (e) {
          ShowToast().showNormalToast(
            msg:
                FirebaseGoogleAuthHelper.lastGoogleErrorMessage ??
                'Google sign-in error: ${e.toString()}',
          );
        } finally {
          if (mounted) {
            setState(() {
              _googleBtnLoading = false;
            });
          }
        }
      },
    );
  }
}
