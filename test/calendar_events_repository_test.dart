import 'dart:async';
import 'package:attendus/Services/calendar_events_repository.dart';
import 'package:attendus/models/event_model.dart';
import 'package:flutter_test/flutter_test.dart';

EventModel event(String id) => EventModel(
  id: id,
  groupName: '',
  title: id,
  description: '',
  location: '',
  customerUid: 'a',
  imageUrl: '',
  selectedDateTime: DateTime(2027),
  eventGenerateTime: DateTime(2027),
  status: 'scheduled',
  private: false,
  getLocation: false,
  radius: 0,
  latitude: 0,
  longitude: 0,
);
void main() {
  test(
    'calendar uses only rule-compatible queries and deduplicates public owned events',
    () async {
      final queries = <CalendarEventQuery>[];
      final repository = CalendarEventsRepository(
        currentUid: () => 'a',
        loadQuery: (query) async {
          queries.add(query);
          return query.field == 'private' || query.field == 'customerUid'
              ? [event('same')]
              : [];
        },
      );
      expect((await repository.load()).map((e) => e.id), ['same']);
      expect(queries.map((q) => q.field), [
        'private',
        'customerUid',
        'coHosts',
        'checkInStaff',
        'accessList',
      ]);
      expect(queries.first.value, false);
      expect(queries.skip(1).every((q) => q.value == 'a'), isTrue);
      expect(queries.skip(2).every((q) => q.arrayContains), isTrue);
    },
  );
  test(
    'calendar rejects old account results after an account switch',
    () async {
      String? uid = 'a';
      final pending = Completer<List<EventModel>>();
      final repository = CalendarEventsRepository(
        currentUid: () => uid,
        loadQuery: (_) => pending.future,
      );
      final load = repository.load();
      uid = 'b';
      pending.complete([event('private-a')]);
      await expectLater(load, throwsStateError);
    },
  );
  test(
    'signed out calendar starts empty without reading private data',
    () async {
      final repository = CalendarEventsRepository(
        currentUid: () => null,
        loadQuery: (_) async {
          fail('query while signed out');
        },
      );
      expect(await repository.load(), isEmpty);
    },
  );
}
