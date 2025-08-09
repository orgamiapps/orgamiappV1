/// Performance configuration constants for optimal app performance
class PerformanceConfig {
  // Animation durations - reduced for better performance
  static const Duration shortAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 400);
  static const Duration longAnimation = Duration(milliseconds: 600);

  // Image loading optimizations
  static const Duration imageCacheExpiry = Duration(hours: 2);
  static const int imageMemoryCacheWidth = 300;
  static const int imageMemoryCacheHeight = 200;
  static const int imageDiskCacheWidth = 600;
  static const int imageDiskCacheHeight = 400;

  // Firebase operation timeouts
  static const Duration firebaseTimeout = Duration(seconds: 8);
  static const Duration shortFirebaseTimeout = Duration(seconds: 5);

  // Location settings
  static const Duration locationCacheExpiry = Duration(minutes: 5);
  static const Duration locationTimeout = Duration(seconds: 10);

  // UI performance settings
  static const int maxAnimationControllers = 3; // Limit concurrent animations
  static const Duration frameThrottleDuration = Duration(milliseconds: 16); // 60fps
  static const int maxConcurrentOperations = 2;

  // Data processing limits
  static const int maxEventsPerBatch = 50;
  static const int maxUsersPerBatch = 30;
  static const int maxSearchResults = 20;

  // Memory management
  static const Duration cacheCleanupInterval = Duration(minutes: 30);
  static const int maxCacheSize = 100; // Maximum cached items

  // Network optimization
  static const Duration networkTimeout = Duration(seconds: 15);
  static const int maxRetryAttempts = 3;
  static const Duration retryDelay = Duration(seconds: 2);

  // Debounce settings
  static const Duration searchDebounce = Duration(milliseconds: 300);
  static const Duration scrollDebounce = Duration(milliseconds: 100);
  static const Duration refreshDebounce = Duration(seconds: 2);
}