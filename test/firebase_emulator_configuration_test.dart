import 'package:attendus/Utils/firebase_emulator_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'emulator routing rejects cloud projects, remote hosts and release mode',
    () {
      for (final project in ['orgami-66nxok', 'attendus-staging', '']) {
        expect(
          () => FirebaseEmulatorConfig.validate(
            projectId: project,
            hostname: '127.0.0.1',
            debug: true,
          ),
          throwsStateError,
        );
      }
      expect(
        () => FirebaseEmulatorConfig.validate(
          projectId: 'demo-attendus-admin',
          hostname: 'example.com',
          debug: true,
        ),
        throwsStateError,
      );
      expect(
        () => FirebaseEmulatorConfig.validate(
          projectId: 'demo-attendus-admin',
          hostname: '127.0.0.1',
          debug: false,
        ),
        throwsStateError,
      );
    },
  );
  test('explicit local hosts work for desktop and Android emulator', () {
    for (final host in ['localhost', '127.0.0.1', '10.0.2.2']) {
      FirebaseEmulatorConfig.validate(
        projectId: 'demo-attendus-admin',
        hostname: host,
        debug: true,
      );
    }
  });
}
