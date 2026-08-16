import 'package:attendus/screens/Events/shared_event_screen.dart'
    deferred as shared_event;
import 'package:attendus/widgets/deferred_screen_loader.dart';
import 'package:flutter/material.dart';

class DeferredSharedEventScreen extends StatelessWidget {
  final String eventId;

  const DeferredSharedEventScreen({super.key, required this.eventId});

  @override
  Widget build(BuildContext context) {
    return DeferredScreenLoader(
      loadLibrary: shared_event.loadLibrary,
      recoveryKey: 'shared-event',
      loadingLabel: 'Opening event',
      builder: () => shared_event.SharedEventScreen(eventId: eventId),
    );
  }
}
