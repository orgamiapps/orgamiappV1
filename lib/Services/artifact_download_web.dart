import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'package:web/web.dart' as web;
import 'artifact_download_result.dart';

Future<ArtifactDownloadResult> downloadArtifact(
  Uint8List bytes,
  String filename,
  String contentType, {
  Rect? sharePositionOrigin,
}) async {
  String? url;
  web.HTMLAnchorElement? anchor;
  try {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: contentType),
    );
    url = web.URL.createObjectURL(blob);
    anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = filename;
    final body = web.document.body;
    if (body == null) throw StateError('Page is not ready');
    body.append(anchor);
    anchor.click();
    return const ArtifactDownloadResult(
      ArtifactDownloadStatus.downloadInitiated,
    );
  } catch (_) {
    return const ArtifactDownloadResult(ArtifactDownloadStatus.failed);
  } finally {
    anchor?.remove();
    if (url != null) {
      final objectUrl = url;
      Future<void>.delayed(
        const Duration(minutes: 1),
        () => web.URL.revokeObjectURL(objectUrl),
      );
    }
  }
}
