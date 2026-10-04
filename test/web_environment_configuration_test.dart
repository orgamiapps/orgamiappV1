import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _firebaseIdentifiers = <String, List<String>>{
  'production': [
    'orgami-66nxok',
    '951311475019',
    'AIzaSyA-PFyqhP5aEVE6XwGku3jMe91G3efMaVw',
  ],
  'staging': [
    'attendus-staging',
    '925344893088',
    'AIzaSyBCFt_7BJNVVzgAZ2Fa7S_5UMGYIVDQ-dg',
  ],
};

void main() {
  final repository = Directory.current.absolute;
  final tool = File(
    '${repository.path}/tools/configure_web_environment.dart',
  ).absolute.path;

  Future<Directory> fixture() async {
    final systemTemp = await Directory.systemTemp.resolveSymbolicLinks();
    final directory = await Directory.systemTemp.createTemp(
      'attendus web environment ',
    );
    final ownedPath = await directory.resolveSymbolicLinks();
    String normalized(String path) =>
        Platform.isWindows ? path.toLowerCase() : path;
    bool insideSystemTemp(String path) => normalized(
      path,
    ).startsWith('${normalized(systemTemp)}${Platform.pathSeparator}');
    if (!insideSystemTemp(ownedPath)) {
      throw StateError(
        'CLI fixture escaped the resolved system temp directory.',
      );
    }
    addTearDown(() async {
      final type = await FileSystemEntity.type(
        directory.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.notFound) return;
      final resolved = await directory.resolveSymbolicLinks();
      if (type != FileSystemEntityType.directory ||
          normalized(resolved) != normalized(ownedPath) ||
          !insideSystemTemp(resolved) ||
          normalized(await Directory.systemTemp.resolveSymbolicLinks()) !=
              normalized(systemTemp)) {
        throw StateError('Refusing cleanup of a changed CLI fixture path.');
      }
      await Directory(resolved).delete(recursive: true);
    });
    final web = await Directory(
      '${directory.path}/build/web',
    ).create(recursive: true);
    for (final name in ['index.html', 'firebase-messaging-sw.js']) {
      await File('${repository.path}/web/$name').copy('${web.path}/$name');
    }
    await File('${web.path}/main.dart.js').writeAsString('void 0;\n');
    return directory;
  }

  Future<ProcessResult> configure(
    Directory directory,
    String environment,
  ) async {
    // Real argv and a working directory containing spaces exercise Windows
    // quoting too. CI's Flutter action supplies the same Dart CLI on PATH.
    final process = await Process.start(
      'dart',
      [tool, '--environment', environment],
      workingDirectory: directory.path,
      runInShell: Platform.isWindows,
    );
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        process.kill();
        throw StateError('Web environment configuration CLI timed out.');
      },
    );
    return ProcessResult(process.pid, exitCode, await output, await errors);
  }

  for (final environment in _firebaseIdentifiers.keys) {
    final opposite = environment == 'production' ? 'staging' : 'production';
    test('$environment configures the real web templates', () async {
      final directory = await fixture();
      final result = await configure(directory, environment);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('artifacts for $environment'));
      final worker = await File(
        '${directory.path}/build/web/firebase-messaging-sw.js',
      ).readAsString();
      final index = await File(
        '${directory.path}/build/web/index.html',
      ).readAsString();
      for (final identifier in _firebaseIdentifiers[environment]!) {
        expect(worker, contains(identifier));
      }
      for (final identifier in _firebaseIdentifiers[opposite]!) {
        expect(worker, isNot(contains(identifier)));
        expect(index, isNot(contains(identifier)));
      }
      expect(worker, isNot(contains('__ATTENDUS_')));
      expect(index, isNot(contains('__ATTENDUS_')));
    });

    for (final artifact in [
      'main.dart.js',
      'assets/nested/chunk.js',
      'assets/nested/config.json',
      'assets/nested/page.html',
    ]) {
      final oppositeIdentifiers = _firebaseIdentifiers[opposite]!;
      for (var identifierIndex = 0; identifierIndex < 3; identifierIndex++) {
        final identifier = oppositeIdentifiers[identifierIndex];
        final kind = ['project', 'sender', 'key'][identifierIndex];
        test('$environment rejects $opposite $kind in $artifact', () async {
          final directory = await fixture();
          final file = File('${directory.path}/build/web/$artifact');
          await file.parent.create(recursive: true);
          final value = jsonEncode({'firebaseIdentifier': identifier});
          await file.writeAsString(
            artifact.endsWith('.html') ? '<script>$value</script>' : value,
          );
          final result = await configure(directory, environment);
          expect(
            result.exitCode,
            1,
            reason: '${result.stdout}\n${result.stderr}',
          );
          expect(result.stderr, contains('Firebase isolation failed:'));
          expect(result.stderr, contains('contains $identifier.'));
          expect(result.stdout, isNot(contains('Configured Flutter')));
        });
      }
    }

    for (final template in ['index.html', 'firebase-messaging-sw.js']) {
      test('$environment rejects unresolved markers in $template', () async {
        final directory = await fixture();
        final file = File('${directory.path}/build/web/$template');
        await file.writeAsString(
          '\n__ATTENDUS_UNRECOGNIZED_CONFIGURATION__\n',
          mode: FileMode.append,
        );
        final result = await configure(directory, environment);
        expect(
          result.exitCode,
          1,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stderr, contains('Unresolved Attendus placeholder'));
        expect(result.stdout, isNot(contains('Configured Flutter')));
      });
    }
  }
}
