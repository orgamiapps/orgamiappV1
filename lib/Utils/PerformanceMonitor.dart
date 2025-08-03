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
  int _lastFrameTime = 0;
  bool _isMonitoring = false;

  // Memory thresholds (simplified for now)
  static const int _memoryWarningThreshold = 100 * 1024 * 1024; // 100MB
  static const int _memoryCriticalThreshold = 200 * 1024 * 1024; // 200MB

  // Frame rate thresholds
  static const double _minFrameRate = 30.0; // Minimum acceptable frame rate

  void startMonitoring() {
    if (_isMonitoring) return;
    _isMonitoring = true;

    print('🔍 Starting performance monitoring...');

    // Monitor frame rate
    _frameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
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
    print('🔍 Stopped performance monitoring');
  }

  void _onFrame(Duration timeStamp) {
    _frameCount++;
    _lastFrameTime = timeStamp.inMilliseconds;
  }

  void _checkFrameRate() {
    if (_frameCount < _minFrameRate) {
      print('⚠️ WARNING: Low frame rate detected: $_frameCount fps');
      _handleFrameRateWarning();
    }

    // Reset frame count
    _frameCount = 0;
  }

  void _handleFrameRateWarning() {
    print('Optimizing performance due to low frame rate');

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

  // Method to get current frame rate
  double get currentFrameRate {
    return _frameCount.toDouble();
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
    PerformanceMonitor().startMonitoring();
  }

  @override
  void dispose() {
    PerformanceMonitor().stopMonitoring();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
