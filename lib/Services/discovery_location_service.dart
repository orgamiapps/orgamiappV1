import 'dart:convert';

import 'package:attendus/Services/discovery_marketplace_service.dart';
import 'package:attendus/Services/places_service.dart';
import 'package:attendus/Utils/location_helper.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DiscoveryLocation {
  final double latitude;
  final double longitude;
  final String city;
  final String regionCode;
  final String source;
  final bool nationwide;

  const DiscoveryLocation({
    required this.latitude,
    required this.longitude,
    required this.city,
    required this.regionCode,
    required this.source,
    this.nationwide = false,
  });

  String get label => nationwide
      ? 'United States'
      : regionCode.isEmpty
      ? city
      : '$city, $regionCode';

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'city': city,
    'regionCode': regionCode,
    'source': source,
    'nationwide': nationwide,
  };

  factory DiscoveryLocation.fromJson(Map<String, dynamic> map) =>
      DiscoveryLocation(
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        city: map['city']?.toString() ?? '',
        regionCode: map['regionCode']?.toString() ?? '',
        source: map['source']?.toString() ?? 'saved',
        nationwide: map['nationwide'] == true,
      );
}

class DiscoveryLocationService {
  DiscoveryLocationService({PlacesService? places})
    : _places = places ?? PlacesService();

  static const _key = 'discovery_location_v1';
  static const _interestsKey = 'discovery_interests_v1';
  final PlacesService _places;

  Future<DiscoveryLocation?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return DiscoveryLocation.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      await prefs.remove(_key);
      return null;
    }
  }

  Future<DiscoveryLocation?> useDeviceLocation() async {
    final position = await LocationHelper.getCurrentLocation();
    if (position == null) return null;
    final details = await _places.reverseGeocode(
      LatLng(position.latitude, position.longitude),
      discoveryOnly: true,
    );
    if (details.countryCode.toUpperCase() != 'US') return null;
    return persist(
      DiscoveryLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        city: details.city.isEmpty ? details.formattedAddress : details.city,
        regionCode: details.regionCode,
        source: 'device',
      ),
    );
  }

  Future<DiscoveryLocation> usePlace(PlaceDetails details) => persist(
    DiscoveryLocation(
      latitude: details.location.latitude,
      longitude: details.location.longitude,
      city: details.city.isEmpty ? details.displayName : details.city,
      regionCode: details.regionCode,
      source: 'search',
    ),
  );

  Future<DiscoveryLocation> useNationwide() => persist(
    const DiscoveryLocation(
      latitude: 39.8283,
      longitude: -98.5795,
      city: 'United States',
      regionCode: '',
      source: 'nationwide',
      nationwide: true,
    ),
  );

  Future<DiscoveryLocation> persist(DiscoveryLocation location) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(location.toJson()));
    await DiscoveryMarketplaceService().savePreferences(
      city: location.city,
      regionCode: location.regionCode,
      latitude: location.latitude,
      longitude: location.longitude,
      locationSource: location.source,
    );
    return location;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    LocationHelper.clearCache();
  }

  Future<List<String>> loadInterests() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_interestsKey) ?? const [];
  }

  Future<void> saveInterests(List<String> interests) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_interestsKey, interests);
    final location = await load();
    if (location != null) {
      await DiscoveryMarketplaceService().savePreferences(
        city: location.city,
        regionCode: location.regionCode,
        latitude: location.latitude,
        longitude: location.longitude,
        locationSource: location.source,
        preferredCategories: interests,
      );
    }
  }
}
