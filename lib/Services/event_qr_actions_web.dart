import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui';
import 'package:web/web.dart' as web;
import 'event_qr_action_result.dart';

bool get canCopyQrImage =>
    web.window.isSecureContext &&
    globalContext.has('ClipboardItem') &&
    web.window.navigator.has('clipboard');
bool get canPreviewQrImage => true;
web.Blob _blob(Uint8List bytes) =>
    web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'image/png'));
web.File _file(Uint8List bytes, String filename) => web.File(
  [bytes.toJS].toJS,
  filename,
  web.FilePropertyBag(type: 'image/png'),
);

Future<EventQrActionResult> copyQrImage(Uint8List bytes) async {
  if (!canCopyQrImage) return EventQrActionResult.unsupported;
  try {
    final items = JSObject()..setProperty('image/png'.toJS, _blob(bytes));
    // No asynchronous work before the browser call: retain user activation.
    await web.window.navigator.clipboard
        .write([web.ClipboardItem(items)].toJS)
        .toDart;
    return EventQrActionResult.completed;
  } catch (_) {
    return EventQrActionResult.failed;
  }
}

bool canShareQrImage(Uint8List bytes, String filename) {
  try {
    return web.window.navigator.canShare(
      web.ShareData(files: [_file(bytes, filename)].toJS),
    );
  } catch (_) {
    return false;
  }
}

Future<EventQrActionResult> shareQrImage(
  Uint8List bytes,
  String filename,
  String title,
  String text,
  Rect origin,
) async {
  if (!canShareQrImage(bytes, filename)) return EventQrActionResult.unsupported;
  try {
    await web.window.navigator
        .share(
          web.ShareData(
            files: [_file(bytes, filename)].toJS,
            title: title,
            text: text,
          ),
        )
        .toDart;
    return EventQrActionResult.completed;
  } catch (error) {
    if (error.isA<web.DOMException>() &&
        (error as web.DOMException).name == 'AbortError') {
      return EventQrActionResult.dismissed;
    }
    return EventQrActionResult.failed;
  }
}

bool previewQrImage(Uint8List bytes, String filename) {
  final url = web.URL.createObjectURL(_blob(bytes));
  // An actual browser image supports touch-and-hold saving, unlike canvas.
  final opened = web.window.open(url, '_blank');
  if (opened != null) opened.opener = null;
  Future<void>.delayed(
    const Duration(minutes: 5),
    () => web.URL.revokeObjectURL(url),
  );
  return opened != null;
}
