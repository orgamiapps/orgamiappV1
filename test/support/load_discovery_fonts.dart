import 'dart:io';
import 'package:flutter/services.dart';

// Use pinned Roboto fixtures instead of Ahem's artificial character widths when
// asserting above-the-fold geometry. SDK font caches differ across platforms.
Future<void> loadDiscoveryFonts() async {
  final loader = FontLoader('Roboto');
  for (final weight in ['regular', 'medium', 'bold']) {
    final file = File('test/fixtures/fonts/roboto-$weight.ttf');
    loader.addFont(
      file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
  }
  await loader.load();
}
