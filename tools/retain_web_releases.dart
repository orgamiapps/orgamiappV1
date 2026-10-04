import 'dart:convert';
import 'dart:io';

const _downloadBatchSize = 6;
const _maxDownloadAttempts = 4;

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tools/retain_web_releases.dart BASE_URL');
    exitCode = 64;
    return;
  }

  final baseUri = Uri.parse(arguments.single);
  final webDirectory = Directory('build/web');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final manifestUri = baseUri.resolve(
      'release-manifest.json?retain=${DateTime.now().millisecondsSinceEpoch}',
    );
    final manifestDownload = await _downloadWithRetry(
      client,
      manifestUri,
      allowNotFound: true,
    );
    final bytes = manifestDownload.bytes;
    if (manifestDownload.statusCode == HttpStatus.notFound) {
      stdout.writeln('No prior web release manifest was found.');
      return;
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

    for (var offset = 0; offset < files.length; offset += _downloadBatchSize) {
      final batch = files.skip(offset).take(_downloadBatchSize);
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
  if (expectedBytes is! int || expectedBytes < 0) {
    throw FormatException('Invalid byte length for retained release: $path');
  }
  final download = await _downloadWithRetry(
    client,
    baseUri.resolve(path),
    expectedBytes: expectedBytes,
  );
  final output = File('${webDirectory.path}/$path');
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(download.bytes);
}

Future<_Download> _downloadWithRetry(
  HttpClient client,
  Uri uri, {
  int? expectedBytes,
  bool allowNotFound = false,
}) async {
  Object? lastError;
  for (var attempt = 1; attempt <= _maxDownloadAttempts; attempt += 1) {
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final bytes = await response
          .fold<List<int>>(<int>[], (buffer, chunk) => buffer..addAll(chunk))
          .timeout(const Duration(seconds: 60));
      final validNotFound =
          allowNotFound && response.statusCode == HttpStatus.notFound;
      final validSuccess =
          response.statusCode == HttpStatus.ok &&
          (expectedBytes == null || bytes.length == expectedBytes);
      if (validNotFound || validSuccess) {
        return _Download(response.statusCode, bytes);
      }
      lastError = HttpException(
        'HTTP ${response.statusCode}, ${bytes.length}/${expectedBytes ?? "?"} '
        'bytes from $uri',
      );
    } catch (error) {
      lastError = error;
    }

    if (attempt < _maxDownloadAttempts) {
      await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
    }
  }
  throw HttpException(
    'Download validation failed after $_maxDownloadAttempts attempts for '
    '$uri: $lastError',
  );
}

final class _Download {
  const _Download(this.statusCode, this.bytes);

  final int statusCode;
  final List<int> bytes;
}
