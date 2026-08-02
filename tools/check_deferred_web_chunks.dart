import 'dart:io';

Future<void> main(List<String> arguments) async {
  final webDirectory = Directory('build/web');
  final bootstrap = File('${webDirectory.path}/flutter_bootstrap.js');
  if (!bootstrap.existsSync()) {
    _fail('Missing web build artifact: ${bootstrap.path}');
    return;
  }

  final bootstrapSource = bootstrap.readAsStringSync();
  final mainMatch = RegExp(
    r'"mainJsPath":"([^"]+\.dart\.js)"',
  ).firstMatch(bootstrapSource);
  if (mainMatch == null) {
    _fail('Could not find the generated mainJsPath in flutter_bootstrap.js.');
    return;
  }

  final mainName = mainMatch.group(1)!;
  final mainBundle = File('${webDirectory.path}/$mainName');
  if (!mainBundle.existsSync()) {
    _fail('Missing generated main bundle: ${mainBundle.path}');
    return;
  }

  final mainSource = mainBundle.readAsStringSync();
  final chunkNames =
      RegExp(r'"(main\.dart\.js_\d+\.part\.js)"')
          .allMatches(mainSource)
          .map((match) => match.group(1)!)
          .toSet()
          .toList()
        ..sort();
  if (chunkNames.isEmpty) {
    _fail('The generated main bundle did not declare deferred chunks.');
    return;
  }

  final missing = chunkNames
      .where((name) => !File('${webDirectory.path}/$name').existsSync())
      .toList();
  if (missing.isNotEmpty) {
    _fail('Missing deferred web chunks: ${missing.join(', ')}');
    return;
  }

  stdout.writeln(
    'Deferred web chunks: ${chunkNames.length} local files verified.',
  );

  if (arguments.isEmpty) return;
  final baseUri = Uri.parse(arguments.first);
  final client = HttpClient();
  try {
    for (final chunkName in chunkNames) {
      final uri = baseUri.resolve(
        '$chunkName?attendus_chunk_check=${DateTime.now().millisecondsSinceEpoch}',
      );
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close();
      final contentType = response.headers.contentType?.mimeType ?? '';
      await response.drain<void>();
      if (response.statusCode != HttpStatus.ok ||
          !contentType.contains('javascript')) {
        _fail(
          'Invalid deployed deferred chunk $uri: '
          'HTTP ${response.statusCode}, Content-Type $contentType',
        );
        return;
      }
    }
  } finally {
    client.close(force: true);
  }

  stdout.writeln(
    'Deferred web chunks: ${chunkNames.length} production files verified at '
    '$baseUri.',
  );
}

void _fail(String message) {
  stderr.writeln(message);
  exitCode = 1;
}
