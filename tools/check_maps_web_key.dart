import 'dart:io';

const _clientConfigurationFiles = <String>[
  'android/app/google-services.json',
  'android/app/google-services.json.backup',
  'ios/Runner/GoogleService-Info.plist',
  'lib/Utils/app_constants.dart',
  'lib/firebase_options.dart',
  'web/firebase-messaging-sw.js',
];

void main() {
  final key = Platform.environment['GOOGLE_MAPS_WEB_API_KEY']?.trim() ?? '';
  if (key.isEmpty) {
    stderr.writeln(
      'GOOGLE_MAPS_WEB_API_KEY is required for the web release build.',
    );
    exitCode = 1;
    return;
  }

  if (!key.startsWith('AIza') || key.length < 30) {
    stderr.writeln('GOOGLE_MAPS_WEB_API_KEY is not a valid Google API key.');
    exitCode = 1;
    return;
  }

  final reusedFiles = <String>[];
  for (final path in _clientConfigurationFiles) {
    final file = File(path);
    if (file.existsSync() && file.readAsStringSync().contains(key)) {
      reusedFiles.add(path);
    }
  }

  if (reusedFiles.isNotEmpty) {
    stderr.writeln(
      'GOOGLE_MAPS_WEB_API_KEY matches an existing Firebase or platform '
      'client key. Use the dedicated HTTP-referrer-restricted Maps web key.',
    );
    stderr.writeln('Conflicting configuration: ${reusedFiles.join(', ')}');
    exitCode = 1;
  }
}
