import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:orgami/Models/AttendanceModel.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Utils/Toast.dart';

class DwellTimeTracker {
  static const double _exitThreshold =
      200.0; // 200 feet radius for exit detection
  static const Duration _exitGracePeriod = Duration(
    minutes: 15,
  ); // 15 minutes grace period
  static const Duration _locationUpdateInterval = Duration(
    minutes: 5,
  ); // 5-minute location updates
  static const Duration _maxDwellTime = Duration(
    hours: 10,
  ); // 10-hour max dwell time

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, StreamSubscription<Position>> _locationSubscriptions = {};
  final Map<String, Timer> _exitTimers = {};
  final Map<String, Timer> _autoStopTimers = {};

  /// Starts dwell time tracking for a user at an event
  Future<void> startDwellTracking({
    required String eventId,
    required String customerUid,
    required EventModel eventModel,
    required Function(String) onStatusUpdate,
  }) async {
    try {
      // Check if dwell tracking is already active
      if (_locationSubscriptions.containsKey('$eventId-$customerUid')) {
        print('Dwell tracking already active for $eventId-$customerUid');
        return;
      }

      // Update attendance record with entry timestamp
      await _updateAttendanceEntry(eventId, customerUid);

      // Start location monitoring
      await _startLocationMonitoring(
        eventId: eventId,
        customerUid: customerUid,
        eventModel: eventModel,
        onStatusUpdate: onStatusUpdate,
      );

      // Set up auto-stop timer based on event end time
      _setupAutoStopTimer(eventId, customerUid, eventModel);

      print('Dwell tracking started for $eventId-$customerUid');
    } catch (e) {
      print('Error starting dwell tracking: $e');
      rethrow;
    }
  }

  /// Stops dwell time tracking manually
  Future<void> stopDwellTracking({
    required String eventId,
    required String customerUid,
    String? notes,
  }) async {
    try {
      await _stopLocationMonitoring(eventId, customerUid);
      await _updateAttendanceExit(
        eventId,
        customerUid,
        'manual-stopped',
        notes ?? 'Manual check-out',
      );

      print('Dwell tracking stopped manually for $eventId-$customerUid');
    } catch (e) {
      print('Error stopping dwell tracking: $e');
      rethrow;
    }
  }

  /// Updates attendance record with entry timestamp
  Future<void> _updateAttendanceEntry(
    String eventId,
    String customerUid,
  ) async {
    final docId = '$eventId-$customerUid';

    await _firestore.collection(AttendanceModel.firebaseKey).doc(docId).update({
      'entryTimestamp': Timestamp.fromDate(DateTime.now()),
      'dwellStatus': 'active',
      'dwellNotes': 'Geofence entry detected',
    });
  }

