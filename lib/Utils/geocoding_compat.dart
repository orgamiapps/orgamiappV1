import 'package:flutter/widgets.dart' show Locale;
import 'package:geocoding/geocoding.dart' as geocoding;

export 'package:geocoding/geocoding.dart' show Location, Placemark;

final geocoding.Geocoding _geocoding = geocoding.Geocoding();

Future<List<geocoding.Location>> locationFromAddress(
  String address, {
  Locale? locale,
}) {
  return _geocoding.locationFromAddress(address, locale: locale);
}

Future<List<geocoding.Placemark>> placemarkFromCoordinates(
  double latitude,
  double longitude, {
  Locale? locale,
}) {
  return _geocoding.placemarkFromCoordinates(
    latitude,
    longitude,
    locale: locale,
  );
}
