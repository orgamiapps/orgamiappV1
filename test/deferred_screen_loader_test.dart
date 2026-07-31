import 'dart:async';

import 'package:attendus/widgets/deferred_screen_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('loads once and keeps the loaded screen state on rebuild', (
    tester,
  ) async {
    final loaded = Completer<void>();
    var loadCalls = 0;

    Widget buildLoader() => DeferredScreenLoader(
      loadLibrary: () {
        loadCalls++;
        return loaded.future;
      },
      builder: () => const TextField(key: Key('deferred-field')),
    );

    await tester.pumpWidget(_wrap(buildLoader()));
    expect(loadCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    loaded.complete();
    await tester.pump();
    await tester.enterText(find.byKey(const Key('deferred-field')), 'retained');

    await tester.pumpWidget(_wrap(buildLoader()));
    await tester.pump();

    expect(loadCalls, 1);
    expect(find.text('retained'), findsOneWidget);
  });

  testWidgets('offers retry after a deferred library load failure', (
    tester,
  ) async {
    var loadCalls = 0;

    await tester.pumpWidget(
      _wrap(
        DeferredScreenLoader(
          loadLibrary: () {
            loadCalls++;
            if (loadCalls == 1) return Future<void>.error('offline');
            return Future<void>.value();
          },
          builder: () => const Text('Deferred section'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('This section could not be loaded.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(loadCalls, 2);
    expect(find.text('Deferred section'), findsOneWidget);
  });
}
