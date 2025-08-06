import 'package:flutter/foundation.dart';

/// Performance configuration class to centralize performance settings
class PerformanceConfig {
  // Cache settings
  static const Duration defaultCacheExpiry = Duration(minutes: 5);
  static const Duration shortCacheExpiry = Duration(minutes: 2);
  static const Duration longCacheExpiry = Duration(minutes: 15);
  
  // Image optimization settings
  static const int maxImageCacheWidth = 600;
  static const int maxImageCacheHeight = 400;
  static const int maxImageMemoryWidth = 300;
  static const int maxImageMemoryHeight = 200;
  
  // Animation settings
  static const Duration fastAnimationDuration = Duration(milliseconds: 200);
  static const Duration normalAnimationDuration = Duration(milliseconds: 300);
  static const Duration slowAnimationDuration = Duration(milliseconds: 500);
  
  // Network settings
  static const Duration networkTimeout = Duration(seconds: 10);
  static const Duration shortNetworkTimeout = Duration(seconds: 5);
  static const Duration longNetworkTimeout = Duration(seconds: 30);
  
  // Firebase settings
  static const int maxFirestoreBatchSize = 500;
  static const Duration firestoreCacheExpiry = Duration(minutes: 10);
  
  // UI settings
  static const double defaultBorderRadius = 12.0;
  static const double smallBorderRadius = 8.0;
  static const double largeBorderRadius = 20.0;
  
  // Memory settings
  static const int memoryWarningThreshold = 80 * 1024 * 1024; // 80MB
  static const int memoryCriticalThreshold = 150 * 1024 * 1024; // 150MB
  
  // Frame rate settings
  static const double minFrameRate = 25.0;
  static const double targetFrameRate = 60.0;
  
  // Debug settings
  static bool get enablePerformanceLogging => kDebugMode;
  static bool get enableDetailedLogging => kDebugMode;
  
  // Feature flags for performance optimization
  static const bool enableLazyLoading = true;
  static const bool enableImageCompression = true;
  static const bool enableNetworkCaching = true;
  static const bool enableMemoryOptimization = true;
  
  /// Get optimized image dimensions based on screen size
  static Map<String, int> getOptimizedImageDimensions(double screenWidth, double screenHeight) {
    final aspectRatio = screenWidth / screenHeight;
    
    if (aspectRatio > 1.5) {
      // Landscape
      return {
        'width': (screenWidth * 0.8).round(),
        'height': (screenHeight * 0.6).round(),
      };
    } else if (aspectRatio < 0.7) {
      // Portrait
      return {
        'width': (screenWidth * 0.9).round(),
        'height': (screenHeight * 0.7).round(),
      };
    } else {
      // Square-ish
      return {
        'width': (screenWidth * 0.85).round(),
        'height': (screenHeight * 0.65).round(),
      };
    }
  }
  
  /// Get cache key with expiry
  static String getCacheKey(String baseKey, {Duration? expiry}) {
    final expiryDuration = expiry ?? defaultCacheExpiry;
    final expiryTimestamp = DateTime.now().add(expiryDuration).millisecondsSinceEpoch;
    return '${baseKey}_$expiryTimestamp';
  }
  
  /// Check if cache is still valid
  static bool isCacheValid(String cacheKey) {
    try {
      final parts = cacheKey.split('_');
      if (parts.length < 2) return false;
      
      final timestamp = int.tryParse(parts.last);
      if (timestamp == null) return false;
      
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      return DateTime.now().isBefore(cacheTime);
    } catch (e) {
      return false;
    }
  }
  
  /// Get performance-optimized animation duration
  static Duration getAnimationDuration(AnimationSpeed speed) {
    switch (speed) {
      case AnimationSpeed.fast:
        return fastAnimationDuration;
      case AnimationSpeed.normal:
        return normalAnimationDuration;
      case AnimationSpeed.slow:
        return slowAnimationDuration;
    }
  }
  
  /// Get network timeout based on operation type
  static Duration getNetworkTimeout(NetworkOperationType type) {
    switch (type) {
      case NetworkOperationType.short:
        return shortNetworkTimeout;
      case NetworkOperationType.normal:
        return networkTimeout;
      case NetworkOperationType.long:
        return longNetworkTimeout;
    }
  }
}

/// Animation speed enum
enum AnimationSpeed { fast, normal, slow }

/// Network operation type enum
enum NetworkOperationType { short, normal, long }

/// Performance monitoring utilities
class PerformanceUtils {
  static void logPerformance(String operation, Duration duration) {
    if (PerformanceConfig.enablePerformanceLogging) {
      print('⏱️ Performance: $operation took ${duration.inMilliseconds}ms');
    }
  }
  
  static void logMemoryUsage(String context, int bytes) {
    if (PerformanceConfig.enablePerformanceLogging) {
      final mb = bytes / (1024 * 1024);
      print('💾 Memory: $context - ${mb.toStringAsFixed(2)}MB');
    }
  }
  
  static void logNetworkRequest(String url, Duration duration) {
    if (PerformanceConfig.enablePerformanceLogging) {
      print('🌐 Network: $url took ${duration.inMilliseconds}ms');
    }
  }
} 