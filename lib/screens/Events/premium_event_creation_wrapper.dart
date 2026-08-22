import 'package:attendus/screens/Events/create_event_screen.dart';
import 'package:attendus/screens/Events/edit_event_screen.dart';
import 'package:attendus/screens/Events/event_creation_wizard_screen.dart';
import 'package:attendus/Services/event_wizard_service.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/models/event_wizard_model.dart';
import 'package:flutter/material.dart';
import 'package:attendus/Services/account_access_service.dart';
import 'package:attendus/widgets/account_required_sheet.dart';
import 'package:attendus/Services/product_funnel_service.dart';

Future<void> openDuplicateEventWizard(
  BuildContext context,
  EventModel event,
) async {
  EventWizardService service;
  try {
    service = EventWizardService();
  } catch (_) {
    return;
  }
  if (await service.experienceVersion() != 2) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event duplication is coming soon.')),
      );
    }
    return;
  }
  try {
    final draft = await service.duplicateEvent(event.id);
    ProductFunnelService().record(
      'event_wizard_duplicate_started',
      dimensions: {'mode': 'duplicate'},
    );
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            EventCreationWizardScreen(initialDraft: draft, service: service),
      ),
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not duplicate this event.')),
      );
    }
  }
}

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
    return AccountRequiredGate(
      feature: AccountFeature.createEvent,
      child: EventCreationExperienceGate(
        selectedDateTime: selectedDateTime,
        eventDurationHours: eventDurationHours,
        preselectedOrganizationId: preselectedOrganizationId,
        forceOrganizationEvent: forceOrganizationEvent,
      ),
    );
  }
}

/// Fail-closed rollout gate for the additive event-creation experience.
/// Missing, invalid, or unavailable configuration always preserves V1.
class EventCreationExperienceGate extends StatefulWidget {
  const EventCreationExperienceGate({
    super.key,
    this.selectedDateTime,
    this.eventDurationHours,
    this.preselectedOrganizationId,
    this.forceOrganizationEvent = false,
    this.event,
  });

  final DateTime? selectedDateTime;
  final int? eventDurationHours;
  final String? preselectedOrganizationId;
  final bool forceOrganizationEvent;
  final EventModel? event;

  @override
  State<EventCreationExperienceGate> createState() =>
      _EventCreationExperienceGateState();
}

class _EventCreationExperienceGateState
    extends State<EventCreationExperienceGate> {
  late final Future<int> _version;
  EventWizardService? _service;
  Future<EventWizardDraft>? _editDraft;

  @override
  void initState() {
    super.initState();
    try {
      _service = EventWizardService();
      _version = _service!.experienceVersion();
    } catch (_) {
      _version = Future.value(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_service == null) {
      return widget.event != null
          ? EditEventScreen(eventModel: widget.event!)
          : CreateEventScreen(
              selectedDateTime: widget.selectedDateTime,
              eventDurationHours: widget.eventDurationHours,
              preselectedOrganizationId: widget.preselectedOrganizationId,
              forceOrganizationEvent: widget.forceOrganizationEvent,
            );
    }
    return FutureBuilder<int>(
      future: _version,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == 2) {
          if (widget.event != null) {
            _editDraft ??= _service!.createEditDraft(widget.event!.id);
            return FutureBuilder<EventWizardDraft>(
              future: _editDraft,
              builder: (context, draftSnapshot) {
                if (!draftSnapshot.hasData) {
                  if (draftSnapshot.hasError) {
                    return EditEventScreen(eventModel: widget.event!);
                  }
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                return EventCreationWizardScreen(
                  event: widget.event,
                  initialDraft: draftSnapshot.data,
                );
              },
            );
          }
          return EventCreationWizardScreen(
            selectedDateTime: widget.selectedDateTime,
            eventDurationHours: widget.eventDurationHours,
            preselectedOrganizationId: widget.preselectedOrganizationId,
            forceOrganizationEvent: widget.forceOrganizationEvent,
          );
        }
        if (widget.event != null) {
          return EditEventScreen(eventModel: widget.event!);
        }
        return CreateEventScreen(
          selectedDateTime: widget.selectedDateTime,
          eventDurationHours: widget.eventDurationHours,
          preselectedOrganizationId: widget.preselectedOrganizationId,
          forceOrganizationEvent: widget.forceOrganizationEvent,
        );
      },
    );
  }
}
