import 'package:flutter/material.dart';

typedef DeferredLibraryLoader = Future<void> Function();
typedef DeferredScreenBuilder = Widget Function();

/// Loads a deferred Dart library once and renders an actionable retry state if
/// its network request fails.
class DeferredScreenLoader extends StatefulWidget {
  const DeferredScreenLoader({
    super.key,
    required this.loadLibrary,
    required this.builder,
    this.loadingLabel = 'Loading...',
  });

  final DeferredLibraryLoader loadLibrary;
  final DeferredScreenBuilder builder;
  final String loadingLabel;

  @override
  State<DeferredScreenLoader> createState() => _DeferredScreenLoaderState();
}

class _DeferredScreenLoaderState extends State<DeferredScreenLoader> {
  late Future<void> _loadFuture;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _loadFuture = widget.loadLibrary();
  }

  void _retry() {
    setState(() {
      _attempt++;
      _loadFuture = widget.loadLibrary();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      key: ValueKey(_attempt),
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          return widget.builder();
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 40),
                  const SizedBox(height: 12),
                  const Text(
                    'This section could not be loaded.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _retry, child: const Text('Retry')),
                ],
              ),
            ),
          );
        }

        return Center(
          child: Semantics(
            label: widget.loadingLabel,
            child: const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ),
        );
      },
    );
  }
}
