import 'dart:io';

void main() {
  final webDirectory = Directory('build/web');
  final mainBundle = File('${webDirectory.path}/main.dart.js');
  final bootstrap = File('${webDirectory.path}/flutter_bootstrap.js');
  final index = File('${webDirectory.path}/index.html');

  for (final file in [mainBundle, bootstrap, index]) {
    if (!file.existsSync()) {
      stderr.writeln('Missing web build artifact: ${file.path}');
      exitCode = 1;
      return;
    }
  }

  final fingerprint = _fnv1a64(mainBundle.readAsBytesSync());
  final fingerprintedName = 'main.$fingerprint.dart.js';
  mainBundle.copySync('${webDirectory.path}/$fingerprintedName');

  final bootstrapSource = bootstrap.readAsStringSync();
  const mainPath = '"mainJsPath":"main.dart.js"';
  if (!bootstrapSource.contains(mainPath)) {
    stderr.writeln('Could not find main.dart.js in flutter_bootstrap.js.');
    exitCode = 1;
    return;
  }
  bootstrap.writeAsStringSync(
    bootstrapSource.replaceFirst(mainPath, '"mainJsPath":"$fingerprintedName"'),
  );

  final indexSource = index.readAsStringSync();
  const preloadPath = 'href="main.dart.js"';
  const bootstrapPath = "bootstrap.src = 'flutter_bootstrap.js';";
  if (!indexSource.contains(preloadPath) ||
      !indexSource.contains(bootstrapPath)) {
    stderr.writeln('Could not find expected web entry points in index.html.');
    exitCode = 1;
    return;
  }
  index.writeAsStringSync(
    indexSource
        .replaceFirst(preloadPath, 'href="$fingerprintedName"')
        .replaceFirst(
          bootstrapPath,
          "bootstrap.src = 'flutter_bootstrap.js?v=$fingerprint';",
        ),
  );

  stdout.writeln('Fingerprinted web entry point: $fingerprintedName');
}

String _fnv1a64(List<int> bytes) {
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return (hash & 0x7fffffffffffffff).toRadixString(16).padLeft(16, '0');
}
