import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';

class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._internal();
  factory PerformanceMonitor() => _instance;
  PerformanceMonitor._internal();

  Timer? _memoryTimer;
  Timer? _frameTimer;
  int _frameCount = 0;
  bool _isMonitoring = false;

  // Optimized frame rate thresholds
  static const double _minFrameRate =
      25.0; // Reduced from 30.0 for better tolerance

  void startMonitoring() {
    if (_isMonitoring) return;
    _isMonitoring = true;

    if (kDebugMode) {
      debugPrint('🔍 Starting performance monitoring...');
    }

    // Monitor frame rate with reduced frequency (every 3 seconds instead of 2)
    _frameTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _checkFrameRate();
    });

    // Add frame callback for frame rate monitoring
    SchedulerBinding.instance.addPersistentFrameCallback((timeStamp) {
      _onFrame(timeStamp);
    });
  }

  void stopMonitoring() {
    _isMonitoring = false;
    _memoryTimer?.cancel();
    _frameTimer?.cancel();
    if (kDebugMode) {
      debugPrint('🔍 Stopped performance monitoring');
    }
  }

  void _onFrame(Duration timeStamp) {
    _frameCount++;
  }

  void _checkFrameRate() {
    // Calculate actual FPS based on time period (3 seconds)
    final fps = _frameCount / 3.0;
    
    if (fps < _minFrameRate) {
      if (kDebugMode) {
        debugPrint('⚠️ WARNING: Low frame rate detected: ${fps.toStringAsFixed(1)} fps');
      }
      _handleFrameRateWarning();
    }

    // Reset frame count
    _frameCount = 0;
  }

  void _handleFrameRateWarning() {
    if (kDebugMode) {
      debugPrint('Optimizing performance due to low frame rate');
    }

    // Reduce animation complexity
    // This could involve disabling non-essential animations
  }

  // Method to log performance metrics
  void logPerformanceMetric(String metric, dynamic value) {
    developer.log('Performance: $metric = $value');
  }

  // Method to check if app is running smoothly
  bool get isPerformanceGood {
    return _frameCount >= _minFrameRate;
  }

  // Method to get current frame rate (calculated over 3 second window)
  double get currentFrameRate {
    return _frameCount / 3.0;
  }
}

// Extension to add performance monitoring to widgets
extension PerformanceMonitoring on Widget {
  Widget withPerformanceMonitoring() {
    return PerformanceMonitorWidget(child: this);
  }
}

class PerformanceMonitorWidget extends StatefulWidget {
  final Widget child;

  const PerformanceMonitorWidget({super.key, required this.child});

  @override
  State<PerformanceMonitorWidget> createState() =>
      _PerformanceMonitorWidgetState();
}

class _PerformanceMonitorWidgetState extends State<PerformanceMonitorWidget> {
  @override
  void initState() {
    super.initState();
    // Only start monitoring in debug mode to reduce production overhead
    if (kDebugMode) {
      PerformanceMonitor().startMonitoring();
    }
  }

  @override
  void dispose() {
    if (kDebugMode) {
      PerformanceMonitor().stopMonitoring();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
