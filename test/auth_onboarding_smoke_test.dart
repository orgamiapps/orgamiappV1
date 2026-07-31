import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/screens/Authentication/create_account/create_account_screen.dart';
import 'package:attendus/screens/Authentication/forgot_password_screen.dart';
import 'package:attendus/screens/Authentication/login_screen.dart';
import 'package:attendus/screens/Splash/second_splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(theme: AttendUsTheme.light, home: child);
}

void main() {
  testWidgets('onboarding renders guest, account, and sign-in entry points', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const SecondSplashScreen()));

    expect(find.text('Welcome to Attendus'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Continue as guest'), findsOneWidget);
  });

  testWidgets('login screen renders email and password form', (tester) async {
    await tester.pumpWidget(_wrap(const LoginScreen()));

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('create account screen renders first wizard step', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const CreateAccountScreen()));

    expect(find.text('Create Account'), findsOneWidget);
    expect(find.text('Step 1 of 5'), findsOneWidget);
    expect(find.text('First name'), findsWidgets);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('forgot password screen renders reset form', (tester) async {
    await tester.pumpWidget(_wrap(const ForgotPasswordScreen()));

    expect(find.text('Reset your password'), findsOneWidget);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Send reset link'), findsOneWidget);
  });
}
