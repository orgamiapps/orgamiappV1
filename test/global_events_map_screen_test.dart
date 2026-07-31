import 'dart:async';

import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/Events/global_events_map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

EventModel mapEvent({
  required String id,
  String status = 'scheduled',
  String locationType = 'in_person',
  bool isPrivate = false,
}) {
  final start = DateTime.now().add(const Duration(hours: 1));
  return EventModel(
    id: id,
    groupName: '',
    title: 'Map event $id',
    description: '',
    location: 'Boston, MA',
    customerUid: 'owner',
    imageUrl: '',
    selectedDateTime: start,
    eventGenerateTime: start,
    status: status,
    private: isPrivate,
    getLocation: locationType == 'in_person',
    radius: 100,
    latitude: 42.3601,
    longitude: -71.0589,
    locationType: locationType,
    eventDuration: 2,
  );
}

Widget app(Stream<List<EventModel>> events) {
  return MaterialApp(
    home: GlobalEventsMapScreen(
      eventsForTesting: events,
      requestUserLocation: false,
      mapEnabled: false,
    ),
  );
}

void main() {
  testWidgets('successful empty data keeps the map shell and shows the CTA', (
    tester,
  ) async {
    await tester.pumpWidget(app(Stream.value(const [])));
    await tester.pump();

    expect(find.text('No events with map locations yet'), findsOneWidget);
    expect(find.text('Create event'), findsOneWidget);
    expect(find.text('Map unavailable'), findsNothing);
  });

  testWidgets('stream failures show a retryable load error', (tester) async {
    await tester.pumpWidget(
      app(Stream<List<EventModel>>.error(StateError('offline'))),
    );
    await tester.pump();

    expect(find.textContaining('Events could not be loaded'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('live updates show only eligible map events', (tester) async {
    final controller = StreamController<List<EventModel>>.broadcast();
    addTearDown(controller.close);
    await tester.pumpWidget(app(controller.stream));

    controller.add([
      mapEvent(id: 'public'),
      mapEvent(id: 'online', locationType: 'online'),
      mapEvent(id: 'pending', status: 'pending'),
      mapEvent(id: 'private', isPrivate: true),
    ]);
    await tester.pump();

    expect(find.text('1 event on map'), findsOneWidget);
    expect(find.text('No events with map locations yet'), findsNothing);
  });
}
