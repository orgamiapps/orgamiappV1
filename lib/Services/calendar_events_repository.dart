import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:attendus/models/event_model.dart';

class CalendarEventQuery {
  const CalendarEventQuery(
    this.field,
    this.value, {
    this.arrayContains = false,
  });
  final String field;
  final Object value;
  final bool arrayContains;
}

/// Each query independently proves access under the event read rules.
class CalendarEventsRepository {
  CalendarEventsRepository({
    String? Function()? currentUid,
    Future<List<EventModel>> Function(CalendarEventQuery)? loadQuery,
  }) : _currentUid =
           currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid),
       _loadQuery = loadQuery ?? _loadFirestore;
  final String? Function() _currentUid;
  final Future<List<EventModel>> Function(CalendarEventQuery) _loadQuery;

  static Future<List<EventModel>> _loadFirestore(
    CalendarEventQuery spec,
  ) async {
    final collection = FirebaseFirestore.instance.collection('Events');
    final query = spec.arrayContains
        ? collection.where(spec.field, arrayContains: spec.value)
        : collection.where(spec.field, isEqualTo: spec.value);
    final snapshot = await query.get();
    return snapshot.docs.map(EventModel.fromJson).toList();
  }

  Future<List<EventModel>> load() async {
    final uid = _currentUid();
    if (uid == null) return const [];
    final sources = await Future.wait([
      _loadQuery(const CalendarEventQuery('private', false)),
      _loadQuery(CalendarEventQuery('customerUid', uid)),
      for (final field in ['coHosts', 'checkInStaff', 'accessList'])
        _loadQuery(CalendarEventQuery(field, uid, arrayContains: true)),
    ]);
    if (_currentUid() != uid) throw StateError('Calendar account changed');
    final events = <String, EventModel>{};
    for (final source in sources) {
      for (final event in source) {
        events[event.id] = event;
      }
    }
    return events.values.toList()
      ..sort((a, b) => a.selectedDateTime.compareTo(b.selectedDateTime));
  }
}
