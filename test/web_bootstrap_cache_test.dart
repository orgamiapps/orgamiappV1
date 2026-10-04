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
    expect(index, contains('__ATTENDUS_PRIMARY_ORIGIN__'));
    expect(index, contains('__ATTENDUS_WORKER_BRIDGE_ENABLED__'));
  });

  test('web releases configure Firebase for the selected environment', () {
    final options = File('lib/firebase_options.dart').readAsStringSync();
    final worker = File('web/firebase-messaging-sw.js').readAsStringSync();
    final configurationTool = File(
      'tools/configure_web_environment.dart',
    ).readAsStringSync();
    final buildScript = File(
      'scripts/build_web_release.ps1',
    ).readAsStringSync();

    expect(options, contains("'ATTENDUS_FIREBASE_ENV'"));
    expect(options, contains("projectId: 'attendus-staging'"));
    expect(worker, contains('__ATTENDUS_FIREBASE_PROJECT_ID__'));
    expect(configurationTool, contains("'staging':"));
    expect(configurationTool, contains("'attendus-staging'"));
    expect(configurationTool, contains('_verifyFirebaseIsolation'));
    expect(configurationTool, contains("'orgami-66nxok'"));
    expect(
      buildScript,
      contains('dart run tools/configure_web_environment.dart'),
    );
    expect(
      buildScript,
      contains(r'"--dart-define=ATTENDUS_FIREBASE_ENV=$Environment"'),
    );
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

      expect(deployScript, contains('dart run tools/retain_web_releases.dart'));
      expect(deployScript, contains('dart run tools/package_web_release.dart'));
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

  test('retained release downloads retry validated immutable assets', () {
    final retentionTool = File(
      'tools/retain_web_releases.dart',
    ).readAsStringSync();

    expect(retentionTool, contains('const _maxDownloadAttempts = 4'));
    expect(retentionTool, contains('expectedBytes: expectedBytes'));
    expect(retentionTool, contains('bytes.length == expectedBytes'));
    expect(retentionTool, contains('Duration(milliseconds: 500 * attempt)'));
  });
}
