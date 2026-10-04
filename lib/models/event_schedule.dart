import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as zones;
import 'package:timezone/timezone.dart' as tz;

class EventSchedule {
  EventSchedule(this.start, this.durationMinutes, this.zone);
  final DateTime start;
  final int? durationMinutes;
  final String zone;
  static bool _initialized = false;

  tz.Location get location {
    if (!_initialized) {
      zones.initializeTimeZones();
      _initialized = true;
    }
    try {
      return tz.getLocation(zone);
    } catch (_) {
      return tz.UTC;
    }
  }

  DateTime? get end => durationMinutes == null
      ? null
      : start.add(Duration(minutes: durationMinutes!));
  tz.TZDateTime get eventStart => tz.TZDateTime.from(start, location);
  String get dateLabel => DateFormat('EEEE, MMMM d, yyyy').format(eventStart);
  String get timeLabel {
    final first = DateFormat('h:mm a').format(eventStart);
    final finish = end;
    if (finish == null) {
      return '$first ${eventStart.timeZoneName} · End time unconfirmed';
    }
    final last = tz.TZDateTime.from(finish, location);
    final pattern = last.day == eventStart.day ? 'h:mm a' : 'MMM d, h:mm a';
    final startZone = eventStart.timeZoneName == last.timeZoneName
        ? ''
        : ' ${eventStart.timeZoneName}';
    return '$first$startZone – ${DateFormat(pattern).format(last)} ${last.timeZoneName}';
  }

  String get cardLabel =>
      '${DateFormat('EEE, MMM d · h:mm a').format(eventStart)} ${eventStart.timeZoneName}';
  String get localLabel =>
      '${DateFormat('MMM d, h:mm a').format(start.toLocal())} ${start.toLocal().timeZoneName}';

  static String compact(DateTime value) =>
      DateFormat("yyyyMMdd'T'HHmmss'Z'").format(value.toUtc());
  static String _escape(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('\r', '')
      .replaceAll('\n', r'\n')
      .replaceAll(',', r'\,')
      .replaceAll(';', r'\;');
  String calendar({
    required String eventId,
    required String title,
    required String venue,
    required String url,
    int revision = 0,
    bool cancelled = false,
  }) {
    if (end == null) {
      throw StateError('The organizer needs to confirm the end time.');
    }
    return [
          'BEGIN:VCALENDAR',
          'VERSION:2.0',
          'PRODID:-//Attendus//Events//EN',
          'METHOD:${cancelled ? 'CANCEL' : 'PUBLISH'}',
          'BEGIN:VEVENT',
          'UID:${_escape(eventId)}@attendus.app',
          'SEQUENCE:$revision',
          if (cancelled) 'STATUS:CANCELLED',
          'DTSTAMP:${compact(DateTime.now())}',
          'DTSTART:${compact(start)}',
          'DTEND:${compact(end!)}',
          'SUMMARY:${_escape(title)}',
          'LOCATION:${_escape(venue)}',
          'URL:${_escape(url)}',
          'END:VEVENT',
          'END:VCALENDAR',
          '',
        ]
        .map((line) {
          final output = StringBuffer();
          var width = 0;
          for (final rune in line.runes) {
            final character = String.fromCharCode(rune);
            final size = utf8.encode(character).length;
            if (width + size > 75) {
              output.write('\r\n ');
              width = 1;
            }
            output.write(character);
            width += size;
          }
          return output.toString();
        })
        .join('\r\n');
  }
}
