import 'dart:async';

import 'package:attendus/Utils/deferred_load_recovery.dart';
import 'package:attendus/widgets/deferred_screen_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

class _FakeDeferredLoadRecovery implements DeferredLoadRecovery {
  _FakeDeferredLoadRecovery({this.claimResult = false});

  @override
  final bool canRefreshApp = true;
  bool claimResult;
  int refreshCalls = 0;
  final List<String> claimedKeys = [];
  final List<String> clearedKeys = [];

  @override
  bool claimAutomaticRefresh(String recoveryKey) {
    claimedKeys.add(recoveryKey);
    return claimResult;
  }

  @override
  void clearRecoveryGuard(String recoveryKey) {
    clearedKeys.add(recoveryKey);
  }

  @override
  void refreshApp() {
    refreshCalls++;
  }
}

void main() {
  testWidgets('loads once and keeps the loaded screen state on rebuild', (
    tester,
  ) async {
    final loaded = Completer<void>();
    final recovery = _FakeDeferredLoadRecovery();
    var loadCalls = 0;

    Widget buildLoader() => DeferredScreenLoader(
      recoveryKey: 'dashboard',
      recovery: recovery,
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
    expect(recovery.clearedKeys, ['dashboard']);

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
          recoveryKey: 'native-test',
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
    expect(find.text('Refresh app'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(loadCalls, 2);
    expect(find.text('Deferred section'), findsOneWidget);
  });

  testWidgets('first web failure refreshes once and shows updating state', (
    tester,
  ) async {
    final recovery = _FakeDeferredLoadRecovery(claimResult: true);

    await tester.pumpWidget(
      _wrap(
        DeferredScreenLoader(
          recoveryKey: 'groups',
          recovery: recovery,
          loadLibrary: () => Future<void>.error('stale chunk'),
          builder: () => const Text('Groups'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Updating Attendus...'), findsOneWidget);
    expect(find.text('This section could not be loaded.'), findsNothing);
    expect(recovery.claimedKeys, ['groups']);
    expect(recovery.refreshCalls, 1);
  });

  testWidgets('repeated web failure stops and offers manual recovery', (
    tester,
  ) async {
    final recovery = _FakeDeferredLoadRecovery(claimResult: false);

    await tester.pumpWidget(
      _wrap(
        DeferredScreenLoader(
          recoveryKey: 'messages',
          recovery: recovery,
          loadLibrary: () => Future<void>.error('still unavailable'),
          builder: () => const Text('Messages'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('This section could not be loaded.'), findsOneWidget);
    expect(find.text('Refresh app'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(recovery.refreshCalls, 0);

    await tester.tap(find.text('Refresh app'));
    await tester.pump();

    expect(find.text('Updating Attendus...'), findsOneWidget);
    expect(recovery.refreshCalls, 1);
  });

  test('reload guards are isolated by deferred section', () {
    final storage = <String, String>{};
    final guard = DeferredReloadGuard(
      read: (key) => storage[key],
      write: (key, value) => storage[key] = value,
      remove: storage.remove,
    );

    expect(guard.claim('groups'), isTrue);
    expect(guard.claim('messages'), isTrue);
    expect(guard.claim('groups'), isFalse);
    expect(guard.claim('messages'), isFalse);

    guard.clear('groups');

    expect(guard.claim('groups'), isTrue);
    expect(guard.claim('messages'), isFalse);
  });

  test('reload guard fails closed when session storage is unavailable', () {
    final guard = DeferredReloadGuard(
      read: (_) => throw StateError('storage unavailable'),
      write: (_, _) => throw StateError('storage unavailable'),
      remove: (_) => throw StateError('storage unavailable'),
    );

    expect(guard.claim('profile'), isFalse);
    expect(() => guard.clear('profile'), returnsNormally);
  });
}
