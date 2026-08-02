import 'dart:convert';
import 'dart:io';

const _retention = Duration(days: 30);

void main(List<String> arguments) {
  final webDirectory = Directory('build/web');
  if (!webDirectory.existsSync()) {
    _fail('Missing web build directory: ${webDirectory.path}');
    return;
  }

  final releaseId = _releaseId(arguments);
  if (!RegExp(r'^[a-f0-9]{7,64}$').hasMatch(releaseId)) {
    _fail('Release ID must be a 7-64 character lowercase Git SHA.');
    return;
  }

  final sourceMain = File('${webDirectory.path}/main.dart.js');
  final bootstrap = File('${webDirectory.path}/flutter_bootstrap.js');
  final index = File('${webDirectory.path}/index.html');
  for (final file in [sourceMain, bootstrap, index]) {
    if (!file.existsSync()) {
      _fail('Missing web build artifact: ${file.path}');
      return;
    }
  }

  const releaseBasePlaceholder = '{{attendus_release_base}}';
  final releaseBase = '/releases/$releaseId/';
  var bootstrapSource = bootstrap.readAsStringSync();
  if (!bootstrapSource.contains(releaseBasePlaceholder)) {
    _fail(
      'Flutter bootstrap does not contain the Attendus release placeholder.',
    );
    return;
  }
  bootstrapSource = bootstrapSource.replaceAll(
    releaseBasePlaceholder,
    releaseBase,
  );
  bootstrap.writeAsStringSync(bootstrapSource);

  var indexSource = index.readAsStringSync();
  const preloadPath = 'href="main.dart.js"';
  const bootstrapPath = "bootstrap.src = 'flutter_bootstrap.js';";
  if (!indexSource.contains(preloadPath) ||
      !indexSource.contains(bootstrapPath)) {
    _fail('Could not find expected web entry points in index.html.');
    return;
  }
  indexSource = indexSource
      .replaceFirst(preloadPath, 'href="${releaseBase}main.dart.js"')
      .replaceFirst(
        bootstrapPath,
        "bootstrap.src = 'flutter_bootstrap.js?v=$releaseId';",
      )
      .replaceFirst(
        'window.attendusBootStartedAt = performance.now();',
        "window.attendusReleaseId = '$releaseId';\n"
            '    window.attendusBootStartedAt = performance.now();',
      );
  index.writeAsStringSync(indexSource);

  final releaseDirectory = Directory(
    '${webDirectory.path}/releases/$releaseId',
  );
  if (releaseDirectory.existsSync()) {
    releaseDirectory.deleteSync(recursive: true);
  }
  releaseDirectory.createSync(recursive: true);

  _copyFile(sourceMain, File('${releaseDirectory.path}/main.dart.js'));
  for (final entity in webDirectory.listSync(followLinks: false)) {
    if (entity is File &&
        RegExp(
          r'main\.dart\.js_\d+\.part\.js$',
        ).hasMatch(_basename(entity.path))) {
      _copyFile(
        entity,
        File('${releaseDirectory.path}/${_basename(entity.path)}'),
      );
    }
  }
  for (final directoryName in ['assets', 'canvaskit']) {
    final source = Directory('${webDirectory.path}/$directoryName');
    if (source.existsSync()) {
      _copyDirectory(
        source,
        Directory('${releaseDirectory.path}/$directoryName'),
      );
    }
  }

  final releaseFiles = _releaseFiles(releaseDirectory, webDirectory);
  if (!releaseFiles.any(
    (entry) => entry['path'] == 'releases/$releaseId/main.dart.js',
  )) {
    _fail('Release package does not contain main.dart.js.');
    return;
  }
  if (!releaseFiles.any(
    (entry) => (entry['path'] as String).endsWith('.part.js'),
  )) {
    _fail('Release package does not contain deferred chunks.');
    return;
  }

  final manifestFile = File('${webDirectory.path}/release-manifest.json');
  final priorReleases = _readPriorReleases(manifestFile);
  final now = DateTime.now().toUtc();
  final cutoff = now.subtract(_retention);
  final retained = <Map<String, dynamic>>[];
  for (final release in priorReleases) {
    final id = release['id']?.toString() ?? '';
    final createdAt = DateTime.tryParse(release['createdAt']?.toString() ?? '');
    if (id == releaseId || createdAt == null || createdAt.isBefore(cutoff)) {
      continue;
    }
    final directory = Directory('${webDirectory.path}/releases/$id');
    if (directory.existsSync()) retained.add(release);
  }
  retained.add({
    'id': releaseId,
    'createdAt': now.toIso8601String(),
    'files': releaseFiles,
  });
  retained.sort(
    (left, right) =>
        left['createdAt'].toString().compareTo(right['createdAt'].toString()),
  );

  final retainedIds = retained.map((release) => release['id']).toSet();
  final releasesRoot = Directory('${webDirectory.path}/releases');
  for (final entity in releasesRoot.listSync(followLinks: false)) {
    if (entity is Directory && !retainedIds.contains(_basename(entity.path))) {
      entity.deleteSync(recursive: true);
    }
  }

  manifestFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'currentRelease': releaseId,
      'generatedAt': now.toIso8601String(),
      'retentionDays': _retention.inDays,
      'releases': retained,
    }),
  );

  sourceMain.deleteSync();
  for (final entity in webDirectory.listSync(followLinks: false)) {
    if (entity is File &&
        (RegExp(
              r'main\.dart\.js_\d+\.part\.js$',
            ).hasMatch(_basename(entity.path)) ||
            RegExp(
              r'main\.[a-f0-9]{7,64}\.dart\.js$',
            ).hasMatch(_basename(entity.path)))) {
      entity.deleteSync();
    }
  }
  for (final directoryName in ['assets', 'canvaskit']) {
    final directory = Directory('${webDirectory.path}/$directoryName');
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }

  stdout.writeln(
    'Packaged web release $releaseId with ${releaseFiles.length} files; '
    '${retained.length} release(s) retained.',
  );
}

