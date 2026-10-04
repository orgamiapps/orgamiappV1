import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:geolocator/geolocator.dart';

class SmartArrivalFailure extends StateError {
  SmartArrivalFailure(this.reason, String message) : super(message);
  final String reason;
}

/// Attendance deliberately does not reuse cached discovery/search positions.
class SmartArrivalService {
  SmartArrivalService({this.isWeb = kIsWeb});
  final bool isWeb;
  StreamSubscription<Position>? _subscription;
  Completer<Position>? _reading;
  int _generation = 0;

  void cancel() {
    _generation++;
    unawaited(_subscription?.cancel());
    _subscription = null;
    if (_reading != null && !_reading!.isCompleted) {
      _reading!.completeError(
        SmartArrivalFailure('cancelled', 'Location check cancelled.'),
      );
    }
    _reading = null;
  }

  Future<Map<String, dynamic>> freshPosition({
    bool requestPermission = false,
  }) async {
    cancel();
    final generation = _generation;
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw SmartArrivalFailure(
        'services_disabled',
        'Turn on location services, or use the venue QR or code.',
      );
    }
    if (generation != _generation) {
      throw SmartArrivalFailure('cancelled', 'Location check cancelled.');
    }
    LocationPermission permission;
    try {
      permission = await Geolocator.checkPermission();
    } catch (_) {
      if (!isWeb) rethrow;
      // Some HTTPS browsers support geolocation without the Permissions API.
      permission = LocationPermission.unableToDetermine;
    }
    if (generation != _generation) {
      throw SmartArrivalFailure('cancelled', 'Location check cancelled.');
    }
    if (!isWeb &&
        permission == LocationPermission.denied &&
        requestPermission) {
      permission = await Geolocator.requestPermission();
    }
    if (generation != _generation) {
      throw SmartArrivalFailure('cancelled', 'Location check cancelled.');
    }
    final browserPrompt =
        isWeb &&
        requestPermission &&
        permission != LocationPermission.deniedForever;
    if (!browserPrompt &&
        permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      throw SmartArrivalFailure(
        'permission_denied',
        'Location permission is needed for Smart Arrival. You can also use the venue QR or code.',
      );
    }
    // A foreground, single-result subscription can be cancelled immediately
    // when the user leaves, unlike an uncancellable getCurrentPosition future.
    final reading = Completer<Position>();
    _reading = reading;
    _subscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        ).listen(
          (position) {
            if (!reading.isCompleted) reading.complete(position);
          },
          onError: (Object error, StackTrace stack) {
            if (!reading.isCompleted) reading.completeError(error, stack);
          },
        );
    try {
      final position = await reading.future.timeout(
        const Duration(seconds: 10),
      );
      if (generation != _generation) {
        throw SmartArrivalFailure('cancelled', 'Location check cancelled.');
      }
      final age = DateTime.now().difference(position.timestamp);
      if (age > const Duration(seconds: 30) ||
          age < const Duration(seconds: -5) ||
          !position.accuracy.isFinite ||
          !position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.accuracy < 0 ||
          position.accuracy > 50 ||
          position.isMocked) {
        throw SmartArrivalFailure(
          'inaccurate_or_stale',
          'We could not get an accurate location. Retry or ask event staff for help.',
        );
      }
      return {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'sampledAt': position.timestamp.toUtc().toIso8601String(),
        'mocked': position.isMocked,
      };
    } finally {
      if (generation == _generation) {
        await _subscription?.cancel();
        _subscription = null;
        _reading = null;
      }
    }
  }

  Future<List<Map<String, dynamic>>> candidates(
    Map<String, dynamic> position, {
    String? eventId,
  }) async {
    final response = await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('getSmartArrivalCandidates')
        .call({'position': position, 'eventId': ?eventId});
    return ((response.data as Map)['events'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}
