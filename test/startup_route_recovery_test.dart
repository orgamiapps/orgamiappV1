import 'dart:async';

import 'package:attendus/main.dart';
import 'package:attendus/Utils/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('new Discover routes reuse a pending startup retry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final initial = Completer<void>();
    final retry = Completer<void>();
    var retries = 0;
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider()..loadTheme(false),
        child: MyApp(
          homeOverride: const Scaffold(body: Text('Test home')),
          firebaseInitialization: initial.future,
          onFirebaseRetry: () {
            retries++;
            return retry.future;
          },
        ),
      ),
    );
    unawaited(appNavigatorKey.currentState!.pushNamed('/app/discover'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    initial.completeError(StateError('temporary connection failure'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Unable to start Attendus'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(retries, 1);
    unawaited(
      appNavigatorKey.currentState!.pushNamed(
        '/app/discover?distanceMode=auto',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Unable to start Attendus'), findsNothing);
    expect(find.text('Checking your session...'), findsWidgets);
    expect(retries, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    retry.complete();
    await tester.pump();
  });
}
