import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Explicit local integration-test routing; never selected by platform detection.
abstract final class FirebaseEmulatorConfig {
  static const host = String.fromEnvironment(
    'ATTENDUS_EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );

  static void validate({
    required String projectId,
    required String hostname,
    required bool debug,
  }) {
    if (!debug ||
        projectId != 'demo-attendus-admin' ||
        !{'127.0.0.1', 'localhost', '10.0.2.2'}.contains(hostname)) {
      throw StateError(
        'Integration tests require debug mode and local demo emulators.',
      );
    }
  }

  static Future<void> connect(String projectId) async {
    validate(projectId: projectId, hostname: host, debug: kDebugMode);
    await FirebaseAuth.instance.useAuthEmulator(host, 9190);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8180);
    FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).useFunctionsEmulator(host, 5101);
    await FirebaseStorage.instance.useStorageEmulator(host, 9299);
  }
}
