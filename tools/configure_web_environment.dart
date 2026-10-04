import 'dart:io';

const _environments = <String, Map<String, String>>{
  'production': {
    'apiKey': 'AIzaSyA-PFyqhP5aEVE6XwGku3jMe91G3efMaVw',
    'authDomain': 'orgami-66nxok.firebaseapp.com',
    'projectId': 'orgami-66nxok',
    'storageBucket': 'orgami-66nxok.appspot.com',
    'messagingSenderId': '951311475019',
    'appId': '1:951311475019:web:65b1de24d2f3a8d289c8ce',
    'primaryOrigin': 'https://attendus.app',
    'secondaryOrigin': 'https://www.attendus.app',
    'firebaseHostingOrigin': 'https://orgami-66nxok.web.app',
    'firebaseAppOrigin': 'https://orgami-66nxok.firebaseapp.com',
    'workerBridgeEnabled': 'true',
  },
  'staging': {
    'apiKey': 'AIzaSyBCFt_7BJNVVzgAZ2Fa7S_5UMGYIVDQ-dg',
    'authDomain': 'attendus-staging.firebaseapp.com',
    'projectId': 'attendus-staging',
    'storageBucket': 'attendus-staging.firebasestorage.app',
    'messagingSenderId': '925344893088',
    'appId': '1:925344893088:web:3be71e809ba516e1d021c5',
    'primaryOrigin': 'https://attendus-staging.web.app',
    'secondaryOrigin': 'https://attendus-staging.firebaseapp.com',
    'firebaseHostingOrigin': 'https://attendus-staging.web.app',
    'firebaseAppOrigin': 'https://attendus-staging.firebaseapp.com',
    'workerBridgeEnabled': 'false',
  },
};

void main(List<String> arguments) {
  final environment = _argument(arguments, '--environment');
  final values = _environments[environment];
  if (values == null) {
    _fail('Use --environment production or --environment staging.');
  }

  final files = <File>[
    File('build/web/index.html'),
    File('build/web/firebase-messaging-sw.js'),
  ];
  for (final file in files) {
    if (!file.existsSync()) {
      _fail('Missing web build artifact: ${file.path}');
    }
  }

  _replaceAll(files[0], {
    '__ATTENDUS_PRIMARY_ORIGIN__': values['primaryOrigin']!,
    '__ATTENDUS_SECONDARY_ORIGIN__': values['secondaryOrigin']!,
    '__ATTENDUS_FIREBASE_HOSTING_ORIGIN__': values['firebaseHostingOrigin']!,
    '__ATTENDUS_FIREBASE_APP_ORIGIN__': values['firebaseAppOrigin']!,
    '__ATTENDUS_WORKER_BRIDGE_ENABLED__': values['workerBridgeEnabled']!,
  });
  _replaceAll(files[1], {
    '__ATTENDUS_FIREBASE_API_KEY__': values['apiKey']!,
    '__ATTENDUS_FIREBASE_AUTH_DOMAIN__': values['authDomain']!,
    '__ATTENDUS_FIREBASE_PROJECT_ID__': values['projectId']!,
    '__ATTENDUS_FIREBASE_STORAGE_BUCKET__': values['storageBucket']!,
    '__ATTENDUS_FIREBASE_MESSAGING_SENDER_ID__': values['messagingSenderId']!,
    '__ATTENDUS_FIREBASE_APP_ID__': values['appId']!,
  });

  for (final file in files) {
    final source = file.readAsStringSync();
    if (source.contains(RegExp(r'__ATTENDUS_[A-Z0-9_]+__'))) {
      _fail('Unresolved Attendus placeholder in ${file.path}.');
    }
  }

  _verifyFirebaseIsolation(environment, values);

  stdout.writeln('Configured Flutter web artifacts for $environment.');
}

void _verifyFirebaseIsolation(String environment, Map<String, String> values) {
  final forbidden = environment == 'staging'
      ? const [
          'orgami-66nxok',
          '951311475019',
          'AIzaSyA-PFyqhP5aEVE6XwGku3jMe91G3efMaVw',
        ]
      : const [
          'attendus-staging',
          '925344893088',
          'AIzaSyBCFt_7BJNVVzgAZ2Fa7S_5UMGYIVDQ-dg',
        ];
  final artifacts = Directory('build/web')
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => const ['.html', '.js', '.json'].any(file.path.endsWith));
  var selectedProjectFound = false;
  for (final file in artifacts) {
    final source = file.readAsStringSync();
    if (source.contains(values['projectId']!)) selectedProjectFound = true;
    for (final identifier in forbidden) {
      if (source.contains(identifier)) {
        _fail('Firebase isolation failed: ${file.path} contains $identifier.');
      }
    }
  }
  if (!selectedProjectFound) {
    _fail('The $environment Firebase project is absent from the web build.');
  }
}

String _argument(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index < 0 || index + 1 >= arguments.length) return '';
  return arguments[index + 1].trim().toLowerCase();
}

void _replaceAll(File file, Map<String, String> replacements) {
  var source = file.readAsStringSync();
  for (final entry in replacements.entries) {
    if (!source.contains(entry.key)) {
      if (!source.contains(entry.value)) {
        _fail('Missing ${entry.key} in ${file.path}.');
      }
      continue;
    }
    source = source.replaceAll(entry.key, entry.value);
  }
  file.writeAsStringSync(source);
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
