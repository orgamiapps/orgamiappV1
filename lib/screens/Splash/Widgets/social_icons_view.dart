import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:attendus/firebase/firebase_google_auth_helper.dart';
import 'package:attendus/Services/auth_service.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/Utils/toast.dart';

class SocialLoginView extends StatefulWidget {
  const SocialLoginView({super.key});

  @override
  State<SocialLoginView> createState() => _SocialLoginViewState();
}

class _SocialLoginViewState extends State<SocialLoginView> {
  bool _googleBtnLoading = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        try {
          if (!_googleBtnLoading) {
            setState(() {
              _googleBtnLoading = true;
            });
            final navigator = Navigator.of(context);
            final profileData = await FirebaseGoogleAuthHelper()
                .loginWithGoogle();
            if (profileData != null) {
              try {
                await AuthService().handleSocialLoginSuccessWithProfileData(
                  profileData,
                );
                if (!mounted) return;
                await AuthService().ensureInMemoryUserModel();
                RouterClass().homeScreenRoute(context: navigator.context);
              } catch (e) {
                ShowToast().showNormalToast(
                  msg: 'Error setting up profile: ${e.toString()}',
                );
              }
            } else {
              if (!FirebaseGoogleAuthHelper.lastGoogleCancelled) {
                ShowToast().showNormalToast(msg: 'Google sign-in failed');
              }
            }
            setState(() {
              _googleBtnLoading = false;
            });
          }
        } catch (e) {
          setState(() {
            _googleBtnLoading = false;
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppThemeColor.darkBlueColor, Color(0xFF1E4A8C)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppThemeColor.darkBlueColor.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: _googleBtnLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppThemeColor.pureWhiteColor,
                    ),
                  ),
                )
              : Icon(
                  FontAwesomeIcons.google,
                  color: AppThemeColor.pureWhiteColor,
                  size: 20,
                ),
        ),
      ),
    );
  }
}
