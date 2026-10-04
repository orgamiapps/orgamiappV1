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

/// Canonical server-authorized persistence for every event entry point.
/// Presentation rollout configuration never selects a direct Firestore writer.
class EventCreationExperienceGate extends StatefulWidget {
  const EventCreationExperienceGate({
    super.key,
    this.selectedDateTime,
    this.eventDurationHours,
    this.preselectedOrganizationId,
    this.forceOrganizationEvent = false,
    this.event,
    this.service,
    this.editDraftLoader,
  });

  final DateTime? selectedDateTime;
  final int? eventDurationHours;
  final String? preselectedOrganizationId;
  final bool forceOrganizationEvent;
  final EventModel? event;
  final EventWizardRepository? service;
  final Future<EventWizardDraft> Function(String eventId)? editDraftLoader;

  @override
  State<EventCreationExperienceGate> createState() =>
      _EventCreationExperienceGateState();
}

class _EventCreationExperienceGateState
    extends State<EventCreationExperienceGate> {
  EventWizardRepository? _service;
  Future<EventWizardDraft>? _editDraft;
  Object? _initializationError;
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  void _initialize() {
    try {
      _service = widget.service ?? EventWizardService();
      _initializationError = null;
      if (widget.event != null) {
        final load =
            widget.editDraftLoader ??
            (_service as EventWizardService).createEditDraft;
        _editDraft = load(widget.event!.id);
        // A retry can fail before the next build attaches FutureBuilder.
        // Mark the future handled immediately; FutureBuilder still renders its error.
        _editDraft!.ignore();
      }
    } catch (error) {
      _initializationError = error;
    }
  }

  Widget _unavailable() => Scaffold(
    appBar: AppBar(title: const Text('Event editor')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'The event editor is unavailable. Reconnect or sign in again, then retry. Your published event has not changed.',
            ),
            TextButton(
              onPressed: () => setState(_initialize),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (_service == null || _initializationError != null) return _unavailable();
    if (widget.event != null) {
      return FutureBuilder<EventWizardDraft>(
        future: _editDraft,
        builder: (context, snapshot) {
          if (snapshot.hasError) return _unavailable();
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return EventCreationWizardScreen(
            event: widget.event,
            initialDraft: snapshot.data,
            service: _service,
          );
        },
      );
    }
    return EventCreationWizardScreen(
      selectedDateTime: widget.selectedDateTime,
      eventDurationHours: widget.eventDurationHours,
      preselectedOrganizationId: widget.preselectedOrganizationId,
      forceOrganizationEvent: widget.forceOrganizationEvent,
      service: _service,
    );
  }
}
