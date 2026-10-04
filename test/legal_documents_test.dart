import 'package:attendus/screens/Legal/privacy_policy_screen.dart';
import 'package:attendus/screens/Legal/terms_conditions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('privacy policy uses a fixed version and accurate containment', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PrivacyPolicyScreen()));

    expect(find.textContaining('Version 2026.08.02'), findsOneWidget);
    expect(find.textContaining('Facial enrollment'), findsOneWidget);
    expect(find.textContaining('currently disabled'), findsWidgets);
    expect(find.textContaining('[Your Jurisdiction]'), findsNothing);
  });

  testWidgets('terms omit placeholder jurisdiction and dynamic dates', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: TermsConditionsScreen()));

    expect(find.textContaining('Version 2026.08.02'), findsOneWidget);
    expect(find.textContaining('placeholder jurisdiction'), findsWidgets);
    expect(find.textContaining('[Your Jurisdiction]'), findsNothing);
    expect(find.textContaining('Last Updated:'), findsNothing);
  });
}