  /// Updates attendance record with exit timestamp and calculates dwell time
  Future<void> _updateAttendanceExit(
    String eventId,
    String customerUid,
    String status,
    String notes,
  ) async {
    final docId = '$eventId-$customerUid';

    // Get current attendance record
    final doc = await _firestore
        .collection(AttendanceModel.firebaseKey)
        .doc(docId)
        .get();

    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      final entryTimestamp = data['entryTimestamp'] as Timestamp?;

      if (entryTimestamp != null) {
        final exitTime = DateTime.now();
        final dwellDuration = exitTime.difference(entryTimestamp.toDate());

        // Cap dwell time at maximum
        final finalDwellTime = dwellDuration > _maxDwellTime
            ? _maxDwellTime
            : dwellDuration;

        await _firestore
            .collection(AttendanceModel.firebaseKey)
            .doc(docId)
            .update({
              'exitTimestamp': Timestamp.fromDate(exitTime),
              'dwellTime': finalDwellTime.inMilliseconds,
              'dwellStatus': status,
              'dwellNotes': notes,
            });

        print('Dwell time recorded: ${finalDwellTime.inMinutes} minutes');
      }
    }
  }

  /// Starts location monitoring for dwell tracking
  Future<void> _startLocationMonitoring({
    required String eventId,
    required String customerUid,
    required EventModel eventModel,
    required Function(String) onStatusUpdate,
  }) async {
    final subscriptionKey = '$eventId-$customerUid';

    // Check location permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions permanently denied');
    }

    // Start location stream
    final locationStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      ),
    );

    final subscription = locationStream.listen(
      (Position position) {
        _handleLocationUpdate(
          position: position,
          eventId: eventId,
          customerUid: customerUid,
          eventModel: eventModel,
          onStatusUpdate: onStatusUpdate,
        );
      },
      onError: (error) {
        print('Location stream error: $error');
        onStatusUpdate('Location tracking error: $error');
      },
    );

    _locationSubscriptions[subscriptionKey] = subscription;
  }

  /// Handles location updates and checks geofence status
  void _handleLocationUpdate({
    required Position position,
    required String eventId,
    required String customerUid,
    required EventModel eventModel,
    required Function(String) onStatusUpdate,
  }) {
    final currentLocation = LatLng(position.latitude, position.longitude);
    final eventLocation = eventModel.getLatLng();
    final distance = _calculateDistance(currentLocation, eventLocation);

    final subscriptionKey = '$eventId-$customerUid';

    if (distance > _exitThreshold) {
      // User is outside the geofence
      if (!_exitTimers.containsKey(subscriptionKey)) {
        // Start exit timer
        _exitTimers[subscriptionKey] = Timer(_exitGracePeriod, () {
          _handleExitConfirmed(
            eventId: eventId,
            customerUid: customerUid,
            onStatusUpdate: onStatusUpdate,
          );
        });

        onStatusUpdate('Exit detected - grace period started');
      }
    } else {
      // User is inside the geofence
      if (_exitTimers.containsKey(subscriptionKey)) {
        // Cancel exit timer
        _exitTimers[subscriptionKey]?.cancel();
        _exitTimers.remove(subscriptionKey);
        onStatusUpdate('Returned to event area');
      }
    }
  }

  /// Handles confirmed exit after grace period
  Future<void> _handleExitConfirmed({
    required String eventId,
    required String customerUid,
    required Function(String) onStatusUpdate,
  }) async {
    try {
      await _stopLocationMonitoring(eventId, customerUid);
      await _updateAttendanceExit(
        eventId,
        customerUid,
        'completed',
        'Exit confirmed after grace period',
      );

      onStatusUpdate('Dwell tracking completed');
    } catch (e) {
      print('Error handling exit confirmation: $e');
      onStatusUpdate('Error completing dwell tracking: $e');
    }
  }

  /// Sets up auto-stop timer based on event end time
  void _setupAutoStopTimer(
    String eventId,
    String customerUid,
    EventModel eventModel,
  ) {
    final subscriptionKey = '$eventId-$customerUid';
    final now = DateTime.now();
    final autoStopTime = eventModel.dwellTrackingEndTime;

    if (autoStopTime.isAfter(now)) {
      final delay = autoStopTime.difference(now);

      _autoStopTimers[subscriptionKey] = Timer(delay, () {
        _handleAutoStop(eventId, customerUid);
      });
    }
  }

  /// Handles auto-stop when event ends
  Future<void> _handleAutoStop(String eventId, String customerUid) async {
    try {
      await _stopLocationMonitoring(eventId, customerUid);
      await _updateAttendanceExit(
        eventId,
        customerUid,
        'auto-stopped',
        'Auto-stopped at event end time',
      );

      print('Dwell tracking auto-stopped for $eventId-$customerUid');
    } catch (e) {
      print('Error in auto-stop: $e');
    }
  }

  /// Stops location monitoring
  Future<void> _stopLocationMonitoring(
    String eventId,
    String customerUid,
  ) async {
    final subscriptionKey = '$eventId-$customerUid';

    // Cancel location subscription
    _locationSubscriptions[subscriptionKey]?.cancel();
    _locationSubscriptions.remove(subscriptionKey);

    // Cancel exit timer
    _exitTimers[subscriptionKey]?.cancel();
    _exitTimers.remove(subscriptionKey);

    // Cancel auto-stop timer
    _autoStopTimers[subscriptionKey]?.cancel();
    _autoStopTimers.remove(subscriptionKey);
  }

  /// Calculates distance between two points in feet
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 20902231; // Earth radius in feet

    final lat1 = point1.latitude * pi / 180;
    final lat2 = point2.latitude * pi / 180;
    final dLat = (point2.latitude - point1.latitude) * pi / 180;
    final dLng = (point2.longitude - point1.longitude) * pi / 180;

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  /// Checks if dwell tracking is active for a user at an event
  bool isDwellTrackingActive(String eventId, String customerUid) {
    final subscriptionKey = '$eventId-$customerUid';
    return _locationSubscriptions.containsKey(subscriptionKey);
  }

  /// Disposes all active tracking
  void dispose() {
    for (final subscription in _locationSubscriptions.values) {
      subscription.cancel();
    }
    _locationSubscriptions.clear();

    for (final timer in _exitTimers.values) {
      timer.cancel();
    }
    _exitTimers.clear();

    for (final timer in _autoStopTimers.values) {
      timer.cancel();
    }
    _autoStopTimers.clear();
  }
}
