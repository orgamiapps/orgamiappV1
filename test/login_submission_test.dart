import 'dart:async';

import 'package:attendus/Services/auth_service.dart';
import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/screens/Authentication/login_screen.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';

import 'support/auth_fakes.dart';

void main() {
  late TestFirebaseAuth auth;
  late AuthService service;
  late Completer<UserCredential> response;
  int attempts = 0;
  int navigations = 0;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    auth = TestFirebaseAuth();
    response = Completer<UserCredential>();
    attempts = 0;
    navigations = 0;
    CustomerController.logeInCustomer = null;
    auth.emailSignIn = () {
      attempts++;
      return response.future;
    };
    service = AuthService.forTesting(
      auth: auth,
      storage: TestSecureStorage(),
      loadCustomer: (_) async => null,
      initializeFirebase: () async {},
      onAuthenticatedSession: () async {},
      onLogout: () async {},
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('PonnamKarthik/fluttertoast'),
          (_) async => true,
        );
  });
  tearDown(() async {
    service.dispose();
    CustomerController.logeInCustomer = null;
    await auth.changes.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('PonnamKarthik/fluttertoast'),
          null,
        );
  });

  Future<void> show(WidgetTester tester) async {
    response = Completer<UserCredential>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AttendUsTheme.light,
        home: LoginScreen(
          authService: service,
          onSignedIn: () => navigations++,
        ),
      ),
    );
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'owner@example.test',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'test-password');
  }

  testWidgets(
    'one password Enter invokes exactly one authentication after button animation',
    (tester) async {
      await show(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(attempts, 1);
      await tester.pump(const Duration(milliseconds: 600));
      expect(attempts, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'repeat Enter while authentication is pending cannot submit again',
    (tester) async {
      await show(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.showKeyboard(find.byType(TextFormField).at(1));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 600));
      expect(attempts, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'actual loading button click submits once and repeated callback stays fenced',
    (tester) async {
      await show(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      final button = find.byType(RoundedLoadingButton);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(attempts, 1);
      tester.widget<RoundedLoadingButton>(button).onPressed!();
      await tester.pump();
      expect(attempts, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'invalid input makes no request and corrected keyboard input can submit',
    (tester) async {
      await show(tester);
      await tester.enterText(find.byType(TextFormField).at(1), 'short');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 600));
      expect(attempts, 0);
      expect(
        find.text('Password must be at least 6 characters.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'test-password');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(attempts, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'acknowledged login rejection permits one explicit keyboard retry',
    (tester) async {
      await show(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      response.completeError(FirebaseAuthException(code: 'invalid-credential'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(attempts, 1);
      response = Completer<UserCredential>();
      await tester.showKeyboard(find.byType(TextFormField).at(1));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(attempts, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'fast successful login keeps success state and navigates once without delayed second authentication',
    (tester) async {
      await show(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      final user = TestAuthUser('owner');
      auth.user = user;
      response.complete(TestUserCredential(user));
      await tester.pump();
      expect(
        tester
            .widget<RoundedLoadingButton>(find.byType(RoundedLoadingButton))
            .controller
            .currentState,
        ButtonState.success,
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(attempts, 1);
      expect(navigations, 1);
      expect(CustomerController.logeInCustomer?.uid, 'owner');
      await tester.showKeyboard(find.byType(TextFormField).at(1));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(attempts, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
