import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  onScreenshot: (name, bytes, [args]) async {
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(name)) {
      throw ArgumentError('Unsafe screenshot name');
    }
    final directory = Directory(
      '${Platform.environment['ATTENDUS_BROWSER_EVIDENCE'] ?? 'build/debugging-flutter-integration'}/screenshots',
    );
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png').writeAsBytes(bytes);
    return bytes.isNotEmpty;
  },
);
