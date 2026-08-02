import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tools/retain_web_releases.dart BASE_URL');
    exitCode = 64;
    return;
  }

  final baseUri = Uri.parse(arguments.single);
  final webDirectory = Directory('build/web');
  final client = HttpClient();
  try {
    final manifestUri = baseUri.resolve(
      'release-manifest.json?retain=${DateTime.now().millisecondsSinceEpoch}',
    );
    final request = await client.getUrl(manifestUri);
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    if (response.statusCode == HttpStatus.notFound) {
      stdout.writeln('No prior web release manifest was found.');
      return;
    }
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Could not download $manifestUri: HTTP ${response.statusCode}',
      );
    }

    final bodyText = utf8.decode(bytes);
    if (bodyText.trimLeft().startsWith('<!DOCTYPE html>')) {
      stdout.writeln('No prior web release manifest was found.');
      return;
    }

    final decoded = jsonDecode(bodyText);
    if (decoded is! Map || decoded['releases'] is! List) {
      throw const FormatException('Invalid web release manifest.');
    }
    final manifest = Map<String, dynamic>.from(decoded);
    final files = <Map<String, dynamic>>[];
    for (final release in manifest['releases'] as List) {
      if (release is! Map || release['files'] is! List) continue;
      for (final file in release['files'] as List) {
        if (file is Map) files.add(Map<String, dynamic>.from(file));
      }
    }

    for (var offset = 0; offset < files.length; offset += 12) {
      final batch = files.skip(offset).take(12);
      await Future.wait(
        batch.map(
          (file) => _downloadReleaseFile(client, baseUri, webDirectory, file),
        ),
      );
    }
    File('${webDirectory.path}/release-manifest.json').writeAsBytesSync(bytes);
    stdout.writeln(
      'Retained ${manifest['releases'].length} prior web release(s) '
      'with ${files.length} files.',
    );
  } finally {
    client.close(force: true);
  }
}

Future<void> _downloadReleaseFile(
  HttpClient client,
  Uri baseUri,
  Directory webDirectory,
  Map<String, dynamic> entry,
) async {
  final path = entry['path']?.toString() ?? '';
  final expectedBytes = entry['bytes'];
  if (!RegExp(r'^releases/[a-f0-9]{7,64}/[A-Za-z0-9._/-]+$').hasMatch(path) ||
      path.contains('..')) {
    throw FormatException('Unsafe release path in manifest: $path');
  }
  final request = await client.getUrl(baseUri.resolve(path));
  request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
  final response = await request.close();
  final bytes = await response.fold<List<int>>(
    <int>[],
    (buffer, chunk) => buffer..addAll(chunk),
  );
  if (response.statusCode != HttpStatus.ok ||
      expectedBytes is! int ||
      bytes.length != expectedBytes) {
    throw HttpException(
      'Retained release validation failed for $path: '
      'HTTP ${response.statusCode}, ${bytes.length}/$expectedBytes bytes',
    );
  }
  final output = File('${webDirectory.path}/$path');
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(bytes);
}
