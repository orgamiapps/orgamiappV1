import 'discovery_history_port.dart';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import '../models/discovery_route_state.dart';

class DiscoveryHistoryBackend implements DiscoveryHistoryPort {
  DiscoveryHistoryBackend({required this.onRestore, required this.isActive}) {
    _listener = ((web.Event event) {
      final uri = currentUri;
      if (!DiscoveryRouteState.matches(uri)) return;
      final record = _record;
      // Only our own filter entries bypass Navigator. Event/community entries
      // remain owned by Flutter; restoring beneath them must not consume Back.
      if (record != null && isActive()) event.stopImmediatePropagation();
      onRestore(uri, scroll);
    }).toJS;
    web.window.addEventListener('popstate', _listener, true.toJS);
  }
  final void Function(Uri, double) onRestore;
  final bool Function() isActive;
  late final JSFunction _listener;
  @override
  Uri get currentUri => Uri.parse(web.window.location.href);
  Map<String, dynamic> get _state {
    final value = web.window.history.state.dartify();
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  Map? get _record => _state['attendusDiscovery'] is Map
      ? _state['attendusDiscovery'] as Map
      : null;
  @override
  double get scroll {
    final value = _record?['scroll'];
    return value is num && value.isFinite && value >= 0 ? value.toDouble() : 0;
  }

  @override
  bool get available => true;
  @override
  void write(Uri uri, double offset, {required bool push}) {
    if (!isActive()) return;
    final state = _state;
    final old = _record;
    state['attendusDiscovery'] = {
      'id': push || old == null
          ? DateTime.now().microsecondsSinceEpoch.toString()
          : old['id'],
      'scroll': offset.isFinite && offset >= 0 ? offset : 0,
    };
    if (push) {
      web.window.history.pushState(state.jsify(), '', uri.toString());
    } else {
      web.window.history.replaceState(state.jsify(), '', uri.toString());
    }
  }

  @override
  void dispose() =>
      web.window.removeEventListener('popstate', _listener, true.toJS);
}
