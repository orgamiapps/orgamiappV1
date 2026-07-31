import 'dart:io';

const _defaultBundlePath = 'build/web/main.dart.js';
const _defaultMaxGzipBytes = 1800000;

Future<void> main(List<String> arguments) async {
  final bundlePath = arguments.isEmpty ? _defaultBundlePath : arguments.first;
  final maxGzipBytes = arguments.length < 2
      ? _defaultMaxGzipBytes
      : int.parse(arguments[1]);
  final bundle = File(bundlePath);

  if (!await bundle.exists()) {
    stderr.writeln('Bundle not found: $bundlePath');
    exitCode = 2;
    return;
  }

  final rawBytes = await bundle.readAsBytes();
  final gzipBytes = gzip.encode(rawBytes).length;
  final gzipMegabytes = gzipBytes / 1000000;
  final budgetMegabytes = maxGzipBytes / 1000000;

  stdout.writeln(
    'Initial web bundle: ${gzipMegabytes.toStringAsFixed(3)} MB gzip '
    '(budget: ${budgetMegabytes.toStringAsFixed(3)} MB)',
  );

  if (gzipBytes > maxGzipBytes) {
    stderr.writeln(
      'Bundle budget exceeded by ${gzipBytes - maxGzipBytes} gzip bytes.',
    );
    exitCode = 1;
  }
}
