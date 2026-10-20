import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:attendus/models/event_model.dart';
import 'event_share_service.dart';

enum EventQrFormat { card, qrOnly }

/// Screen-independent artwork. No network images, event credentials, or IDs.
class EventQrImage {
  static String filename(EventModel event, EventQrFormat format) {
    var slug = event.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    slug = slug.replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.isEmpty) slug = 'event';
    if (slug.length > 60) slug = slug.substring(0, 60);
    return '$slug-${format == EventQrFormat.card ? 'event-card' : 'qr'}.png';
  }

  static Future<Uint8List> render(
    EventModel event,
    EventQrFormat format,
  ) async {
    const width = 1080;
    final height = format == EventQrFormat.card ? 1420 : 1080;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    final url = EventShareService.eventUri(event.id).toString();
    final code = QrCode.fromData(
      data: url,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final matrix = QrImage(code);
    // Integer module sizes, at least four white modules on every edge.
    final module = (936 / (matrix.moduleCount + 8)).floor();
    final side = module * matrix.moduleCount;
    final left = ((width - side) / 2).floorToDouble();
    final top = format == EventQrFormat.card
        ? 330.0 + 4 * module
        : ((height - side) / 2).floorToDouble();
    final paint = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    for (var row = 0; row < matrix.moduleCount; row++) {
      for (var col = 0; col < matrix.moduleCount; col++) {
        if (matrix.isDark(row, col)) {
          canvas.drawRect(
            Rect.fromLTWH(
              left + col * module,
              top + row * module,
              module.toDouble(),
              module.toDouble(),
            ),
            paint,
          );
        }
      }
    }
    void label(
      String value,
      double y,
      double size,
      Color color, {
      int lines = 1,
      FontWeight weight = FontWeight.normal,
    }) {
      final text = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: size,
            fontWeight: weight,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: lines,
        ellipsis: '…',
      )..layout(maxWidth: 936);
      text.paint(canvas, Offset((width - text.width) / 2, y));
      text.dispose();
    }

    if (format == EventQrFormat.card) {
      label(
        'ATTENDUS',
        54,
        28,
        const Color(0xFF13776C),
        weight: FontWeight.w700,
      );
      label(
        event.title.trim(),
        115,
        52,
        const Color(0xFF142C40),
        lines: 2,
        weight: FontWeight.w700,
      );
      label(event.schedule.dateLabel, 240, 26, const Color(0xFF526171));
      label(event.schedule.timeLabel, 280, 24, const Color(0xFF526171));
      label(
        'Scan to view event',
        1270,
        38,
        const Color(0xFF142C40),
        weight: FontWeight.w600,
      );
      label(Uri.parse(url).host, 1335, 28, const Color(0xFF526171));
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Could not prepare QR image');
      return bytes.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }
}
