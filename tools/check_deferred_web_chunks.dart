import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final webDirectory = Directory('build/web');
  final manifestFile = File('${webDirectory.path}/release-manifest.json');
  if (!manifestFile.existsSync()) {
    _fail('Missing web release manifest: ${manifestFile.path}');
    return;
  }

  final manifest = _readManifest(manifestFile);
  if (manifest == null) return;
  final currentRelease = manifest['currentRelease']?.toString() ?? '';
  final releases = (manifest['releases'] as List? ?? const [])
      .whereType<Map>()
      .map((release) => Map<String, dynamic>.from(release))
      .toList();
  final current = releases.cast<Map<String, dynamic>?>().firstWhere(
    (release) => release?['id'] == currentRelease,
    orElse: () => null,
  );
  if (current == null) {
    _fail('Current release $currentRelease is absent from its manifest.');
    return;
  }

  var totalFiles = 0;
  for (final release in releases) {
    final files = (release['files'] as List? ?? const []).whereType<Map>();
    for (final entry in files) {
      final path = entry['path']?.toString() ?? '';
      final expectedBytes = entry['bytes'];
      final file = File('${webDirectory.path}/$path');
      if (!file.existsSync() ||
          expectedBytes is! int ||
          file.lengthSync() != expectedBytes) {
        _fail('Invalid local release asset: $path');
        return;
      }
      totalFiles += 1;
    }
  }

  final mainPath = 'releases/$currentRelease/main.dart.js';
  final mainBundle = File('${webDirectory.path}/$mainPath');
  if (!mainBundle.existsSync()) {
    _fail('Missing current main bundle: $mainPath');
    return;
  }
  final chunkNames =
      RegExp(r'"(main\.dart\.js_\d+\.part\.js)"')
          .allMatches(mainBundle.readAsStringSync())
          .map((match) => match.group(1)!)
          .toSet()
          .toList()
        ..sort();
  if (chunkNames.isEmpty) {
    _fail('The current main bundle did not declare deferred chunks.');
    return;
  }
  for (final chunkName in chunkNames) {
    final chunk = File(
      '${webDirectory.path}/releases/$currentRelease/$chunkName',
    );
    if (!chunk.existsSync()) {
      _fail('Missing deferred web chunk: ${chunk.path}');
      return;
    }
  }
  stdout.writeln(
    'Web releases: ${releases.length} release(s), $totalFiles local files, '
    '${chunkNames.length} current deferred chunks verified.',
  );

  if (arguments.isEmpty) return;
  final baseUri = Uri.parse(arguments.first);
  final client = HttpClient();
  try {
    for (final rootPath in [
      '',
      'index.html',
      'flutter_bootstrap.js',
      'release-manifest.json',
    ]) {
      final request = await client.getUrl(baseUri.resolve(rootPath));
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode != HttpStatus.ok) {
        _fail(
          'Invalid web bootstrap ${baseUri.resolve(rootPath)}: '
          'HTTP ${response.statusCode}',
        );
        return;
      }
    }

    final allFiles = releases
        .expand(
          (release) => (release['files'] as List? ?? const []).whereType<Map>(),
        )
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
    for (var offset = 0; offset < allFiles.length; offset += 12) {
      final batch = allFiles.skip(offset).take(12);
      final results = await Future.wait(
        batch.map((entry) => _checkRemoteAsset(client, baseUri, entry)),
      );
      String? failure;
      for (final result in results) {
        if (result != null) {
          failure = result;
          break;
        }
      }
      if (failure != null) {
        _fail(failure);
        return;
      }
    }
  } finally {
    client.close(force: true);
  }
  stdout.writeln(
    'Web releases: $totalFiles immutable production assets verified at '
    '$baseUri.',
  );
}

Map<String, dynamic>? _readManifest(File file) {
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map || decoded['releases'] is! List) {
      throw const FormatException('Missing releases list.');
    }
    return Map<String, dynamic>.from(decoded);
  } catch (error) {
    _fail('Invalid web release manifest: $error');
    return null;
  }
}

Future<String?> _checkRemoteAsset(
  HttpClient client,
  Uri baseUri,
  Map<String, dynamic> entry,
) async {
  final path = entry['path']?.toString() ?? '';
  final expectedBytes = entry['bytes'];
  final uri = baseUri.resolve(path);
  final request = await client.openUrl('HEAD', uri);
  request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
  final response = await request.close();
  await response.drain<void>();
  final cacheControl =
      response.headers.value(HttpHeaders.cacheControlHeader) ?? '';
  final contentType = response.headers.contentType?.mimeType ?? '';
  if (response.statusCode != HttpStatus.ok ||
      expectedBytes is! int ||
      response.contentLength != expectedBytes) {
    return 'Invalid deployed release asset $uri: HTTP ${response.statusCode}, '
        '${response.contentLength}/$expectedBytes bytes';
  }
  if (!cacheControl.contains('immutable') ||
      !cacheControl.contains('max-age=31536000')) {
    return 'Release asset is not immutable: $uri ($cacheControl)';
  }
  if (path.endsWith('.js') && !contentType.contains('javascript')) {
    return 'Release script has invalid MIME type: $uri ($contentType)';
  }
  return null;
}

void _fail(String message) {
  stderr.writeln(message);
  exitCode = 1;
}
