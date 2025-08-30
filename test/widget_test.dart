// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:attendus/main.dart';
import 'package:attendus/Utils/theme_provider.dart';

void main() {
  testWidgets('App builds with ThemeProvider', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider()..loadTheme(false),
        child: const MyApp(
          homeOverride: Scaffold(body: Center(child: Text('Test Home'))),
        ),
      ),
    );

    expect(find.text('Test Home'), findsOneWidget);
  });
}
