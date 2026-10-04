import 'package:attendus/screens/Events/premium_event_creation_wrapper.dart'
    deferred as premium_creation;
import 'package:attendus/widgets/deferred_screen_loader.dart';
import 'package:flutter/material.dart';

/// Keeps event creation and its dashboard dependency outside the initial web
/// bundle while providing one route target for pending-auth intent resumption.
class DeferredPremiumEventCreation extends StatelessWidget {
  const DeferredPremiumEventCreation({
    super.key,
    this.loadLibraryOverride,
    this.builderOverride,
  });

  final Future<void> Function()? loadLibraryOverride;
  final WidgetBuilder? builderOverride;

  @override
  Widget build(BuildContext context) => DeferredScreenLoader(
    loadLibrary: loadLibraryOverride ?? premium_creation.loadLibrary,
    recoveryKey: 'premium-event-creation',
    loadingLabel: 'Loading event creation',
    builder: () =>
        builderOverride?.call(context) ??
        premium_creation.PremiumEventCreationWrapper(),
  );
}
