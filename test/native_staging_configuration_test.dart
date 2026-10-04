import 'package:attendus/firebase_options.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test('native staging cannot fall back to production without config', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    if (DefaultFirebaseOptions.environment != 'staging') {
      expect(DefaultFirebaseOptions.currentPlatform.projectId, 'orgami-66nxok');
      return;
    }
    expect(() => DefaultFirebaseOptions.currentPlatform, throwsStateError);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(() => DefaultFirebaseOptions.currentPlatform, throwsStateError);
  });
}
