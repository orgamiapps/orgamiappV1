import 'dart:async';

import 'package:attendus/widgets/app_startup_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('shows pending state, then renders the app and reports ready', (
    tester,
  ) async {
    final initialization = Completer<void>();
    var readyCalls = 0;

    await tester.pumpWidget(
      _wrap(
        AppStartupGate(
          initialization: initialization.future,
          onRetry: () => initialization.future,
          onReady: () => readyCalls++,
          child: const Text('App ready'),
        ),
      ),
    );

    expect(find.text('Attendus'), findsOneWidget);
    expect(find.text('Checking your session...'), findsOneWidget);

    initialization.complete();
    await tester.pump();
    await tester.pump();

    expect(find.text('App ready'), findsOneWidget);
    expect(readyCalls, 1);
  });

  testWidgets('shows failure state and retries with a replacement future', (
    tester,
  ) async {
    final firstAttempt = Completer<void>();
    final retryAttempt = Completer<void>();
    var retryCalls = 0;

    await tester.pumpWidget(
      _wrap(
        AppStartupGate(
          initialization: firstAttempt.future,
          onRetry: () {
            retryCalls++;
            return retryAttempt.future;
          },
          child: const Text('App ready'),
        ),
      ),
    );

    firstAttempt.completeError(StateError('offline'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Unable to start Attendus'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    expect(retryCalls, 1);
    expect(find.text('Checking your session...'), findsOneWidget);

    retryAttempt.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('App ready'), findsOneWidget);
  });

  testWidgets('does not report ready after disposal', (tester) async {
    final initialization = Completer<void>();
    var readyCalls = 0;

    await tester.pumpWidget(
      _wrap(
        AppStartupGate(
          initialization: initialization.future,
          onRetry: () => initialization.future,
          onReady: () => readyCalls++,
          child: const Text('App ready'),
        ),
      ),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    initialization.complete();
    await tester.pump();

    expect(readyCalls, 0);
  });
}
