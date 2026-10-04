import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'artifact_download_result.dart';
import 'artifact_download_native.dart'
    if (dart.library.js_interop) 'artifact_download_web.dart'
    as platform;
export 'artifact_download_result.dart';

Future<ArtifactDownloadResult> downloadArtifact(
  Uint8List bytes,
  String filename,
  String contentType, {
  Rect? sharePositionOrigin,
}) => platform.downloadArtifact(
  bytes,
  filename,
  contentType,
  sharePositionOrigin: sharePositionOrigin,
);
