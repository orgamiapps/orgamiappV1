import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/Events/global_events_map_screen.dart';
import 'package:attendus/Services/places_service.dart';
import 'package:flutter_test/flutter_test.dart';

EventModel eventAt(
  DateTime start, {
  String status = 'scheduled',
  String locationType = 'in_person',
  bool isPrivate = false,
  double latitude = 40.7128,
  double longitude = -74.0060,
  int duration = 2,
}) {
  return EventModel(
    id: 'event-1',
    groupName: '',
    title: 'Test event',
    description: '',
    location: 'New York, NY',
    customerUid: 'owner',
    imageUrl: '',
    selectedDateTime: start,
    eventGenerateTime: start,
    status: status,
    private: isPrivate,
    getLocation: locationType == 'in_person',
    radius: 100,
    latitude: latitude,
    longitude: longitude,
    locationType: locationType,
    eventDuration: duration,
  );
}

void main() {
  test('Places sessions use unique UUID v4 tokens', () {
    final service = PlacesService();
    final first = service.createSessionToken();
    final second = service.createSessionToken();
    final uuidV4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    expect(first, matches(uuidV4));
    expect(second, matches(uuidV4));
    expect(second, isNot(first));
  });

  group('EventModel location fields', () {
    test('legacy records default to in-person', () {
      final now = DateTime(2026, 7, 27, 12);
      final event = EventModel.fromJson({
        'id': 'legacy',
        'groupName': '',
        'title': 'Legacy event',
        'description': '',
        'location': 'Boston, MA',
        'customerUid': 'owner',
        'imageUrl': '',
        'selectedDateTime': now.toIso8601String(),
        'eventGenerateTime': now.toIso8601String(),
        'status': 'active',
        'private': false,
        'getLocation': true,
        'latitude': 42.3601,
        'longitude': -71.0589,
        'radius': 100,
      });

      expect(event.locationType, 'in_person');
      expect(event.placeId, isNull);
    });

    test(
      'online persistence clears physical metadata and geofence settings',
      () {
        final event =
            eventAt(
                DateTime(2026, 7, 28, 18),
                locationType: 'online',
                latitude: 40.7128,
                longitude: -74.0060,
              )
              ..locationName = 'Old venue'
              ..placeId = 'old-place-id'
              ..getLocation = true
              ..radius = 250
              ..signInSecurityTier = 'all'
              ..signInMethods = ['geofence', 'qr_code', 'manual_code'];

        final json = event.toJson();
        expect(json['locationType'], 'online');
        expect(json, containsPair('locationName', null));
        expect(json, containsPair('placeId', null));
        expect(json['getLocation'], isFalse);
        expect(json['placeId'], isNull);
        expect(json['latitude'], 0);
        expect(json['longitude'], 0);
        expect(json['radius'], 0);
        expect(json['signInSecurityTier'], 'regular');
        expect(json['signInMethods'], isNot(contains('geofence')));
      },
    );

    test('in-person persistence retains selected place metadata', () {
      final event = eventAt(DateTime(2026, 7, 28, 18))
        ..locationName = 'Empire State Building'
        ..placeId = 'selected-place-id';

      final json = event.toJson();
      expect(json['locationType'], 'in_person');
      expect(json['locationName'], 'Empire State Building');
      expect(json['placeId'], 'selected-place-id');
      expect(json['getLocation'], isTrue);
      expect(json['latitude'], isNot(0));
      expect(json['longitude'], isNot(0));
    });
  });

  group('global map eligibility', () {
    final now = DateTime(2026, 7, 27, 12);

    test('includes scheduled and legacy active physical events', () {
      expect(
        isEventEligibleForGlobalMap(
          eventAt(now.add(const Duration(hours: 1))),
          now,
        ),
        isTrue,
      );
      expect(
        isEventEligibleForGlobalMap(eventAt(now, status: 'active'), now),
        isTrue,
      );
    });

    test('excludes private, pending, online, and invalid coordinates', () {
      final start = now.add(const Duration(hours: 1));
      expect(
        isEventEligibleForGlobalMap(eventAt(start, isPrivate: true), now),
        isFalse,
      );
      expect(
        isEventEligibleForGlobalMap(eventAt(start, status: 'pending'), now),
        isFalse,
      );
      expect(
        isEventEligibleForGlobalMap(eventAt(start, status: 'cancelled'), now),
        isFalse,
      );
      expect(
        isEventEligibleForGlobalMap(
          eventAt(start, locationType: 'online'),
          now,
        ),
        isFalse,
      );
      expect(
        isEventEligibleForGlobalMap(
          eventAt(start, latitude: 0, longitude: 0),
          now,
        ),
        isFalse,
      );
    });

    test('excludes events after the two-hour end buffer', () {
      final event = eventAt(now.subtract(const Duration(hours: 5)));
      expect(isEventEligibleForGlobalMap(event, now), isFalse);
    });
  });

  group('global map camera mode', () {
    test('uses an event zoom for one marker and bounds for several', () {
      expect(
        selectGlobalMapCameraMode(
          eventCount: 1,
          hasBounds: false,
          hasUserLocation: true,
        ),
        GlobalMapCameraMode.singleEvent,
      );
      expect(
        selectGlobalMapCameraMode(
          eventCount: 2,
          hasBounds: true,
          hasUserLocation: true,
        ),
        GlobalMapCameraMode.eventBounds,
      );
    });

    test('empty maps prefer the user and otherwise show the world', () {
      expect(
        selectGlobalMapCameraMode(
          eventCount: 0,
          hasBounds: false,
          hasUserLocation: true,
        ),
        GlobalMapCameraMode.userLocation,
      );
      expect(
        selectGlobalMapCameraMode(
          eventCount: 0,
          hasBounds: false,
          hasUserLocation: false,
        ),
        GlobalMapCameraMode.world,
      );
    });
  });
}
