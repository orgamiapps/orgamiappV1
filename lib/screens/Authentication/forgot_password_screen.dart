import 'dart:async';

import 'package:attendus/Utils/toast.dart';
import 'package:attendus/widgets/attendus_auth_layout.dart';
import 'package:attendus/widgets/attendus_design_system.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _btnCtlr = RoundedLoadingButtonController();
  final _emailEdtController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailEdtController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AttendUsAuthLayout(
      title: 'Reset your password',
      subtitle:
          'Enter the email attached to your Attendus account and we will send reset instructions.',
      leading: const AttendUsBackButton(),
      child: Form(
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
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
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
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: RoundedLoadingButton(
                animateOnTap: true,
                borderRadius: 12,
                controller: _btnCtlr,
                elevation: 0,
                color: Theme.of(context).colorScheme.primary,
                onPressed: _submit,
                child: const Text(
                  'Send reset link',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'For security, password reset links are sent only through Firebase Auth.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    _btnCtlr.start();
    if (_formKey.currentState!.validate()) {
      _resetPassword();
    } else {
      _btnCtlr.reset();
    }
  }

  Future<void> _resetPassword() async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailEdtController.text.trim(),
      );
      ShowToast().showNormalToast(
        msg: 'Password reset link sent to your email.',
      );
      _btnCtlr.success();
      Timer(const Duration(seconds: 2), () {
        if (mounted) Navigator.pop(context);
      });
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) debugPrint(e.code);
      switch (e.code) {
        case 'user-not-found':
          ShowToast().showNormalToast(
            msg: 'No account was found for this email address.',
          );
          break;
        case 'invalid-email':
          ShowToast().showNormalToast(
            msg: 'Please enter a valid email address.',
          );
          break;
        case 'too-many-requests':
          ShowToast().showNormalToast(
            msg: 'Too many requests. Please try again later.',
          );
          break;
        default:
          ShowToast().showNormalToast(
            msg: 'Unable to send reset instructions. Please try again.',
          );
      }
      _btnCtlr.reset();
    } catch (e) {
      _btnCtlr.reset();
      if (kDebugMode) debugPrint('Error resetting password: $e');
      ShowToast().showNormalToast(
        msg: 'Unable to send reset instructions. Please try again.',
      );
    }
  }
}
