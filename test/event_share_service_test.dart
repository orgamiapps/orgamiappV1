import 'package:attendus/Services/event_share_service.dart';
import 'package:attendus/Utils/app_constants.dart';
import 'package:attendus/models/event_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'calendar export keeps exact UTC instants and same-environment event URL',
    () {
      final event = EventModel(
        id: 'stage-calendar',
        groupName: '',
        title: 'Fixture event',
        description: '',
        location: 'Fixture venue',
        imageUrl: '',
        customerUid: 'fixture-owner',
        status: 'active',
        selectedDateTime: DateTime.parse('2026-11-01T01:30:00-04:00'),
        eventGenerateTime: DateTime.utc(2026),
        private: false,
        getLocation: false,
        radius: 100,
        latitude: 0,
        longitude: 0,
        eventDurationMinutes: 60,
        eventTimeZone: 'America/New_York',
      );
      final calendar = EventShareService.calendarText(
        event,
        links: PublicLinkConfiguration.forEnvironment('staging'),
      ).replaceAll('\r\n ', '');
      expect(calendar, contains('DTSTART:20261101T053000Z'));
      expect(calendar, contains('DTEND:20261101T063000Z'));
      expect(
        calendar,
        contains('URL:https://attendus-staging.web.app/event/stage-calendar'),
      );
      expect(calendar, isNot(contains('URL:https://attendus.app/')));
    },
  );
  test('builds and parses the canonical event URL', () {
    final uri = EventShareService.eventUri('event-123');

    expect(uri.toString(), '${AppConstants.publicWebDomain}/event/event-123');
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
