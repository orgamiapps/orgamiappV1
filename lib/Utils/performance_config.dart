/// Performance configuration constants for optimal app performance
/// Updated with modern best practices for maximum speed and efficiency
class PerformanceConfig {
  // Animation durations - optimized for perceived performance
  static const Duration shortAnimation = Duration(milliseconds: 150);
  static const Duration mediumAnimation = Duration(milliseconds: 250);
  static const Duration longAnimation = Duration(milliseconds: 350);

  // Image loading optimizations - adjusted for better memory usage
  static const Duration imageCacheExpiry = Duration(hours: 3);
  static const int imageMemoryCacheWidth = 400; // Increased for modern screens
  static const int imageMemoryCacheHeight = 300;
  static const int imageDiskCacheWidth = 800;
  static const int imageDiskCacheHeight = 600;
  static const int maxImageCacheSize = 50; // Maximum number of cached images

  // Firebase operation timeouts - balanced for reliability and speed
  static const Duration firebaseTimeout = Duration(seconds: 10);
  static const Duration shortFirebaseTimeout = Duration(seconds: 6);
  static const Duration queryTimeout = Duration(seconds: 8);

  // Location settings
  static const Duration locationCacheExpiry = Duration(minutes: 10);
  static const Duration locationTimeout = Duration(seconds: 8);

  // UI performance settings
  static const int maxAnimationControllers = 2; // Limit concurrent animations
  static const Duration frameThrottleDuration = Duration(milliseconds: 16); // 60fps
  static const int maxConcurrentOperations = 3; // Increased for better parallelism
  static const double scrollCacheExtent = 600.0; // Pixels to cache off-screen

  // Data processing limits - optimized for faster initial loads
  static const int initialEventsLoad = 20; // Reduced for faster first load
  static const int maxEventsPerBatch = 30; // Reduced from 50
  static const int maxUsersPerBatch = 20; // Reduced from 30
  static const int maxSearchResults = 15; // Reduced from 20
  static const int paginationSize = 15; // Items per page

  // Memory management - more aggressive cleanup
  static const Duration cacheCleanupInterval = Duration(minutes: 20);
  static const int maxCacheSize = 80; // Reduced from 100
  static const int maxFirestoreListeners = 5; // Limit active listeners

  // Network optimization
  static const Duration networkTimeout = Duration(seconds: 12);
  static const int maxRetryAttempts = 2; // Reduced from 3 for faster failure
  static const Duration retryDelay = Duration(milliseconds: 1500);
  static const bool useCompressionForImages = true;

  // Debounce settings - optimized for responsiveness
  static const Duration searchDebounce = Duration(milliseconds: 250);
  static const Duration scrollDebounce = Duration(milliseconds: 50);
  static const Duration refreshDebounce = Duration(milliseconds: 1500);
  static const Duration inputDebounce = Duration(milliseconds: 200);

  // Build optimization
  static const bool enableRepaintBoundaries = true;
  static const bool useConstWidgets = true;
  static const bool cacheSizedBox = true;

  // List optimization
  static const bool addAutomaticKeepAlives = true;
  static const bool addRepaintBoundaries = true;
  static const double listItemExtent = 80.0; // Average item height for better scrolling

  // State management optimization
  static const bool useSelectorsOverConsumers = true;
  static const bool batchStateUpdates = true;

  // Asset preloading
  static const bool preloadCriticalAssets = true;
  static const List<String> criticalAssets = [
    'images/inAppLogo.png',
    // Add other critical assets
  ];

  /// Get recommended cache size based on available memory
  static int getRecommendedCacheSize() {
    // In a real app, you might check available memory
    // For now, return the configured max
    return maxCacheSize;
  }

  /// Check if device supports high-performance features
  static bool shouldUseHighPerformanceMode() {
    // Could check device specs, battery level, etc.
    return true;
  }

  /// Get optimized batch size based on network conditions
  static int getOptimizedBatchSize(bool isOnline, bool isSlowNetwork) {
    if (!isOnline) return 10;
    if (isSlowNetwork) return 15;
    return maxEventsPerBatch;
  }
}