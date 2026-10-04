import 'dart:async';

import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/screens/Authentication/forgot_password_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';

class _Auth extends Fake implements FirebaseAuth {
  int calls = 0;
  Completer<void> response = Completer<void>();
  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) {
    calls++;
    return response.future;
  }
}

void main() {
  late _Auth auth;
  setUp(() {
    auth = _Auth();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('PonnamKarthik/fluttertoast'),
          (_) async => true,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('PonnamKarthik/fluttertoast'),
          null,
        );
  });
  Future<void> show(WidgetTester tester) async {
    auth.response = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AttendUsTheme.light,
        home: ForgotPasswordScreen(auth: auth),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'owner@example.test');
  }

  testWidgets(
    'one keyboard reset action sends exactly one request after button animation',
    (tester) async {
      await show(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(auth.calls, 1);
      await tester.pump(const Duration(milliseconds: 600));
      expect(auth.calls, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'repeat keyboard and button actions remain fenced until reset reply',
    (tester) async {
      await show(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.showKeyboard(find.byType(TextFormField));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      tester
          .widget<RoundedLoadingButton>(find.byType(RoundedLoadingButton))
          .onPressed!();
      await tester.pump(const Duration(milliseconds: 600));
      expect(auth.calls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('fast reset success does not dispatch a delayed second request', (
    tester,
  ) async {
    await show(tester);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    auth.response.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(auth.calls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
  testWidgets(
    'fast reset rejection permits one intentional retry without delayed package callback',
    (tester) async {
      await show(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      auth.response.completeError(
        FirebaseAuthException(code: 'too-many-requests'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(auth.calls, 1);
      auth.response = Completer<void>();
      await tester.showKeyboard(find.byType(TextFormField));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(auth.calls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'invalid reset email does not send and corrected input can send once',
    (tester) async {
      await show(tester);
      await tester.enterText(find.byType(TextFormField), 'invalid');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 600));
      expect(auth.calls, 0);
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'owner@example.test');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(auth.calls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
