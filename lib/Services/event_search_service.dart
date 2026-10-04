import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/Services/on_device_nlp_service.dart';
import 'package:geolocator/geolocator.dart';

typedef EventSearch =
    Future<List<EventModel>> Function(
      String query,
      double? latitude,
      double? longitude,
    );

/// Uses the shipped natural-language parser and authoritative event query.
/// Optional native model assets and SQLite are not prerequisites for search.
class EventSearchService {
  EventSearchService({
    EventSearch? search,
    Future<Position?> Function()? locate,
  }) : _search = search ?? _searchPublicEvents,
       _locate = locate ?? _currentPosition;

  final EventSearch _search;
  final Future<Position?> Function() _locate;

  static Future<List<EventModel>> _searchPublicEvents(
    String query,
    double? latitude,
    double? longitude,
  ) => FirebaseFirestoreHelper().aiSearchEvents(
    query: query,
    latitude: latitude,
    longitude: longitude,
    limit: 25,
  );

  static Future<Position?> _currentPosition() async {
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return null;
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
      ),
    );
  }

  Future<List<EventModel>> search(String query) async {
    final intent = await OnDeviceNLPService.instance.parseQuery(query);
    Position? position;
    if (intent['nearMe'] == true) {
      try {
        position = await _locate().timeout(const Duration(seconds: 3));
      } catch (_) {
        // Permission denial or a missing location plugin must not prevent search.
      }
    }
    return _search(query, position?.latitude, position?.longitude);
  }
}
