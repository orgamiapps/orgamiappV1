import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:attendus/Utils/logger.dart';

/// Centralized location management to prevent permission conflicts
class LocationHelper {
  static Position? _cachedPosition;
  static DateTime? _lastLocationUpdate;
  static bool _isRequestingLocation = false;
  static const Duration _cacheExpiry = Duration(minutes: 5);

  /// Get current location with proper error handling and caching
  static Future<Position?> getCurrentLocation({
    bool showErrorDialog = false,
    BuildContext? context,
  }) async {
    // Prevent multiple simultaneous location requests
    if (_isRequestingLocation) {
      Logger.debug('Location request already in progress');
      return _cachedPosition;
    }

    // Return cached position if still valid
    if (_cachedPosition != null &&
        _lastLocationUpdate != null &&
        DateTime.now()
                .difference(_lastLocationUpdate!)
                .compareTo(_cacheExpiry) <
            0) {
      Logger.debug('Returning cached location');
      return _cachedPosition;
    }

    _isRequestingLocation = true;

    try {
      // Check if location service is enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        Logger.warning('Location services are disabled');
        if (showErrorDialog && context != null && context.mounted) {
          _showLocationServiceDialog(context);
        }
        return null;
      }

      // Check permission status
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        Logger.debug('Requesting location permission');
        permission = await Geolocator.requestPermission();

        if (permission == LocationPermission.denied) {
          Logger.warning('Location permission denied');
          if (showErrorDialog && context != null && context.mounted) {
            _showPermissionDeniedDialog(context);
          }
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        Logger.error('Location permission permanently denied');
        if (showErrorDialog && context != null && context.mounted) {
          _showPermissionPermanentlyDeniedDialog(context);
        }
        return null;
      }

      // Get current position with timeout
      Logger.debug('Getting current location...');
      Position position = await Geolocator.getCurrentPosition(
        // New Geolocator versions recommend settings objects instead of deprecated fields
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // Cache the position
      _cachedPosition = position;
      _lastLocationUpdate = DateTime.now();

      Logger.success(
        'Location retrieved successfully: ${position.latitude}, ${position.longitude}',
      );
      return position;
    } catch (e) {
      Logger.error('Error getting location: $e');
      if (showErrorDialog && context != null && context.mounted) {
        _showLocationErrorDialog(context, e.toString());
      }
      return null;
    } finally {
      _isRequestingLocation = false;
    }
  }

  /// Convert Position to LatLng
  static LatLng? positionToLatLng(Position? position) {
    if (position == null) return null;
    return LatLng(position.latitude, position.longitude);
  }

  /// Check if location permissions are granted
  static Future<bool> hasLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (e) {
      Logger.error('Error checking location permission: $e');
      return false;
    }
  }

  /// Calculate distance between two points
  static double calculateDistance(LatLng point1, LatLng point2) {
    return Geolocator.distanceBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    );
  }

  /// Check if location is within radius
  static bool isWithinRadius(
    LatLng center,
    double radiusInMeters,
    LatLng point,
  ) {
    double distance = calculateDistance(center, point);
    return distance <= radiusInMeters;
  }

  /// Clear cached location (useful for refresh scenarios)
  static void clearCache() {
    _cachedPosition = null;
    _lastLocationUpdate = null;
  }

  // Dialog helpers
  static void _showLocationServiceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Services Disabled'),
        content: const Text(
          'Please enable location services in your device settings to use location-based features.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static void _showPermissionDeniedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Permission Required'),
        content: const Text(
          'Location access is needed to find events near you. Please grant location permission.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await Geolocator.requestPermission();
            },
            child: const Text('Grant Permission'),
          ),
        ],
      ),
    );
  }

  static void _showPermissionPermanentlyDeniedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Permission Permanently Denied'),
        content: const Text(
          'Location permission has been permanently denied. Please enable it in app settings to use location features.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await Geolocator.openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  static void _showLocationErrorDialog(BuildContext context, String error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Error'),
        content: Text('Unable to get your location: $error'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
