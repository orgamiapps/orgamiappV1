import 'dart:async';

import 'package:attendus/Services/places_service.dart';
import 'package:attendus/screens/Events/location_picker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class FakePlacesService extends PlacesService {
  Future<List<PlaceSuggestion>> Function(String query)? onAutocomplete;
  Future<PlaceDetails> Function(String placeId)? onDetails;
  Future<PlaceDetails> Function(LatLng location)? onReverseGeocode;
  int sessionCount = 0;
  int autocompleteCalls = 0;

  @override
  String createSessionToken() => 'session-${++sessionCount}';

  @override
  Future<List<PlaceSuggestion>> autocomplete({
    required String query,
    required String sessionToken,
    bool citiesOnly = false,
    LatLng? locationBias,
  }) {
    ++autocompleteCalls;
    return onAutocomplete?.call(query) ?? Future.value(const []);
  }

  @override
  Future<PlaceDetails> details({
    required String placeId,
    required String sessionToken,
  }) {
    return onDetails?.call(placeId) ??
        Future.value(
          const PlaceDetails(
            placeId: 'default-place',
            displayName: 'Default place',
            formattedAddress: '1 Default Street',
            location: LatLng(40, -74),
          ),
        );
  }

  @override
  Future<PlaceDetails> reverseGeocode(LatLng location) {
    return onReverseGeocode?.call(location) ??
        Future.value(
          PlaceDetails(
            placeId: null,
            displayName: '',
            formattedAddress: '',
            location: location,
          ),
        );
  }
}

Widget picker(
  FakePlacesService service, {
  LocationPickerMapBuilder? mapBuilder,
}) {
  return MaterialApp(
    home: LocationPickerScreen(
      placesService: service,
      mapEnabled: false,
      mapBuilder: mapBuilder,
    ),
  );
}

Future<void> search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(milliseconds: 301));
  await tester.pump();
}

void main() {
  testWidgets('debounced search shows an explicit empty state', (tester) async {
    final service = FakePlacesService();
    await tester.pumpWidget(picker(service));

    await search(tester, 'unknown venue');

    expect(service.autocompleteCalls, 1);
    expect(find.textContaining('No locations found'), findsOneWidget);
  });

  testWidgets('search failures are visible and retryable', (tester) async {
    final service = FakePlacesService();
    var shouldFail = true;
    service.onAutocomplete = (_) {
      if (shouldFail) {
        return Future.error(
          const PlacesServiceException('Location search is unavailable.'),
        );
      }
      return Future.value(const []);
    };
    await tester.pumpWidget(picker(service));

    await search(tester, 'Central Park');
    expect(find.text('Location search is unavailable.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    shouldFail = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(service.autocompleteCalls, 2);
    expect(find.textContaining('No locations found'), findsOneWidget);
  });

  testWidgets('stale autocomplete responses cannot replace newer results', (
    tester,
  ) async {
    final service = FakePlacesService();
    final first = Completer<List<PlaceSuggestion>>();
    final second = Completer<List<PlaceSuggestion>>();
    service.onAutocomplete = (query) {
      return query.startsWith('First') ? first.future : second.future;
    };
    await tester.pumpWidget(picker(service));

    await search(tester, 'First venue');
    await search(tester, 'Second venue');
    second.complete(const [
      PlaceSuggestion(
        placeId: 'second',
        description: 'Second venue, Boston',
        primaryText: 'Second venue',
        secondaryText: 'Boston',
      ),
    ]);
    await tester.pump();
    first.complete(const [
      PlaceSuggestion(
        placeId: 'first',
        description: 'First venue, New York',
        primaryText: 'First venue',
        secondaryText: 'New York',
      ),
    ]);
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text('Second venue'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text('First venue'),
      ),
      findsNothing,
    );
  });

  testWidgets('selecting a suggestion stores metadata and renews the session', (
    tester,
  ) async {
    final service = FakePlacesService();
    service.onAutocomplete = (_) => Future.value(const [
      PlaceSuggestion(
        placeId: 'place-1',
        description: 'Madison Square Garden, New York, NY',
        primaryText: 'Madison Square Garden',
        secondaryText: 'New York, NY',
      ),
    ]);
    service.onDetails = (_) => Future.value(
      const PlaceDetails(
        placeId: 'place-1',
        displayName: 'Madison Square Garden',
        formattedAddress: '4 Pennsylvania Plaza, New York, NY',
        location: LatLng(40.7505, -73.9934),
      ),
    );
    await tester.pumpWidget(picker(service));

    await search(tester, 'Madison Square Garden');
    await tester.tap(find.text('Madison Square Garden').last);
    await tester.pump();

    expect(find.text('4 Pennsylvania Plaza, New York, NY'), findsWidgets);
    expect(find.text('Use this location'), findsOneWidget);
    expect(service.sessionCount, 2);
  });

  testWidgets('a manual pin remains usable when reverse geocoding fails', (
    tester,
  ) async {
    final service = FakePlacesService();
    service.onReverseGeocode = (_) =>
        Future.error(const PlacesServiceException('Address lookup failed.'));
    await tester.pumpWidget(
      picker(
        service,
        mapBuilder: (onMapTap) => Center(
          child: FilledButton(
            onPressed: () => onMapTap(const LatLng(42.3601, -71.0589)),
            child: const Text('Simulate map tap'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Simulate map tap'));
    await tester.pump();

    expect(find.text('42.360100, -71.058900'), findsWidgets);
    expect(find.text('Address lookup failed.'), findsOneWidget);
    expect(find.text('Use this location'), findsOneWidget);
  });
}
