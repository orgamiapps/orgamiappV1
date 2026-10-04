import 'package:flutter/widgets.dart';

enum ArtifactDownloadStatus {
  downloadInitiated,
  shareCompleted,
  shareActionSelected,
  dismissed,
  outcomeUnavailable,
  failed,
}

class ArtifactDownloadResult {
  const ArtifactDownloadResult(this.status);
  final ArtifactDownloadStatus status;
  String get message => switch (status) {
    ArtifactDownloadStatus.downloadInitiated =>
      'Download started. Check your browser downloads.',
    ArtifactDownloadStatus.shareCompleted =>
      'The selected share action reported completion.',
    ArtifactDownloadStatus.shareActionSelected =>
      'Share action selected. Check the destination app to finish.',
    ArtifactDownloadStatus.dismissed => 'Share dismissed.',
    ArtifactDownloadStatus.outcomeUnavailable =>
      'Share sheet opened. Completion could not be confirmed.',
    ArtifactDownloadStatus.failed =>
      'Could not open the download or share action. Please retry.',
  };
}

/// Capture before starting asynchronous export work; never retain a BuildContext.
Rect artifactShareOrigin(BuildContext context) {
  final viewport = Offset.zero & MediaQuery.sizeOf(context);
  final render = context.findRenderObject();
  if (render is RenderBox && render.hasSize && render.attached) {
    final bounds = (render.localToGlobal(Offset.zero) & render.size).intersect(
      viewport,
    );
    if (bounds.width > 0 && bounds.height > 0) return bounds;
  }
  return Rect.fromCenter(center: viewport.center, width: 1, height: 1);
}
