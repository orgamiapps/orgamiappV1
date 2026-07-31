import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class PlaceSuggestion {
  final String placeId;
  final String description;
  final String primaryText;
  final String secondaryText;

  const PlaceSuggestion({
    required this.placeId,
    required this.description,
    required this.primaryText,
    required this.secondaryText,
  });

  factory PlaceSuggestion.fromMap(Map<String, dynamic> data) {
    return PlaceSuggestion(
      placeId: data['placeId']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      primaryText: data['primaryText']?.toString() ?? '',
      secondaryText: data['secondaryText']?.toString() ?? '',
    );
  }
}

class PlaceDetails {
  final String? placeId;
  final String displayName;
  final String formattedAddress;
  final String city;
  final String regionCode;
  final LatLng location;

  const PlaceDetails({
    required this.placeId,
    required this.displayName,
    required this.formattedAddress,
    required this.location,
    this.city = '',
    this.regionCode = '',
  });

  factory PlaceDetails.fromMap(Map<String, dynamic> data) {
    return PlaceDetails(
      placeId: data['placeId']?.toString(),
      displayName: data['displayName']?.toString() ?? '',
      formattedAddress: data['formattedAddress']?.toString() ?? '',
      city: data['city']?.toString() ?? '',
      regionCode: data['regionCode']?.toString() ?? '',
      location: LatLng(
        (data['latitude'] as num).toDouble(),
        (data['longitude'] as num).toDouble(),
      ),
    );
  }

  String get cityAndRegion {
    if (city.isNotEmpty && regionCode.isNotEmpty) return '$city, $regionCode';
    return city.isNotEmpty ? city : formattedAddress;
  }
}

class PlacesServiceException implements Exception {
  final String message;

  const PlacesServiceException(this.message);

  @override
  String toString() => message;
}

class PlacesService {
  PlacesService({FirebaseFunctions? functions})
    : _functionsOverride = functions;

  final FirebaseFunctions? _functionsOverride;
  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'us-central1');
  static final Random _random = Random.secure();

  String createSessionToken() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    final value = hex.join();
    return '${value.substring(0, 8)}-'
        '${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-'
        '${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }

  Future<List<PlaceSuggestion>> autocomplete({
    required String query,
    required String sessionToken,
    bool citiesOnly = false,
    LatLng? locationBias,
  }) async {
    try {
      final result = await _functions.httpsCallable('placesAutocomplete').call({
        'query': query,
        'sessionToken': sessionToken,
        'useCase': citiesOnly ? 'groupCity' : 'event',
        if (locationBias != null)
          'locationBias': {
            'latitude': locationBias.latitude,
            'longitude': locationBias.longitude,
          },
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final predictions = (data['predictions'] as List? ?? const []);
      return predictions
          .map(
            (item) =>
                PlaceSuggestion.fromMap(Map<String, dynamic>.from(item as Map)),
          )
          .where((item) => item.placeId.isNotEmpty)
          .toList(growable: false);
    } on FirebaseFunctionsException catch (error) {
      throw PlacesServiceException(_messageFor(error));
    } catch (_) {
      throw const PlacesServiceException(
        'Could not search for locations. Check your connection and try again.',
      );
    }
  }

  Future<PlaceDetails> details({
    required String placeId,
    required String sessionToken,
  }) async {
    try {
      final result = await _functions.httpsCallable('placeDetails').call({
        'placeId': placeId,
        'sessionToken': sessionToken,
      });
      return PlaceDetails.fromMap(
        Map<String, dynamic>.from(result.data as Map),
      );
    } on FirebaseFunctionsException catch (error) {
      throw PlacesServiceException(_messageFor(error));
    } catch (_) {
      throw const PlacesServiceException(
        'Could not load that place. Please try another result.',
      );
    }
  }

  Future<PlaceDetails> reverseGeocode(LatLng location) async {
    try {
      final result = await _functions.httpsCallable('reverseGeocode').call({
        'latitude': location.latitude,
        'longitude': location.longitude,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return PlaceDetails(
        placeId: data['placeId']?.toString(),
        displayName: '',
        formattedAddress: data['formattedAddress']?.toString() ?? '',
        location: location,
      );
    } on FirebaseFunctionsException catch (error) {
      throw PlacesServiceException(_messageFor(error));
    } catch (_) {
      throw const PlacesServiceException(
        'The pin was selected, but its address could not be loaded.',
      );
    }
  }

  String _messageFor(FirebaseFunctionsException error) {
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) return message;
    switch (error.code) {
      case 'unauthenticated':
        return 'Sign in with an account to search for locations.';
      case 'resource-exhausted':
        return 'Too many searches. Please wait a moment and try again.';
      case 'failed-precondition':
        return 'Location search is not configured yet.';
      default:
        return 'Location search is temporarily unavailable.';
    }
  }
}
