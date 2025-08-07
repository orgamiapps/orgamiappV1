import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:orgami/Utils/logger.dart';

class DwellTimeTracker {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Track active dwell sessions
  static final Map<String, DwellSession> _activeSessions = {};

  /// Starts dwell time tracking for a user at an event
  static Future<bool> startDwellTracking(String eventId) async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      String sessionKey = '$eventId-${currentUser.uid}';

      // Check if already tracking
      if (_activeSessions.containsKey(sessionKey)) {
        if (kDebugMode) {
          Logger.debug(
            'Dwell tracking already active for $eventId-${currentUser.uid}',
          );
        }
        return true;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Create dwell session
      DwellSession session = DwellSession(
        eventId: eventId,
        userId: currentUser.uid,
        startTime: DateTime.now(),
        startLocation: position,
      );

      _activeSessions[sessionKey] = session;

      if (kDebugMode) {
        Logger.debug('Dwell tracking started for $eventId-${currentUser.uid}');
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        Logger.error('Error starting dwell tracking: $e');
      }
      return false;
    }
  }

  /// Stops dwell time tracking manually
  static Future<bool> stopDwellTracking(String eventId) async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      String sessionKey = '$eventId-${currentUser.uid}';
      DwellSession? session = _activeSessions.remove(sessionKey);

      if (session != null) {
        await _recordDwellTime(session);

        if (kDebugMode) {
          Logger.debug(
            'Dwell tracking stopped manually for $eventId-${currentUser.uid}',
          );
        }
        return true;
      }

      return false;
    } catch (e) {
      if (kDebugMode) {
        Logger.error('Error stopping dwell tracking: $e');
      }
      return false;
    }
  }

  /// Starts location monitoring for dwell tracking
  static void startLocationMonitoring(String eventId) {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) return;

      String sessionKey = '$eventId-${currentUser.uid}';
      DwellSession? session = _activeSessions[sessionKey];

      if (session == null) return;

      // Start location stream
      StreamSubscription<Position>? locationSubscription;
      locationSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10, // 10 meters
            ),
          ).listen(
            (Position position) {
              _handleLocationUpdate(session, position, locationSubscription);
            },
            onError: (error) {
              if (kDebugMode) {
                Logger.error('Location stream error: $error');
              }
            },
          );

      session.locationSubscription = locationSubscription;
    } catch (e) {
      if (kDebugMode) {
        Logger.error('Error starting location monitoring: $e');
      }
    }
  }

  /// Handles location updates and checks geofence status
  static void _handleLocationUpdate(
    DwellSession session,
    Position newPosition,
    StreamSubscription<Position>? subscription,
  ) {
    try {
      // Calculate distance from start location
      double distance = Geolocator.distanceBetween(
        session.startLocation.latitude,
        session.startLocation.longitude,
        newPosition.latitude,
        newPosition.longitude,
      );

      // Auto-stop if user moved more than 100 meters
      if (distance > 100) {
        _autoStopDwellTracking(session, subscription);
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('Error handling location update: $e');
      }
    }
  }

  /// Handles confirmed exit after grace period
  static Future<void> handleExitConfirmation(String eventId) async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) return;

      String sessionKey = '$eventId-${currentUser.uid}';
      DwellSession? session = _activeSessions[sessionKey];

      if (session != null) {
        // Cancel location subscription
        session.locationSubscription?.cancel();

        // Remove from active sessions
        _activeSessions.remove(sessionKey);

        // Record dwell time
        await _recordDwellTime(session);
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('Error handling exit confirmation: $e');
      }
    }
  }

  /// Calculates distance between two points in feet

  /// Checks if dwell tracking is active for a user at an event
  static bool isDwellTrackingActive(String eventId, String customerUid) {
    return _activeSessions.containsKey('$eventId-$customerUid');
  }

  /// Disposes all active tracking
  static void dispose() {
    for (final session in _activeSessions.values) {
      session.locationSubscription?.cancel();
    }
    _activeSessions.clear();
  }

  // Record dwell time to Firestore
  static Future<void> _recordDwellTime(DwellSession session) async {
    try {
      final dwellTime = DateTime.now().difference(session.startTime);

      // Only record if dwell time is significant (more than 1 minute)
      if (dwellTime.inMinutes > 0) {
        await _firestore.collection('dwell_times').add({
          'eventId': session.eventId,
          'userId': session.userId,
          'startTime': Timestamp.fromDate(session.startTime),
          'endTime': Timestamp.fromDate(DateTime.now()),
          'durationMinutes': dwellTime.inMinutes,
          'startLocation': {
            'latitude': session.startLocation.latitude,
            'longitude': session.startLocation.longitude,
          },
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (kDebugMode) {
          Logger.error('Dwell time recorded: ${dwellTime.inMinutes} minutes');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('Error recording dwell time: $e');
      }
    }
  }

  // Auto-stop dwell tracking
  static Future<void> _autoStopDwellTracking(
    DwellSession session,
    StreamSubscription<Position>? subscription,
  ) async {
    try {
      // Cancel location subscription
      subscription?.cancel();

      // Remove from active sessions
      String sessionKey = '${session.eventId}-${session.userId}';
      _activeSessions.remove(sessionKey);

      // Record dwell time
      await _recordDwellTime(session);

      if (kDebugMode) {
        Logger.error(
          'Dwell tracking auto-stopped for ${session.eventId}-${session.userId}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('Error in auto-stop: $e');
      }
    }
  }
}

// Dwell session model
class DwellSession {
  final String eventId;
  final String userId;
  final DateTime startTime;
  final Position startLocation;
  StreamSubscription<Position>? locationSubscription;

  DwellSession({
    required this.eventId,
    required this.userId,
    required this.startTime,
    required this.startLocation,
    this.locationSubscription,
  });
}
