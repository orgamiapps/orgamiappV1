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
    'qualified release checks deferred chunks before sealing and live bytes after publication',
    () {
      final candidateWorkflow = File(
        '.github/workflows/firebase-release.yml',
      ).readAsStringSync();
      final promotionWorkflow = File(
        '.github/workflows/web-release-promote.yml',
      ).readAsStringSync();
      final pipeline = File('tools/web_release_pipeline.js').readAsStringSync();
      final verifier = File('tools/verify_web_hosting.js').readAsStringSync();
      final contract = File('tools/web_release_contract.js').readAsStringSync();
      final promotion = pipeline.substring(
        pipeline.indexOf('async function promote('),
        pipeline.indexOf('async function main('),
      );
      final deployment = pipeline.substring(
        pipeline.indexOf('async function deploy('),
        pipeline.indexOf('async function qualify('),
      );

      // This guards the active workflow wiring. The Node contract/Hosting
      // suites exercise artifact drift, live hash mismatches and state changes.
      expect(
        candidateWorkflow,
        stringContainsInOrder([
          'origin=https://attendus.app/',
          r'dart run tools/retain_web_releases.dart "$origin"',
          r'dart run tools/package_web_release.dart --release-id "$RELEASE_ID"',
          'dart run tools/check_deferred_web_chunks.dart',
          'node tools/web_release_pipeline.js seal',
          r'name: web-candidate-${{ matrix.environment }}',
        ]),
      );
      expect(
        promotionWorkflow,
        contains(
          'node tools/web_release_pipeline.js promote --qualification-run',
        ),
      );
      expect(promotionWorkflow, contains('--expected-prior-release'));
      expect(
        promotion,
        stringContainsInOrder([
          '"web-candidate-production"',
          'provenance.artifactSha256 !== receipt.provenance.production.artifactSha256',
          'c.digest(candidate) !== receipt.productionCandidateSha256',
          'args["expected-prior-release"] !== candidate.predecessor.production.hostingVersion',
          'await deploy(candidate,',
        ]),
      );
      for (final buildCommand in [
        'flutter build',
        'tools/retain_web_releases.dart',
        'tools/package_web_release.dart',
      ]) {
        expect(promotionWorkflow, isNot(contains(buildCommand)));
        expect(promotion, isNot(contains(buildCommand)));
      }
      expect(
        deployment,
        stringContainsInOrder([
          'c.validateArtifact(candidate, root, path.join(bundle, "web"))',
          'deployStep("hosting", "hosting")',
          'await verifyPublishedDeployment(candidate, publishedHosting,',
          'write(output,',
        ]),
      );
      expect(
        contract,
        contains('digest(files(webRoot)) !== candidate.webSha256'),
      );
      expect(pipeline, contains('await http(candidate,'));
      expect(
        pipeline,
        contains('require("./verify_web_hosting").verifyHosting('),
      );
      expect(
        verifier,
        contains('["https://attendus.app", "https://orgami-66nxok.web.app"]'),
      );
      expect(
        verifier,
        contains(r'name.startsWith(`releases/${candidate.releaseId}/`)'),
      );
      expect(verifier, contains('expectedSha256: candidate.webFiles[name]'));
      expect(verifier, contains('record.sha256 !== target.expectedSha256'));
      expect(
        verifier,
        contains('receipt.matchedUrls.length !== targets.length'),
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
