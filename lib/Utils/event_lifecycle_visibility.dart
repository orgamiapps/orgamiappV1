import 'package:attendus/Services/event_lifecycle_store.dart';
import 'package:attendus/models/event_model.dart';

bool isCancelledEvent(EventModel event, EventLifecycleStore lifecycle) =>
    lifecycle.stateFor(event.id).status == EventLifecycleStatus.cancelled ||
    event.status == 'cancelled';

bool isActiveLifecycleEvent(EventModel event, EventLifecycleStore lifecycle) =>
    lifecycle.allowsActive(event.id) &&
    event.status != 'deleted' &&
    !isCancelledEvent(event, lifecycle);

bool isHistoricalLifecycleEvent(
  EventModel event,
  EventLifecycleStore lifecycle,
) => lifecycle.allowsHistory(event.id) && event.status != 'deleted';

bool isActiveLifecycleData(
  String eventId,
  Map<String, dynamic> data,
  EventLifecycleStore lifecycle,
) =>
    lifecycle.allowsActive(eventId) &&
    data['deleted'] != true &&
    data['cancelled'] != true &&
    data['status'] != 'deleted' &&
    data['status'] != 'cancelled';
