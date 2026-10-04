import 'dart:ui' show Rect;
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'artifact_download_result.dart';

Future<ArtifactDownloadResult> downloadArtifact(
  Uint8List bytes,
  String filename,
  String contentType, {
  Rect? sharePositionOrigin,
  @visibleForTesting Future<ShareResult> Function(ShareParams)? share,
}) async {
  try {
    final result = await (share ?? SharePlus.instance.share)(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: contentType, name: filename)],
        fileNameOverrides: [filename],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
    return ArtifactDownloadResult(switch (result.status) {
      ShareResultStatus.success =>
        defaultTargetPlatform == TargetPlatform.iOS
            ? ArtifactDownloadStatus.shareCompleted
            : ArtifactDownloadStatus.shareActionSelected,
      ShareResultStatus.dismissed => ArtifactDownloadStatus.dismissed,
      ShareResultStatus.unavailable =>
        ArtifactDownloadStatus.outcomeUnavailable,
    });
  } catch (_) {
    return const ArtifactDownloadResult(ArtifactDownloadStatus.failed);
  }
}
