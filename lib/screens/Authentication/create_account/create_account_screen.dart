import 'package:flutter/material.dart';
import 'package:attendus/Utils/router.dart';
import 'package:provider/provider.dart';
import 'package:attendus/screens/Authentication/create_account/create_account_view_model.dart';
import 'package:attendus/screens/Authentication/create_account/steps/step_basic_info.dart';
import 'package:attendus/screens/Authentication/create_account/steps/step_password.dart';
import 'package:attendus/screens/Authentication/create_account/steps/step_profile_photo.dart';
import 'package:attendus/screens/Authentication/create_account/steps/step_professional_info.dart';
import 'package:attendus/screens/Authentication/create_account/steps/step_contacts.dart';
import 'package:attendus/widgets/attendus_auth_layout.dart';
import 'package:attendus/widgets/attendus_design_system.dart';

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  late final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _socialSigningIn = false;

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
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Stack(
          children: [
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _header(context),
                        const SizedBox(height: 16),
                        Expanded(
                          child: AttendUsCard(
                            padding: EdgeInsets.zero,
                            child: PageView(
                              controller: _pageController,
                              physics: const NeverScrollableScrollPhysics(),
                              children: [
                                StepBasicInfo(
                                  onNext: () => _goTo(1),
                                  onSocialSignIn: (isSigning) {
                                    setState(
                                      () => _socialSigningIn = isSigning,
                                    );
                                  },
                                ),
                                StepPassword(onNext: () => _goTo(2)),
                                StepProfilePhoto(
                                  onSkip: () => RouterClass().homeScreenRoute(
                                    context: context,
                                  ),
                                  onNext: () => _goTo(3),
                                ),
                                StepProfessionalInfo(
                                  onSkip: () => _goTo(4),
                                  onNext: () => _goTo(4),
                                ),
                                StepContacts(
                                  onFinish: () => RouterClass().homeScreenRoute(
                                    context: context,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_socialSigningIn)
              Container(
                color: Colors.black.withValues(alpha: 0.15),
                child: const Center(
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
          ],
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
    final theme = Theme.of(context);
    return AttendUsCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          AttendUsBackButton(onPressed: _goBack),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titles[_currentPage], style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  'Step ${_currentPage + 1} of 5',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
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
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(99),
          ),
        );
      }),
    );
  }
}
