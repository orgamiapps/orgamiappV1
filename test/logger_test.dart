import 'package:attendus/Utils/logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => Logger.installErrorTelemetrySink(null));

  test('sanitizes common credentials and personal identifiers', () {
    final safe = Logger.sanitize(
      'user@example.com token=abc123 Authorization: Bearer.secret '
      'https://example.test/?key=maps-key&code=oauth-code',
    );

    expect(safe, isNot(contains('user@example.com')));
    expect(safe, isNot(contains('abc123')));
    expect(safe, isNot(contains('Bearer.secret')));
    expect(safe, isNot(contains('maps-key')));
    expect(safe, isNot(contains('oauth-code')));
  });

  test('error telemetry receives a release-tagged scrubbed event', () {
    Map<String, Object?>? captured;
    Logger.installErrorTelemetrySink((event) => captured = event);

    Logger.error('Could not load user@example.com', 'token=secret-value');

    expect(captured, isNotNull);
    expect(captured!['releaseId'], Logger.releaseId);
    expect(captured!['message'], isNot(contains('user@example.com')));
    expect(captured!['error'], isNot(contains('secret-value')));
  });
}
