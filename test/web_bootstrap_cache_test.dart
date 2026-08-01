import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy Flutter cache cleanup runs only once per browser', () {
    final index = File('web/index.html').readAsStringSync();

    expect(
      index,
      contains("const cleanupKey = 'attendus-legacy-flutter-cache-cleanup-v1'"),
    );
    expect(index, contains("localStorage.getItem(cleanupKey) !== 'done'"));
    expect(index, contains('if (!needsCleanup) return;'));
    expect(index, contains("localStorage.setItem(cleanupKey, 'done')"));
  });
}
