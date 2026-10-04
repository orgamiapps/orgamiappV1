import 'dart:async';

import 'package:attendus/Services/firebase_initializer.dart';
import 'package:firebase_app_check_platform_interface/firebase_app_check_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _RetryingCore extends FirebasePlatform {
  final firstAttempt = Completer<FirebaseAppPlatform>();
  FirebaseAppPlatform? current;
  int calls = 0;

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async {
    calls++;
    if (calls == 1) return firstAttempt.future;
    return current = FirebaseAppPlatform(
      name ?? defaultFirebaseAppName,
      options!,
    );
  }

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => current!;

  @override
  List<FirebaseAppPlatform> get apps => [?current];
}

class _HangingAppCheck extends FirebaseAppCheckPlatform {
  final activation = Completer<void>();
  int calls = 0;

  @override
  FirebaseAppCheckPlatform delegateFor({required FirebaseApp app}) => this;

  @override
  FirebaseAppCheckPlatform setInitialValues() => this;

  @override
  Future<void> activate({
    WebProvider? webProvider,
    AndroidProvider? androidProvider,
    AppleProvider? appleProvider,
    AndroidAppCheckProvider? providerAndroid,
    AppleAppCheckProvider? providerApple,
    WindowsAppCheckProvider? providerWindows,
  }) {
    calls++;
    return activation.future;
  }
}

void main() {
  testWidgets(
    'native core timeout is retryable and a hung App Check cannot hold startup',
    (tester) async {
      final previousCore = FirebasePlatform.instance;
      final previousAppCheck = FirebaseAppCheckPlatform.instance;
      final previousTarget = debugDefaultTargetPlatformOverride;
      final core = _RetryingCore();
      final appCheck = _HangingAppCheck();
      FirebasePlatform.instance = core;
      FirebaseAppCheckPlatform.instance = appCheck;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final failures = <Object>[];
        final first = FirebaseInitializer.initializeOnce().catchError((
          Object error,
        ) {
          failures.add(error);
        });
        final concurrent = FirebaseInitializer.initializeOnce().catchError((
          Object error,
        ) {
          failures.add(error);
        });
        await tester.pump();
        expect(core.calls, 1);
        await tester.pump(const Duration(seconds: 9));
        expect(failures, isEmpty);
        await tester.pump(const Duration(seconds: 1));
        await Future.wait([first, concurrent]);
        expect(failures, hasLength(2));
        expect(failures, everyElement(isA<TimeoutException>()));
        expect(appCheck.calls, 0);

        var ready = 0;
        final retry = FirebaseInitializer.retry().then((_) => ready++);
        final sharedRetry = FirebaseInitializer.retry().then((_) => ready++);
        await tester.pump();
        expect(core.calls, 2);
        expect(appCheck.calls, 1);
        await tester.pump(const Duration(milliseconds: 4999));
        expect(ready, 0);
        await tester.pump(const Duration(milliseconds: 1));
        await Future.wait([retry, sharedRetry]);
        expect(ready, 2);
        expect(appCheck.activation.isCompleted, false);
        await FirebaseInitializer.initializeOnce();
        expect(core.calls, 2);
        expect(appCheck.calls, 1);
      } finally {
        FirebasePlatform.instance = previousCore;
        FirebaseAppCheckPlatform.instance = previousAppCheck;
        debugDefaultTargetPlatformOverride = previousTarget;
      }
    },
  );
}
