import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:attendus/Utils/location_helper.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/models/event_model.dart';

/// Professional service for detecting nearby events with active geofences
/// Used for location-based sign-in functionality
class GeofenceEventDetector {
  static final GeofenceEventDetector _instance =
      GeofenceEventDetector._internal();
  factory GeofenceEventDetector() => _instance;
  GeofenceEventDetector._internal();

  /// Find all events with active geofences that the user is currently within
  /// Returns a list of events sorted by distance (closest first)
  Future<List<EventWithDistance>> findNearbyGeofencedEvents({
    Position? userPosition,
    Duration? timeBuffer,
  }) async {
    try {
      Logger.debug('GeofenceEventDetector: Starting nearby event search');

      // Get user's current location
      final position = userPosition ?? await LocationHelper.getCurrentLocation();
      if (position == null) {
        Logger.warning('Unable to get user location for geofence check');
        return [];
      }

      final userLatLng = LatLng(position.latitude, position.longitude);
      Logger.debug(
        'User location: ${position.latitude}, ${position.longitude}',
      );

      // Get all active events with geofence enabled
      final now = DateTime.now();
      final timeBufferDuration = timeBuffer ?? const Duration(hours: 24);

      final eventsSnapshot = await FirebaseFirestore.instance
          .collection(EventModel.firebaseKey)
          .where('getLocation', isEqualTo: true)
          .where('status', isEqualTo: 'active')
          .get();

      Logger.debug(
        'Found ${eventsSnapshot.docs.length} events with geofence enabled',
      );

      List<EventWithDistance> nearbyEvents = [];

      for (final doc in eventsSnapshot.docs) {
        try {
          final event = EventModel.fromJson(doc);

          // Check if event is happening now or soon
          final eventTime = event.selectedDateTime;
          final eventEndTime = eventTime.add(const Duration(hours: 12)); // Assume event lasts up to 12 hours
          
          // Event must be either:
          // 1. Starting within the time buffer (24 hours by default)
          // 2. Currently happening (between start time and end time)
          final isUpcoming = eventTime.isAfter(now) && 
              eventTime.difference(now) <= timeBufferDuration;
          final isHappening = now.isAfter(eventTime) && now.isBefore(eventEndTime);
          
          if (!isUpcoming && !isHappening) {
            Logger.debug(
              'Event ${event.title} is outside time window (starts: $eventTime, now: $now)',
            );
            continue;
          }

          // Check if event has valid geofence coordinates
          if (event.latitude == 0 && event.longitude == 0) {
            Logger.debug('Event ${event.title} has no geofence coordinates');
            continue;
          }

          // Calculate distance to event
          final eventLocation = LatLng(event.latitude, event.longitude);
          final distance = LocationHelper.calculateDistance(
            userLatLng,
            eventLocation,
          );

          // Check if user is within geofence
          final radiusInMeters = event.radius * 0.3048; // Convert feet to meters
          if (distance <= radiusInMeters) {
            Logger.success(
              'User is within geofence of event: ${event.title} (${distance.toStringAsFixed(1)}m away)',
            );
            nearbyEvents.add(EventWithDistance(
              event: event,
              distance: distance,
              isWithinGeofence: true,
            ));
          }
        } catch (e) {
          Logger.error('Error processing event: $e');
          continue;
        }
      }

      // Sort by distance (closest first)
      nearbyEvents.sort((a, b) => a.distance.compareTo(b.distance));

      Logger.info('Found ${nearbyEvents.length} nearby geofenced events');
      return nearbyEvents;
    } catch (e) {
      Logger.error('Error finding nearby geofenced events: $e');
      return [];
    }
  }

  /// Find the closest event with active geofence that user is within
  Future<EventWithDistance?> findClosestGeofencedEvent({
    Position? userPosition,
  }) async {
    final nearbyEvents = await findNearbyGeofencedEvents(
      userPosition: userPosition,
    );

    if (nearbyEvents.isEmpty) return null;
    return nearbyEvents.first;
  }

  /// Check if user is within geofence of a specific event
  Future<bool> isWithinEventGeofence({
    required String eventId,
    Position? userPosition,
  }) async {
    try {
      // Get user's current location
      final position = userPosition ?? await LocationHelper.getCurrentLocation();
      if (position == null) {
        Logger.warning('Unable to get user location for geofence check');
        return false;
      }

      // Get event details
      final eventDoc = await FirebaseFirestore.instance
          .collection(EventModel.firebaseKey)
          .doc(eventId)
          .get();

      if (!eventDoc.exists) {
        Logger.warning('Event $eventId not found');
        return false;
      }

      final event = EventModel.fromJson(eventDoc);

      // Check if geofence is enabled
      if (!event.getLocation) {
        Logger.debug('Event $eventId does not have geofence enabled');
        return false;
      }

      // Check if event has valid coordinates
      if (event.latitude == 0 && event.longitude == 0) {
        Logger.debug('Event $eventId has no geofence coordinates');
        return false;
      }

      // Calculate distance
      final userLatLng = LatLng(position.latitude, position.longitude);
      final eventLocation = LatLng(event.latitude, event.longitude);
      final distance = LocationHelper.calculateDistance(
        userLatLng,
        eventLocation,
      );

      // Check if within radius
      final radiusInMeters = event.radius * 0.3048; // Convert feet to meters
      final isWithin = distance <= radiusInMeters;

      Logger.debug(
        'User is ${isWithin ? "within" : "outside"} geofence of ${event.title} (${distance.toStringAsFixed(1)}m away, radius: ${radiusInMeters.toStringAsFixed(1)}m)',
      );

      return isWithin;
    } catch (e) {
      Logger.error('Error checking event geofence: $e');
      return false;
    }
  }

  /// Get human-readable distance description
  static String formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.toStringAsFixed(0)} meters';
    } else {
      return '${(distanceInMeters / 1000).toStringAsFixed(2)} km';
    }
  }

  /// Calculate time until event starts
  static String formatTimeUntilEvent(DateTime eventTime) {
    final now = DateTime.now();
    final difference = eventTime.difference(now);

    if (difference.isNegative) {
      // Event has started
      final elapsed = now.difference(eventTime);
      if (elapsed.inHours < 1) {
        return 'Started ${elapsed.inMinutes} min ago';
      } else {
        return 'Started ${elapsed.inHours}h ago';
      }
    } else {
      // Event hasn't started yet
      if (difference.inHours < 1) {
        return 'Starts in ${difference.inMinutes} min';
      } else if (difference.inHours < 24) {
        return 'Starts in ${difference.inHours}h';
      } else {
        return 'Starts in ${difference.inDays} days';
      }
    }
  }
}

/// Model for an event with distance information
class EventWithDistance {
  final EventModel event;
  final double distance; // in meters
  final bool isWithinGeofence;

  EventWithDistance({
    required this.event,
    required this.distance,
    this.isWithinGeofence = false,
  });

  String get formattedDistance =>
      GeofenceEventDetector.formatDistance(distance);

  String get timeUntilEvent =>
      GeofenceEventDetector.formatTimeUntilEvent(event.selectedDateTime);
}

