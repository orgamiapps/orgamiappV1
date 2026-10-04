import 'package:attendus/Services/artifact_download_native.dart' as native;
import 'package:attendus/Services/artifact_download_result.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test('reports platform outcomes without claiming files were saved', () async {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      debugDefaultTargetPlatformOverride = platform;
      for (final status in ShareResultStatus.values) {
        final result = await native.downloadArtifact(
          Uint8List.fromList([1]),
          'roster.csv',
          'text/csv',
          sharePositionOrigin: const Rect.fromLTWH(20, 20, 40, 40),
          share: (params) async {
            expect(
              params.sharePositionOrigin,
              const Rect.fromLTWH(20, 20, 40, 40),
            );
            expect(params.fileNameOverrides, ['roster.csv']);
            return ShareResult('test', status);
          },
        );
        expect(result.status, switch (status) {
          ShareResultStatus.dismissed => ArtifactDownloadStatus.dismissed,
          ShareResultStatus.unavailable =>
            ArtifactDownloadStatus.outcomeUnavailable,
          ShareResultStatus.success =>
            platform == TargetPlatform.iOS
                ? ArtifactDownloadStatus.shareCompleted
                : ArtifactDownloadStatus.shareActionSelected,
        });
        expect(result.message.toLowerCase(), isNot(contains('saved')));
      }
    }
  });
  test('platform exception reports failure', () async {
    final result = await native.downloadArtifact(
      Uint8List(1),
      'file.csv',
      'text/csv',
      share: (_) async => throw StateError('unsupported'),
    );
    expect(result.status, ArtifactDownloadStatus.failed);
  });
  testWidgets('popover origin stays inside the view', (tester) async {
    late BuildContext anchor;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              anchor = context;
              return const SizedBox(width: 80, height: 40);
            },
          ),
        ),
      ),
    );
    final rect = artifactShareOrigin(anchor);
    expect(rect.width, greaterThan(0));
    expect(rect.height, greaterThan(0));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(800));
    expect(rect.bottom, lessThanOrEqualTo(600));
  });
}