String _releaseId(List<String> arguments) {
  final index = arguments.indexOf('--release-id');
  if (index >= 0 && index + 1 < arguments.length) {
    return arguments[index + 1].trim().toLowerCase();
  }
  final result = Process.runSync('git', ['rev-parse', 'HEAD']);
  if (result.exitCode != 0) {
    _fail('Could not resolve the current Git SHA.');
    return '';
  }
  return result.stdout.toString().trim().toLowerCase();
}

List<Map<String, dynamic>> _readPriorReleases(File manifestFile) {
  if (!manifestFile.existsSync()) return [];
  try {
    final data = jsonDecode(manifestFile.readAsStringSync());
    if (data is! Map || data['releases'] is! List) return [];
    return (data['releases'] as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  } catch (_) {
    _fail('Existing release manifest is invalid.');
    return [];
  }
}

List<Map<String, dynamic>> _releaseFiles(
  Directory releaseDirectory,
  Directory webDirectory,
) {
  final files = <Map<String, dynamic>>[];
  for (final entity in releaseDirectory.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    final relative = _relativePath(entity.path, webDirectory.path);
    files.add({'path': relative, 'bytes': entity.lengthSync()});
  }
  files.sort(
    (left, right) =>
        left['path'].toString().compareTo(right['path'].toString()),
  );
  return files;
}

void _copyDirectory(Directory source, Directory destination) {
  destination.createSync(recursive: true);
  for (final entity in source.listSync(followLinks: false)) {
    final name = _basename(entity.path);
    if (entity is Directory) {
      _copyDirectory(entity, Directory('${destination.path}/$name'));
    } else if (entity is File) {
      _copyFile(entity, File('${destination.path}/$name'));
    }
  }
}

void _copyFile(File source, File destination) {
  destination.parent.createSync(recursive: true);
  source.copySync(destination.path);
}

String _relativePath(String path, String root) {
  final normalizedPath = path.replaceAll('\\', '/');
  final normalizedRoot = root.replaceAll('\\', '/');
  return normalizedPath.substring(normalizedRoot.length + 1);
}

String _basename(String path) => path.replaceAll('\\', '/').split('/').last;

void _fail(String message) {
  stderr.writeln(message);
  exitCode = 1;
}
