import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:attendus/Utils/logger.dart';

/// Helper class to detect platform-specific conditions
class PlatformHelper {
  static bool? _isEmulator;
  
  /// Check if the app is running on an emulator/simulator
  static Future<bool> isEmulator() async {
    // Cache the result
    if (_isEmulator != null) return _isEmulator!;
    
    try {
      if (kIsWeb) {
        _isEmulator = false;
        return false;
      }
      
      if (Platform.isAndroid) {
        // Check for common Android emulator properties
        // Note: This is a simplified check. In production, you might want to
        // check more properties or use a package like device_info_plus
        final bool isAndroidEmulator = 
            Platform.resolvedExecutable.contains('emulator') ||
            Platform.resolvedExecutable.contains('simulator') ||
            (Platform.environment['ANDROID_EMULATOR_HOME'] != null) ||
            (Platform.environment['ANDROID_SDK_ROOT'] != null && 
             Platform.environment['USER']?.toLowerCase() == 'runner');
        
        _isEmulator = isAndroidEmulator;
        
        if (isAndroidEmulator) {
          Logger.info('Running on Android emulator - adjusting configurations');
        }
        
        return isAndroidEmulator;
      } else if (Platform.isIOS) {
        // Check for iOS simulator
        // On iOS simulator, the architecture is typically x86_64 or i386
        final bool isIOSSimulator = 
            Platform.environment['SIMULATOR_DEVICE_NAME'] != null ||
            Platform.environment['SIMULATOR_RUNTIME'] != null;
        
        _isEmulator = isIOSSimulator;
        
        if (isIOSSimulator) {
          Logger.info('Running on iOS simulator - adjusting configurations');
        }
        
        return isIOSSimulator;
      }
      
      _isEmulator = false;
      return false;
    } catch (e) {
      Logger.warning('Could not detect if running on emulator: $e');
      _isEmulator = false;
      return false;
    }
  }
  
  /// Check if location services should be initialized
  /// Returns false for emulators to prevent hanging
  static Future<bool> shouldInitializeLocationServices() async {
    if (await isEmulator()) {
      Logger.info('Skipping location services initialization on emulator');
      return false;
    }
    return true;
  }
  
  /// Get appropriate timeouts based on platform
  static Duration getLocationTimeout() {
    if (_isEmulator == true) {
      // Shorter timeout for emulators
      return const Duration(seconds: 2);
    }
    // Normal timeout for real devices
    return const Duration(seconds: 10);
  }
  
  /// Get Firebase initialization timeout
  static Duration getFirebaseTimeout() {
    if (_isEmulator == true) {
      // Longer timeout for emulators as they might be slower
      return const Duration(seconds: 20);
    }
    // Normal timeout for real devices
    return const Duration(seconds: 10);
  }
}
