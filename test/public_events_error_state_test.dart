import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attendus/Services/public_events_repository.dart';
import 'package:attendus/widgets/public_events_error_state.dart';

void main() {
  testWidgets('shows a sanitized missing-index error and retries', (
    tester,
  ) async {
    var retryCount = 0;
    const failure = PublicEventsFailure(
      kind: PublicEventsFailureKind.missingIndex,
      code: 'failed-precondition',
      userMessage: 'Please try again in a moment.',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PublicEventsErrorState(
            failure: failure,
            onRetry: () => retryCount++,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('public-events-error')), findsOneWidget);
    expect(find.text('Events temporarily unavailable'), findsWidgets);
    expect(find.textContaining('firebase.google.com'), findsNothing);
    expect(find.textContaining('requires an index'), findsNothing);

    await tester.tap(find.text('Retry'));
    expect(retryCount, 1);
  });

  testWidgets('labels last-known-good results', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PublicEventsLastKnownNotice())),
    );

    expect(
      find.byKey(const Key('public-events-last-known-notice')),
      findsOneWidget,
    );
    expect(
      find.text('Showing recently loaded events while we reconnect.'),
      findsOneWidget,
    );
  });
}
