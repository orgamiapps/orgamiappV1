import 'package:attendus/screens/Events/create_event_screen.dart';
import 'package:flutter/material.dart';

/// Entry point for event creation.
///
/// The class name is retained to avoid changing existing navigation call sites,
/// but event creation is available to every signed-in user regardless of their
/// subscription tier.
class PremiumEventCreationWrapper extends StatelessWidget {
  final DateTime? selectedDateTime;
  final int? eventDurationHours;
  final String? preselectedOrganizationId;
  final bool forceOrganizationEvent;

  const PremiumEventCreationWrapper({
    super.key,
    this.selectedDateTime,
    this.eventDurationHours,
    this.preselectedOrganizationId,
    this.forceOrganizationEvent = false,
  });

  @override
  Widget build(BuildContext context) {
    return CreateEventScreen(
      selectedDateTime: selectedDateTime,
      eventDurationHours: eventDurationHours,
      preselectedOrganizationId: preselectedOrganizationId,
      forceOrganizationEvent: forceOrganizationEvent,
    );
  }
}
