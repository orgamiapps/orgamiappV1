import 'discovery_history_port.dart';
import 'dart:async';
import 'package:flutter/widgets.dart';
import '../models/discovery_route_state.dart';
import 'discovery_history_native.dart'
    if (dart.library.js_interop) 'discovery_history_web.dart';

class DiscoveryHistoryCoordinator {
  DiscoveryHistoryCoordinator({
    required this.snapshot,
    required this.restore,
    required this.scrollController,
    required bool Function() isActive,
    DiscoveryHistoryPort Function(void Function(Uri, double), bool Function())?
    createBackend,
  }) {
    _isActive = isActive;
    _backend =
        createBackend?.call(_restore, isActive) ??
        DiscoveryHistoryBackend(onRestore: _restore, isActive: isActive);
  }
  final DiscoveryRouteState Function() snapshot;
  final Future<void> Function(DiscoveryRouteState) restore;
  final ScrollController? Function() scrollController;
  late final DiscoveryHistoryPort _backend;
  late final bool Function() _isActive;
  Timer? _timer;
  Timer? _scrollTimer;
  Uri? _lastUri;
  bool _restoring = false;
  bool _disposed = false;
  int _generation = 0;

  Future<void> initialize() async {
    if (!_backend.available) return;
    if (DiscoveryRouteState.matches(_backend.currentUri)) {
      await _restore(_backend.currentUri, _backend.scroll);
    } else {
      _lastUri = snapshot().uri;
      _backend.write(_lastUri!, offset, push: false);
    }
  }

  ScrollPosition? get _readyPosition {
    final controller = scrollController();
    if (controller == null || controller.positions.length != 1) return null;
    final position = controller.position;
    return position.hasPixels && position.hasContentDimensions
        ? position
        : null;
  }

  double get offset => _readyPosition?.pixels ?? 0;
  void schedule() {
    if (_disposed || _restoring || !_backend.available || !_isActive()) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), flush);
  }

  void flush() {
    if (_disposed || _restoring || !_backend.available || !_isActive()) return;
    _timer?.cancel();
    _scrollTimer?.cancel();
    _scrollTimer = null;
    final next = snapshot().uri;
    if (_lastUri != next) {
      if (_lastUri != null) _backend.write(_lastUri!, offset, push: false);
      _backend.write(next, 0, push: true);
      _lastUri = next;
      _readyPosition?.jumpTo(0);
    } else {
      _backend.write(next, offset, push: false);
    }
  }

  Future<void> _restore(Uri uri, double offset) async {
    final generation = ++_generation;
    _timer?.cancel();
    _restoring = true;
    _lastUri = DiscoveryRouteState.fromUri(uri).uri;
    try {
      await restore(DiscoveryRouteState.fromUri(uri));
      // Attachment precedes viewport layout. Allow a short, bounded layout
      // window; an unlaid-out/removed viewport must not erase its saved offset.
      for (var frame = 0; frame < 3; frame++) {
        await WidgetsBinding.instance.endOfFrame;
        if (_disposed || generation != _generation) return;
        final position = _readyPosition;
        if (position == null) continue;
        position.jumpTo(offset.clamp(0, position.maxScrollExtent));
        if (_isActive()) {
          _backend.write(_lastUri!, this.offset, push: false);
        }
        return;
      }
    } finally {
      if (generation == _generation) _restoring = false;
    }
  }

  void scheduleScroll() {
    if (_disposed || _restoring || !_backend.available || !_isActive()) return;
    _scrollTimer ??= Timer(const Duration(milliseconds: 500), saveScroll);
  }

  void saveScroll() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
    if (!_disposed &&
        !_restoring &&
        _lastUri != null &&
        _readyPosition != null &&
        _isActive()) {
      _backend.write(_lastUri!, offset, push: false);
    }
  }

  void dispose() {
    saveScroll();
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _backend.dispose();
  }
}
