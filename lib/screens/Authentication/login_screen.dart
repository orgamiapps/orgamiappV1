import 'package:attendus/Services/auth_service.dart';
import 'package:attendus/Utils/app_constants.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/firebase/firebase_google_auth_helper.dart';
import 'package:attendus/screens/Authentication/create_account/create_account_screen.dart';
import 'package:attendus/screens/Authentication/forgot_password_screen.dart';
import 'package:attendus/widgets/attendus_auth_layout.dart';
import 'package:attendus/widgets/attendus_design_system.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _btnCtlr = RoundedLoadingButtonController();
  final _emailEdtController = TextEditingController();
  final _passwordEdtController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _socialSigningIn = false;

  @override
  void dispose() {
    _emailEdtController.dispose();
    _passwordEdtController.dispose();
    super.dispose();
  }

  Future<void> _makeLogin() async {
    try {
      final email = _emailEdtController.text.trim();
      final password = _passwordEdtController.text;

      Logger.debug('Starting email/password login...');
      final user = await AuthService().signInWithEmailAndPassword(
        email,
        password,
      );

      if (user != null && mounted) {
        Logger.debug('Login successful, navigating to home.');
        _btnCtlr.success();
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) RouterClass().homeScreenRoute(context: context);
      } else {
        Logger.warning('Login failed - no user returned');
        _btnCtlr.reset();
        ShowToast().showNormalToast(msg: 'Login failed. Please try again.');
      }
    } on FirebaseAuthException catch (e) {
      Logger.warning('Firebase Auth Exception: ${e.code}');
      switch (e.code) {
        case 'invalid-credential':
          ShowToast().showNormalToast(
            msg: 'Invalid email or password. Please check your credentials.',
          );
          break;
        case 'network-request-failed':
          ShowToast().showNormalToast(
            msg: 'Network error. Please check your connection and try again.',
          );
          break;
        case 'ERROR_WRONG_PASSWORD':
        case 'wrong-password':
          ShowToast().showNormalToast(msg: 'The password is incorrect.');
          break;
        case 'ERROR_USER_NOT_FOUND':
        case 'user-not-found':
          ShowToast().showNormalToast(
            msg: 'No Attendus account exists for this email.',
          );
          break;
        case 'ERROR_USER_DISABLED':
        case 'user-disabled':
          ShowToast().showNormalToast(msg: 'This account has been disabled.');
          break;
        case 'ERROR_TOO_MANY_REQUESTS':
        case 'too-many-requests':
          ShowToast().showNormalToast(
            msg: 'Too many attempts. Please try again later.',
          );
          break;
        case 'ERROR_OPERATION_NOT_ALLOWED':
        case 'operation-not-allowed':
          ShowToast().showNormalToast(
            msg: 'Email and password sign-in is not enabled.',
          );
          break;
        default:
          ShowToast().showNormalToast(
            msg: 'Login failed: ${e.message ?? 'Please try again.'}',
          );
      }
      _btnCtlr.reset();
    } catch (e) {
      _btnCtlr.reset();
      Logger.error('Error making login', e);
      ShowToast().showNormalToast(msg: 'Login failed. Please try again.');
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_socialSigningIn) return;
    setState(() => _socialSigningIn = true);
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
      } else if (!FirebaseGoogleAuthHelper.lastGoogleCancelled &&
          !FirebaseGoogleAuthHelper.lastGoogleRedirectStarted) {
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
      if (mounted) setState(() => _socialSigningIn = false);
    }
  }

  Future<void> _signInWithApple() async {
    if (_socialSigningIn) return;
    setState(() => _socialSigningIn = true);
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
              'Apple sign-in failed.',
        );
      }
    } catch (e) {
      ShowToast().showNormalToast(
        msg:
            FirebaseGoogleAuthHelper.lastAppleErrorMessage ??
            'Apple sign-in failed.',
      );
    } finally {
      if (mounted) setState(() => _socialSigningIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AttendUsAuthLayout(
      title: 'Welcome back',
      subtitle:
          'Sign in to discover events, manage attendance, and check in securely.',
      leading: const AttendUsBackButton(),
      footer: TextButton(
        onPressed: () =>
            RouterClass.nextScreenNormal(context, const CreateAccountScreen()),
        child: const Text('New to Attendus? Create an account'),
      ),
      child: Stack(
        children: [
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AttendUsFormTextField(
                  controller: _emailEdtController,
                  labelText: 'Email address',
                  hintText: 'you@example.com',
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isEmpty) return 'Enter your email address.';
                    if (!RegExp(
                      r'^[\w\.-]+@[\w\.-]+\.[A-Za-z]{2,}$',
                    ).hasMatch(email)) {
                      return 'Enter a valid email address.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                AttendUsFormTextField(
                  controller: _passwordEdtController,
                  labelText: 'Password',
                  hintText: 'Enter your password',
                  prefixIcon: Icons.lock_outline,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submitLogin(),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Show password'
                        : 'Hide password',
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Enter your password.';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters.';
                    }
                    return null;
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => RouterClass.nextScreenNormal(
                      context,
                      const ForgotPasswordScreen(),
                    ),
                    child: const Text('Forgot password?'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 52,
                  child: RoundedLoadingButton(
                    animateOnTap: true,
                    borderRadius: 12,
                    controller: _btnCtlr,
                    elevation: 0,
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: _submitLogin,
                    child: const Text(
                      'Sign in',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
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
                  loading: _socialSigningIn,
                  onPressed: _signInWithGoogle,
                ),
                if (AppConstants.enableAppleSignIn) ...[
                  const SizedBox(height: 10),
                  AttendUsSocialButton(
                    icon: const Icon(Icons.apple, color: Colors.black),
                    label: 'Continue with Apple',
                    loading: _socialSigningIn,
                    onPressed: _signInWithApple,
                  ),
                ],
              ],
            ),
          ),
          if (_socialSigningIn)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.55),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _submitLogin() {
    _btnCtlr.start();
    if (_formKey.currentState!.validate()) {
      _makeLogin();
    } else {
      _btnCtlr.reset();
    }
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
          child: Text('or', style: Theme.of(context).textTheme.labelMedium),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
