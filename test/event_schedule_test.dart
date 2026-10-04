import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendus/models/event_schedule.dart';

void main() {
  test(
    'exact duration crosses daylight saving without changing the instant',
    () {
      final schedule = EventSchedule(
        DateTime.parse('2026-03-08T06:30:00Z'),
        90,
        'America/New_York',
      );
      expect(schedule.eventStart.hour, 1);
      expect(schedule.end, DateTime.parse('2026-03-08T08:00:00Z'));
      expect(schedule.timeLabel, contains('4:00 AM'));
      expect(schedule.timeLabel, contains('EDT'));
    },
  );
  test(
    'calendar keeps UID and revisions and folds unicode at byte boundaries',
    () {
      final schedule = EventSchedule(
        DateTime.parse('2026-01-01T23:30:00Z'),
        90,
        'UTC',
      );
      final ics = schedule.calendar(
        eventId: 'stable',
        title: '🎉' * 90,
        venue: 'A,B;C',
        url: 'https://attendus.app/event/stable',
        revision: 7,
        cancelled: true,
      );
      expect(ics, contains('UID:stable@attendus.app'));
      expect(ics, contains('SEQUENCE:7'));
      expect(ics, contains('DTEND:20260102T010000Z'));
      expect(ics, contains('STATUS:CANCELLED'));
      for (final line in ics.split('\r\n')) {
        expect(utf8.encode(line).length, lessThanOrEqualTo(75));
      }
    },
  );
  test('unknown duration does not produce a fabricated calendar end', () {
    final schedule = EventSchedule(DateTime.utc(2026), null, 'UTC');
    expect(schedule.end, isNull);
    expect(
      () => schedule.calendar(eventId: 'e', title: 'Event', venue: '', url: ''),
      throwsStateError,
    );
  });
}
