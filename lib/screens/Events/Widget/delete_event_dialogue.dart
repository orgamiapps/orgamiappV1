import 'package:attendus/Services/event_removal_service.dart';
import 'package:attendus/models/event_model.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

Future<EventRemovalResult?> showEventRemovalDialog(
  BuildContext context,
  EventModel event, {
  bool preferCancellation = false,
}) => showDialog<EventRemovalResult>(
  context: context,
  barrierDismissible: false,
  builder: (_) => DeleteEventDialoge(
    singleEvent: event,
    preferCancellation: preferCancellation,
  ),
);

class DeleteEventDialoge extends StatefulWidget {
  const DeleteEventDialoge({
    super.key,
    required this.singleEvent,
    this.preferCancellation = false,
    this.service,
  });
  final EventModel singleEvent;
  final bool preferCancellation;
  final EventRemovalService? service;
  @override
  State<DeleteEventDialoge> createState() => _DeleteEventDialogeState();
}

class _DeleteEventDialogeState extends State<DeleteEventDialoge> {
  final _reason = TextEditingController();
  late final EventRemovalService _service =
      widget.service ?? EventRemovalService();
  String _requestId = EventRemovalService.newRequestId();
  EventRemovalEligibility? _eligibility;
  EventCancellationPreview? _preview;
  bool _busy = false;
  bool _checking = true;
  bool _delete = true;
  bool _uncertain = false;
  String? _error;
  String _scope = 'this_occurrence';

  @override
  void initState() {
    super.initState();
    _checkEligibility();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _checkEligibility({String? explanation}) async {
    setState(() {
      _checking = true;
      _eligibility = null;
      _error = explanation;
    });
    try {
      final eligibility = await _service.eligibility(widget.singleEvent.id);
      if (!mounted) return;
      setState(() {
        _eligibility = eligibility;
        _delete = eligibility.canDelete && !widget.preferCancellation;
        _preview = null;
        _uncertain = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  String _errorMessage(Object error) {
    if (EventRemovalService.isUncertain(error)) {
      return _uncertain
          ? 'The server has not confirmed the outcome yet. Retry to check the same request safely.'
          : 'Could not connect. Check your connection and try again.';
    }
    if (error is FirebaseFunctionsException) {
      return error.message ?? 'Could not remove this event. Please try again.';
    }
    return 'Could not complete this request. Please try again.';
  }

  Future<void> _apply() async {
    if (_busy || _checking || _eligibility == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    var mutationStarted = false;
    try {
      if (!_delete && _preview == null) {
        final preview = await _service.preview(widget.singleEvent.id, _scope);
        if (mounted) setState(() => _preview = preview);
        return;
      }
      mutationStarted = true;
      final result = _delete
          ? await _service.delete(
              eventId: widget.singleEvent.id,
              expectedEventRevision: _eligibility!.eventRevision,
              requestId: _requestId,
            )
          : await _service.cancel(
              eventId: widget.singleEvent.id,
              expectedEventRevision: _eligibility!.eventRevision,
              requestId: _requestId,
              previewToken: _preview!.token,
              reason: _reason.text.trim(),
            );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _uncertain = false;
      });
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      if (error is FirebaseFunctionsException &&
          const ['aborted', 'failed-precondition'].contains(error.code)) {
        _requestId = EventRemovalService.newRequestId();
        await _checkEligibility(
          explanation:
              'The event changed. Review its current details before continuing.',
        );
      } else {
        setState(() {
          _uncertain =
              mutationStarted && EventRemovalService.isUncertain(error);
          _error = _errorMessage(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && !_uncertain,
    child: Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _checking
                    ? 'Checking event…'
                    : _delete
                    ? 'Delete event'
                    : 'Cancel event',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(
                widget.singleEvent.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (_checking)
                const Center(child: CircularProgressIndicator())
              else if (_eligibility != null) ...[
                if (_delete)
                  const Text(
                    'Permanently delete this event? It will disappear from Discover and other event lists. This cannot be undone.',
                  )
                else ...[
                  if (!_eligibility!.canDelete)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'This event has registrations, tickets, payments, or attendance history. Cancel it to preserve those records.',
                      ),
                    ),
                  const Text(
                    'The event will leave active event lists. Its page, registrations, tickets and attendance history will remain. Active registrants will receive an update. Refunds require separate organizer action.',
                  ),
                  if (widget.singleEvent.seriesId?.isNotEmpty == true)
                    DropdownButton<String>(
                      value: _scope,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(
                          value: 'this_occurrence',
                          child: Text('This occurrence'),
                        ),
                        DropdownMenuItem(
                          value: 'this_and_future',
                          child: Text('This and future occurrences'),
                        ),
                        DropdownMenuItem(
                          value: 'entire_series',
                          child: Text('Entire series'),
                        ),
                      ],
                      onChanged: _busy || _uncertain
                          ? null
                          : (value) => setState(() {
                              _scope = value!;
                              _preview = null;
                            }),
                    ),
                  TextField(
                    controller: _reason,
                    enabled: !_busy && !_uncertain,
                    maxLength: 1000,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Reason shared with attendees',
                    ),
                  ),
                  if (_preview != null)
                    Text(
                      '${_preview!.registrationCount} active registrations across the selected occurrences will be notified.',
                    ),
                ],
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    key: const Key('event-removal-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  TextButton(
                    onPressed: _busy || _uncertain
                        ? null
                        : () => Navigator.pop(context),
                    child: const Text('Keep event'),
                  ),
                  if (!_checking && _eligibility == null)
                    FilledButton(
                      onPressed: _checkEligibility,
                      child: const Text('Try again'),
                    )
                  else if (!_checking)
                    FilledButton(
                      onPressed: _busy ? null : _apply,
                      child: Text(
                        _busy
                            ? (!_delete && _preview == null
                                  ? 'Reviewing attendees…'
                                  : _delete
                                  ? 'Deleting event…'
                                  : 'Cancelling event…')
                            : _uncertain
                            ? 'Retry same request'
                            : _delete
                            ? 'Delete event'
                            : _preview == null
                            ? 'Review affected attendees'
                            : 'Cancel event',
                      ),
                    ),
                  if (!_checking &&
                      _eligibility?.canDelete == true &&
                      !_busy &&
                      !_uncertain)
                    TextButton(
                      onPressed: () => setState(() {
                        _delete = !_delete;
                        _preview = null;
                      }),
                      child: Text(
                        _delete ? 'Cancel instead' : 'Delete instead',
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
