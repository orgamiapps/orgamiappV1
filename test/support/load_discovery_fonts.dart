import 'dart:io';
import 'package:flutter/services.dart';

// Use the bundled app font instead of Ahem's artificial character widths when
// asserting above-the-fold geometry. Flutter ships these fonts with its SDK.
Future<void> loadDiscoveryFonts() async {
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  final loader = FontLoader('Roboto');
  for (final weight in ['regular', 'medium', 'bold']) {
    final file = File.fromUri(
      artifacts.uri.resolve('material_fonts/roboto-$weight.ttf'),
    );
    loader.addFont(
      file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
  }
  await loader.load();
}
