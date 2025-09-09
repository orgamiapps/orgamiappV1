import 'package:geolocator/geolocator.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:attendus/Utils/platform_helper.dart';

/// Configuration and workarounds for emulator-specific issues
class EmulatorConfig {
  static bool _hasConfigured = false;
  
  /// Configure app for emulator environment
  static Future<void> configureForEmulator() async {
    if (_hasConfigured) return;
    _hasConfigured = true;
    
    try {
      final isEmulator = await PlatformHelper.isEmulator();
      
      if (isEmulator) {
        Logger.info('Configuring app for emulator environment');
        
        // Configure Geolocator for emulator
        await _configureGeolocatorForEmulator();
        
        Logger.success('Emulator configuration complete');
      }
    } catch (e) {
      Logger.warning('Error configuring for emulator: $e');
    }
  }
  
  /// Configure Geolocator specifically for emulator
  static Future<void> _configureGeolocatorForEmulator() async {
    try {
      Logger.info('Configuring Geolocator for emulator...');
      
      // Check if location services are available without blocking
      final serviceEnabled = await Geolocator.isLocationServiceEnabled()
          .timeout(
            const Duration(seconds: 1),
            onTimeout: () {
              Logger.warning('Location service check timed out on emulator');
              return false;
            },
          );
      
      if (!serviceEnabled) {
        Logger.info('Location services not available on emulator - this is normal');
        return;
      }
      
      // Check permission status without requesting
      final permission = await Geolocator.checkPermission()
          .timeout(
            const Duration(seconds: 1),
            onTimeout: () {
              Logger.warning('Permission check timed out on emulator');
              return LocationPermission.denied;
            },
          );
      
      Logger.info('Emulator location permission status: $permission');
      
      // Don't request permission during startup on emulator
      // Let individual features request when needed
      
    } catch (e) {
      Logger.warning('Error configuring Geolocator for emulator: $e');
    }
  }
  
  /// Get last known location for emulator (mock location)
  static Future<Position?> getEmulatorMockLocation() async {
    try {
      // Try to get last known position first (faster)
      final lastPosition = await Geolocator.getLastKnownPosition()
          .timeout(
            const Duration(seconds: 1),
            onTimeout: () => null,
          );
      
      if (lastPosition != null) {
        Logger.debug('Using last known position for emulator');
        return lastPosition;
      }
      
      // Return a default mock location for emulators (San Francisco)
      Logger.info('Using mock location for emulator');
      return Position(
        latitude: 37.7749,
        longitude: -122.4194,
        timestamp: DateTime.now(),
        accuracy: 100.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );
    } catch (e) {
      Logger.warning('Error getting emulator mock location: $e');
      return null;
    }
  }
}
