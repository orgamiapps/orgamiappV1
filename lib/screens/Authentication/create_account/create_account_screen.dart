import 'package:flutter/material.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/router.dart';
import 'package:provider/provider.dart';
import 'package:attendus/screens/Authentication/create_account/create_account_view_model.dart';
import 'package:attendus/screens/Authentication/create_account/steps/step_basic_info.dart';
import 'package:attendus/screens/Authentication/create_account/steps/step_password.dart';
import 'package:attendus/screens/Authentication/create_account/steps/step_profile_photo.dart';
import 'package:attendus/screens/Authentication/create_account/steps/step_professional_info.dart';
import 'package:attendus/screens/Authentication/create_account/steps/step_contacts.dart';
import 'package:attendus/Utils/app_constants.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/firebase/firebase_google_auth_helper.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  late final PageController _pageController = PageController();
  int _currentPage = 0;

  void _goTo(int index) {
    setState(() => _currentPage = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _goBack() {
    if (_currentPage > 0) {
      _goTo(_currentPage - 1);
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CreateAccountViewModel(),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              _header(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Column(
                  children: [
                    _buildGoogleSignInButton(context),
                    const SizedBox(height: 12),
                    if (AppConstants.enableAppleSignIn)
                      _buildAppleSignInButton(context),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    StepBasicInfo(onNext: () => _goTo(1)),
                    StepPassword(onNext: () => _goTo(2)),
                    StepProfilePhoto(
                      onSkip: () =>
                          RouterClass().homeScreenRoute(context: context),
                      onNext: () => _goTo(3),
                    ),
                    StepProfessionalInfo(
                      onSkip: () => _goTo(4),
                      onNext: () => _goTo(4),
                    ),
                    StepContacts(
                      onFinish: () =>
                          RouterClass().homeScreenRoute(context: context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    const titles = [
      'Create Account',
      'Set Password',
      'Profile Photo',
      'About You',
      'Find Contacts',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          IconButton(
            onPressed: _goBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            color: AppThemeColor.darkBlueColor,
          ),
          const SizedBox(width: 4),
          Text(
            titles[_currentPage],
            style: TextStyle(
              color: AppThemeColor.darkBlueColor,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          _progressDots(),
        ],
      ),
    );
  }

  Widget _progressDots() {
    return Row(
      children: List.generate(5, (i) {
        final active = i == _currentPage;
        return Container(
          width: active ? 20 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: active
                ? AppThemeColor.darkBlueColor
                : AppThemeColor.lightBlueColor.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(99),
          ),
        );
      }),
    );
  }

  Widget _buildGoogleSignInButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: AppThemeColor.darkBlueColor.withValues(alpha: 0.3),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: () async {
          final helper = FirebaseGoogleAuthHelper();
          final user = await helper.loginWithGoogle();
          if (user != null) {
            try {
              await FirebaseFirestoreHelper().ensureUserProfileCompleteness(
                user.uid,
              );
              if (!mounted) return;
              RouterClass().homeScreenRoute(context: context);
            } catch (_) {}
          } else {
            ShowToast().showNormalToast(msg: 'Google sign-in failed');
          }
        },
        icon: const FaIcon(
          FontAwesomeIcons.google,
          size: 18,
          color: Color(0xFF4285F4),
        ),
        label: const Text(
          'Continue with Google',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  Widget _buildAppleSignInButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: AppThemeColor.darkBlueColor.withValues(alpha: 0.3),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: () async {
          final helper = FirebaseGoogleAuthHelper();
          final user = await helper.loginWithApple();
          if (user != null) {
            try {
              await FirebaseFirestoreHelper().ensureUserProfileCompleteness(
                user.uid,
              );
              if (!mounted) return;
              RouterClass().homeScreenRoute(context: context);
            } catch (_) {}
          } else {
            ShowToast().showNormalToast(msg: 'Apple sign-in failed');
          }
        },
        icon: const Icon(Icons.apple, size: 20, color: Colors.black),
        label: const Text(
          'Continue with Apple',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}
