import 'package:attendus/Services/event_lifecycle_store.dart';
import 'package:flutter/widgets.dart';

/// Registers a surface's source IDs and rebuilds it when their availability
/// changes. Pass unfiltered IDs so cancelled history can remain subscribed.
class EventLifecycleScope extends StatefulWidget {
  const EventLifecycleScope({
    super.key,
    required this.eventIds,
    required this.builder,
    this.store,
  });

  final Iterable<String> eventIds;
  final Widget Function(BuildContext, EventLifecycleStore) builder;
  final EventLifecycleStore? store;

  @override
  State<EventLifecycleScope> createState() => _EventLifecycleScopeState();
}

class _EventLifecycleScopeState extends State<EventLifecycleScope> {
  late EventLifecycleStore _store;
  late EventLifecycleLease _lease;

  void _attach() {
    _store = widget.store ?? EventLifecycleStore.instance;
    _lease = _store.retain(widget.eventIds);
    _store.addListener(_changed);
  }

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant EventLifecycleScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _store.removeListener(_changed);
      _lease.dispose();
      _attach();
    } else {
      _lease.update(widget.eventIds);
    }
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    _lease.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _store);
}
