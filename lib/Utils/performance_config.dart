import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Performance configuration class to centralize performance settings
class PerformanceConfig {
  // Performance monitoring settings
  static const bool enablePerformanceMonitoring = true;
  static const bool enableMemoryMonitoring = true;
  static const bool enableNetworkMonitoring = true;

  // Cache settings
  static const int maxCacheSize = 100; // MB
  static const Duration cacheExpiry = Duration(hours: 24);

  // Image optimization settings
  static const int maxImageWidth = 1024;
  static const int maxImageHeight = 1024;
  static const int imageQuality = 80;

  // Network settings
  static const Duration networkTimeout = Duration(seconds: 30);
  static const int maxRetries = 3;

  // Animation settings
  static const Duration defaultAnimationDuration = Duration(milliseconds: 300);
  static const Curve defaultAnimationCurve = Curves.easeInOut;

  // Debug settings
  static const bool showPerformanceOverlay = false;
  static const bool enableDebugLogging = true;

  // Initialize performance configuration
  static void initialize() {
    if (kDebugMode) {
      debugPrint('Performance configuration initialized');
    }

    // Set up performance monitoring
    if (enablePerformanceMonitoring) {
      _setupPerformanceMonitoring();
    }

    if (kDebugMode) {
      debugPrint(
        'Performance monitoring enabled: $enablePerformanceMonitoring',
      );
      debugPrint('Memory monitoring enabled: $enableMemoryMonitoring');
      debugPrint('Network monitoring enabled: $enableNetworkMonitoring');
    }
  }

  // Set up performance monitoring
  static void _setupPerformanceMonitoring() {
    // This would typically set up performance monitoring tools
    // like Firebase Performance, Sentry, etc.
    if (kDebugMode) {
      debugPrint('Setting up performance monitoring...');
    }
  }

  // Get cache configuration
  static Map<String, dynamic> getCacheConfig() {
    return {'maxSize': maxCacheSize, 'expiry': cacheExpiry};
  }

  // Get image optimization configuration
  static Map<String, dynamic> getImageConfig() {
    return {
      'maxWidth': maxImageWidth,
      'maxHeight': maxImageHeight,
      'quality': imageQuality,
    };
  }

  // Get network configuration
  static Map<String, dynamic> getNetworkConfig() {
    return {'timeout': networkTimeout, 'maxRetries': maxRetries};
  }
}

/// Animation speed enum
enum AnimationSpeed { fast, normal, slow }

/// Network operation type enum
enum NetworkOperationType { short, normal, long }

/// Performance monitoring utilities
class PerformanceUtils {
  static void logPerformance(String operation, Duration duration) {
    if (kDebugMode) {
      debugPrint(
        '⏱️ Performance: $operation took ${duration.inMilliseconds}ms',
      );
    }
  }

  static void logMemoryUsage(String context, int bytes) {
    if (kDebugMode) {
      final mb = bytes / (1024 * 1024);
      print('💾 Memory: $context - ${mb.toStringAsFixed(2)}MB');
    }
  }

  static void logNetworkRequest(String url, Duration duration) {
    if (kDebugMode) {
      debugPrint('🌐 Network: $url took ${duration.inMilliseconds}ms');
    }
  }
}
