import 'package:flutter/material.dart';
import 'package:attendus/Utils/deferred_load_recovery.dart';
import 'package:attendus/Utils/logger.dart';

typedef DeferredLibraryLoader = Future<void> Function();
typedef DeferredScreenBuilder = Widget Function();

/// Loads a deferred Dart library once and renders an actionable retry state if
/// its network request fails.
class DeferredScreenLoader extends StatefulWidget {
  const DeferredScreenLoader({
    super.key,
    required this.loadLibrary,
    required this.builder,
    required this.recoveryKey,
    this.loadingLabel = 'Loading...',
    this.recovery,
  });

  final DeferredLibraryLoader loadLibrary;
  final DeferredScreenBuilder builder;
  final String recoveryKey;
  final String loadingLabel;
  final DeferredLoadRecovery? recovery;

  @override
  State<DeferredScreenLoader> createState() => _DeferredScreenLoaderState();
}

class _DeferredScreenLoaderState extends State<DeferredScreenLoader> {
  late final DeferredLoadRecovery _recovery;
  _DeferredScreenState _state = _DeferredScreenState.loading;

  @override
  void initState() {
    super.initState();
    _recovery = widget.recovery ?? createDeferredLoadRecovery();
    _load();
  }

  Future<void> _load() async {
    if (mounted && _state != _DeferredScreenState.loading) {
      setState(() => _state = _DeferredScreenState.loading);
    }

    try {
      await widget.loadLibrary();
      _recovery.clearRecoveryGuard(widget.recoveryKey);
      if (!mounted) return;
      setState(() => _state = _DeferredScreenState.loaded);
    } catch (error, stackTrace) {
      Logger.warning(
        'Deferred section ${widget.recoveryKey} failed to load: $error',
      );
      Logger.debug('$stackTrace');
      if (!mounted) return;

      if (_recovery.claimAutomaticRefresh(widget.recoveryKey)) {
        setState(() => _state = _DeferredScreenState.recovering);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _recovery.refreshApp();
        });
        return;
      }

      setState(() => _state = _DeferredScreenState.error);
    }
  }

  void _refreshApp() {
    setState(() => _state = _DeferredScreenState.recovering);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recovery.refreshApp();
    });
  }

  @override
  Widget build(BuildContext context) {
    return switch (_state) {
      _DeferredScreenState.loaded => widget.builder(),
      _DeferredScreenState.error => _buildError(),
      _DeferredScreenState.recovering => _buildProgress(
        label: 'Updating Attendus...',
        showLabel: true,
      ),
      _DeferredScreenState.loading => _buildProgress(
        label: widget.loadingLabel,
      ),
    };
  }

  Widget _buildProgress({required String label, bool showLabel = false}) {
    return Center(
      child: Semantics(
        label: label,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            if (showLabel) ...[const SizedBox(height: 12), Text(label)],
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
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
            if (_recovery.canRefreshApp) ...[
              FilledButton(
                onPressed: _refreshApp,
                child: const Text('Refresh app'),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ] else
              FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

enum _DeferredScreenState { loading, recovering, loaded, error }
