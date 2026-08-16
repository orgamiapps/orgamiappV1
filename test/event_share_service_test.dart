import 'package:attendus/Services/event_share_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds and parses the canonical event URL', () {
    final uri = EventShareService.eventUri('event-123');

    expect(uri.toString(), 'https://attendus.app/event/event-123');
    expect(EventShareService.eventIdFromUri(uri), 'event-123');
    expect(
      EventShareService.eventIdFromUri(
        Uri.parse('/app/event/event-123?action=ticket'),
      ),
      'event-123',
    );
  });

  test('rejects unrelated and malformed URLs', () {
    expect(
      EventShareService.eventIdFromUri(
        Uri.parse('https://attendus.app/profile/user-1'),
      ),
      isNull,
    );
    expect(
      EventShareService.eventIdFromUri(
        Uri.parse('https://attendus.app/event/one/extra'),
      ),
      isNull,
    );
    expect(
      EventShareService.eventIdFromUri(
        Uri.parse('https://example.com/event/event-123'),
      ),
      isNull,
    );
  });
}
