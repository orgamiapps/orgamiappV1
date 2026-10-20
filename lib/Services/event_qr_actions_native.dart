import 'dart:typed_data';
import 'dart:ui';
import 'package:share_plus/share_plus.dart';
import 'event_qr_action_result.dart';

bool get canCopyQrImage => false;
bool get canPreviewQrImage => false;
Future<EventQrActionResult> copyQrImage(Uint8List bytes) async =>
    EventQrActionResult.unsupported;
bool previewQrImage(Uint8List bytes, String filename) => false;
bool canShareQrImage(Uint8List bytes, String filename) => true;
Future<EventQrActionResult> shareQrImage(
  Uint8List bytes,
  String filename,
  String title,
  String text,
  Rect origin,
) async {
  try {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'image/png')],
        fileNameOverrides: [filename],
        title: title,
        subject: title,
        text: text,
        sharePositionOrigin: origin,
      ),
    );
    return switch (result.status) {
      ShareResultStatus.success => EventQrActionResult.completed,
      ShareResultStatus.dismissed => EventQrActionResult.dismissed,
      ShareResultStatus.unavailable => EventQrActionResult.unavailable,
    };
  } catch (_) {
    return EventQrActionResult.failed;
  }
}
