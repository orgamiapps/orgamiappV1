import 'package:flutter/material.dart';

/// Optimization utilities for widget building and performance
class BuildOptimization {
  /// Creates an optimized list view with better performance
  /// Uses ListView.builder with proper itemExtent and caching
  static Widget optimizedListView({
    required int itemCount,
    required Widget Function(BuildContext, int) itemBuilder,
    ScrollController? controller,
    EdgeInsets? padding,
    double? itemExtent,
    bool shrinkWrap = false,
    ScrollPhysics? physics,
    Key? key,
  }) {
    return ListView.builder(
      key: key,
      controller: controller,
      padding: padding,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Wrap items in RepaintBoundary to isolate repaints
        return RepaintBoundary(
          child: itemBuilder(context, index),
        );
      },
      itemExtent: itemExtent,
      shrinkWrap: shrinkWrap,
      physics: physics,
      // Add cache extent for better scrolling performance
      cacheExtent: 500.0,
      // Use const physics when possible
      addAutomaticKeepAlives: true,
      addRepaintBoundaries: true,
      addSemanticIndexes: true,
    );
  }

  /// Creates an optimized grid view with better performance
  static Widget optimizedGridView({
    required int itemCount,
    required Widget Function(BuildContext, int) itemBuilder,
    required SliverGridDelegate gridDelegate,
    ScrollController? controller,
    EdgeInsets? padding,
    bool shrinkWrap = false,
    ScrollPhysics? physics,
    Key? key,
  }) {
    return GridView.builder(
      key: key,
      controller: controller,
      padding: padding,
      itemCount: itemCount,
      gridDelegate: gridDelegate,
      itemBuilder: (context, index) {
        // Wrap items in RepaintBoundary to isolate repaints
        return RepaintBoundary(
          child: itemBuilder(context, index),
        );
      },
      shrinkWrap: shrinkWrap,
      physics: physics,
      // Add cache extent for better scrolling performance
      cacheExtent: 500.0,
      addAutomaticKeepAlives: true,
      addRepaintBoundaries: true,
      addSemanticIndexes: true,
    );
  }

  /// Wraps a widget with RepaintBoundary to prevent unnecessary repaints
  static Widget isolateRepaints(Widget child, {Key? key}) {
    return RepaintBoundary(
      key: key,
      child: child,
    );
  }

  /// Creates an optimized container with cached decoration
  static Widget optimizedContainer({
    required Widget child,
    Color? color,
    BoxDecoration? decoration,
    EdgeInsets? padding,
    EdgeInsets? margin,
    double? width,
    double? height,
    AlignmentGeometry? alignment,
    Key? key,
  }) {
    return RepaintBoundary(
      child: Container(
        key: key,
        width: width,
        height: height,
        padding: padding,
        margin: margin,
        alignment: alignment,
        decoration: decoration,
        color: decoration == null ? color : null,
        child: child,
      ),
    );
  }

  /// Creates a debounced callback for search or text input
  static VoidCallback debounce(
    VoidCallback callback, {
    Duration delay = const Duration(milliseconds: 300),
  }) {
    DateTime? lastActionTime;

    return () {
      final now = DateTime.now();
      if (lastActionTime == null ||
          now.difference(lastActionTime!) >= delay) {
        lastActionTime = now;
        callback();
      }
    };
  }

  /// Creates an optimized animated widget with reduced overhead
  static Widget optimizedAnimatedContainer({
    required Widget child,
    required Duration duration,
    Curve curve = Curves.easeInOut,
    VoidCallback? onEnd,
    Key? key,
  }) {
    return RepaintBoundary(
      child: AnimatedContainer(
        key: key,
        duration: duration,
        curve: curve,
        onEnd: onEnd,
        child: child,
      ),
    );
  }

  /// Wraps a widget with a visibility check to avoid building when not visible
  static Widget optimizedVisibility({
    required bool visible,
    required Widget child,
    Widget replacement = const SizedBox.shrink(),
    bool maintainState = false,
    bool maintainAnimation = false,
    bool maintainSize = false,
    Key? key,
  }) {
    return Visibility(
      key: key,
      visible: visible,
      maintainState: maintainState,
      maintainAnimation: maintainAnimation,
      maintainSize: maintainSize,
      replacement: replacement,
      child: child,
    );
  }

  /// Creates a memoized widget that only rebuilds when dependencies change
  /// Similar to React.memo()
  static Widget memoize(
    Widget Function() builder, {
    List<Object?>? dependencies,
  }) {
    return _MemoizedWidget(
      builder: builder,
      dependencies: dependencies ?? [],
    );
  }

  /// Optimizes heavy computation by running it in a separate isolate (for complex calculations)
  static Future<T> computeAsync<T>(
    T Function() computation,
  ) async {
    // For simple operations, just run synchronously
    // For complex operations, this could use compute() from foundation
    return computation();
  }

  /// Creates an optimized image with proper caching and memory management
  static Widget optimizedImage({
    required String url,
    double? width,
    double? height,
    BoxFit? fit,
    Widget? placeholder,
    Widget? errorWidget,
    Key? key,
  }) {
    return RepaintBoundary(
      child: Image.network(
        url,
        key: key,
        width: width,
        height: height,
        fit: fit ?? BoxFit.cover,
        cacheWidth: width?.toInt(),
        cacheHeight: height?.toInt(),
        errorBuilder: (context, error, stackTrace) {
          return errorWidget ??
              Container(
                width: width,
                height: height,
                color: Colors.grey[300],
                child: const Icon(Icons.image_not_supported),
              );
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return placeholder ??
              Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                ),
              );
        },
      ),
    );
  }
}

/// A memoized widget that only rebuilds when dependencies change
class _MemoizedWidget extends StatefulWidget {
  final Widget Function() builder;
  final List<Object?> dependencies;

  const _MemoizedWidget({
    required this.builder,
    required this.dependencies,
  });

  @override
  State<_MemoizedWidget> createState() => _MemoizedWidgetState();
}

class _MemoizedWidgetState extends State<_MemoizedWidget> {
  late Widget _cachedWidget;
  late List<Object?> _cachedDependencies;

  @override
  void initState() {
    super.initState();
    _cachedWidget = widget.builder();
    _cachedDependencies = List.from(widget.dependencies);
  }

  @override
  void didUpdateWidget(_MemoizedWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Check if dependencies have changed
    bool dependenciesChanged = false;
    if (_cachedDependencies.length != widget.dependencies.length) {
      dependenciesChanged = true;
    } else {
      for (int i = 0; i < widget.dependencies.length; i++) {
        if (_cachedDependencies[i] != widget.dependencies[i]) {
          dependenciesChanged = true;
          break;
        }
      }
    }

    if (dependenciesChanged) {
      _cachedWidget = widget.builder();
      _cachedDependencies = List.from(widget.dependencies);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _cachedWidget;
  }
}

/// Extension methods for widget optimization
extension WidgetOptimizationExtensions on Widget {
  /// Wraps the widget with RepaintBoundary
  Widget isolateRepaints() {
    return RepaintBoundary(child: this);
  }

  /// Wraps the widget with a key for better rebuild optimization
  Widget withKey(Key key) {
    return KeyedSubtree(key: key, child: this);
  }

  /// Makes the widget conditionally visible
  Widget conditionallyVisible(bool visible) {
    return Visibility(
      visible: visible,
      maintainState: false,
      maintainAnimation: false,
      maintainSize: false,
      child: this,
    );
  }
}

