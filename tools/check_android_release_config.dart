import 'dart:io';

void main() {
  final gradleFile = File('android/app/build.gradle');
  if (!gradleFile.existsSync()) {
    stderr.writeln('Android app Gradle configuration was not found.');
    exitCode = 1;
    return;
  }

  final source = gradleFile.readAsStringSync();
  final failures = <String>[];
  if (source.contains('signingConfig = signingConfigs.debug')) {
    failures.add('release builds still use the Android debug certificate');
  }
  if (!source.contains('signingConfig = signingConfigs.release')) {
    failures.add('release builds do not select the release signing config');
  }
  if (!source.contains("abiFilters 'arm64-v8a', 'armeabi-v7a'")) {
    failures.add('the supported release ABIs are not explicitly declared');
  }
  if (!source.contains('if (isReleaseBuild && !hasReleaseSigning)')) {
    failures.add('release builds do not fail closed when signing is absent');
  }

  if (failures.isNotEmpty) {
    stderr.writeln('Android release configuration is unsafe:');
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Android releases require explicit non-debug signing and support arm64-v8a/armeabi-v7a.',
  );
}
