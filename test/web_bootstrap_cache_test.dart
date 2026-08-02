import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy Flutter cache migration completes before app bootstrap', () {
    final index = File('web/index.html').readAsStringSync();

    expect(
      index,
      contains("const cleanupKey = 'attendus-legacy-flutter-cache-cleanup-v3'"),
    );
    expect(index, contains("localStorage.getItem(cleanupKey) !== 'done'"));
    expect(index, contains("localStorage.setItem(cleanupKey, 'done')"));
    expect(index, contains('await cleanupLegacyFlutterCache()'));
    expect(index, isNot(contains('Promise.race')));
    expect(index, contains('migrationBridgeUrl(migrationUrl.toString())'));
    expect(index, contains("searchParams.get('attendus_worker_return')"));
  });

  test('legacy Flutter service worker retires itself and its app cache', () {
    final worker = File(
      'web/flutter_service_worker_retirement.js',
    ).readAsStringSync();

    expect(worker, contains('self.skipWaiting()'));
    expect(worker, contains("cacheName.startsWith('flutter-')"));
    expect(worker, contains('self.registration.unregister()'));
    expect(worker, contains('client.navigate(client.url)'));
  });

  test(
    'production deploy validates deferred chunks before and after release',
    () {
      final deployScript = File('deploy_web.sh').readAsStringSync();

      expect(
        deployScript,
        contains('dart run tools/retain_web_releases.dart'),
      );
      expect(
        deployScript,
        contains('dart run tools/package_web_release.dart'),
      );
      expect(
        deployScript,
        contains('dart run tools/check_deferred_web_chunks.dart'),
      );
      expect(
        deployScript,
        contains(
          'dart run tools/check_deferred_web_chunks.dart https://attendus.app/',
        ),
      );
      expect(
        deployScript,
        contains(
          'dart run tools/check_deferred_web_chunks.dart '
          'https://orgami-66nxok.web.app/',
        ),
      );
    },
  );
}
