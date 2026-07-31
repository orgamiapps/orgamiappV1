import 'package:attendus_admin/core/permissions.dart';
import 'package:attendus_admin/models/api_models.dart';
import 'package:attendus_admin/ui/mutation_dialog.dart';
import 'package:attendus_admin/ui/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('permissions are role-aware and billing cannot manage roles', () {
    final billing = AdminPermissions.fromWire(['billing_admin']);
    expect(billing.subscriptionsMutate, isTrue);
    expect(billing.roleManagement, isFalse);
    expect(billing.moderation, isFalse);
    expect(AdminPermissions.fromWire(['super_admin']).roleManagement, isTrue);
  });
  test('pagination tracks opaque cursor history', () {
    final pagination = PaginationCursor();
    expect(pagination.token, isNull);
    expect(pagination.forward('next-1'), isTrue);
    expect(pagination.token, 'next-1');
    expect(pagination.back(), isTrue);
    expect(pagination.token, isNull);
    pagination.reset();
    expect(pagination.canGoBack, isFalse);
  });
  testWidgets('sign-in submits credentials through authentication callback', (
    tester,
  ) async {
    String? email, password;
    await tester.pumpWidget(
      MaterialApp(
        home: SignInScreen(
          onSignIn: (e, p) async {
            email = e;
            password = p;
          },
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).at(0), 'admin@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'secret-value');
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(email, 'admin@example.com');
    expect(password, 'secret-value');
  });
  testWidgets('unauthorized and error states offer retry', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AccessErrorScreen(
          message: 'Offline',
          onRetry: () => retried = true,
          onSignOut: () {},
        ),
      ),
    );
    expect(find.text('Offline'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });
  testWidgets(
    'destructive confirmation requires reason, word, and acknowledgment',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MutationDialog(
              title: 'Disable',
              description: 'Affects a real user.',
            ),
          ),
        ),
      );
      final confirm = find.widgetWithText(FilledButton, 'Confirm');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(
        find.byType(TextField).at(0),
        'Verified customer support request',
      );
      await tester.enterText(find.byType(TextField).at(1), 'CONFIRM');
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    },
  );
}
