import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:attendus/models/event_model.dart';

class DeleteEventDialoge extends StatefulWidget {
  const DeleteEventDialoge({super.key, required this.singleEvent});
  final EventModel singleEvent;
  @override
  State<DeleteEventDialoge> createState() => _DeleteEventDialogeState();
}

class _DeleteEventDialogeState extends State<DeleteEventDialoge> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _preview;
  int? _affected;
  String _scope = 'this_occurrence';
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _apply(bool delete) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!delete && _preview == null) {
        final result = await FirebaseFunctions.instance
            .httpsCallable('previewEventCancellationV1')
            .call({'eventId': widget.singleEvent.id, 'recurrenceScope': _scope})
            .timeout(const Duration(seconds: 120));
        if (mounted) {
          setState(() {
            _preview = result.data['previewToken'];
            _affected = result.data['count'];
          });
        }
        return;
      }
      await FirebaseFunctions.instance
          .httpsCallable(delete ? 'deleteEmptyEventV1' : 'cancelEventV1')
          .call({
            'eventId': widget.singleEvent.id,
            'reason': _reason.text,
            'previewToken': _preview,
            'expectedEventRevision': widget.singleEvent.eventRevision,
          })
          .timeout(const Duration(seconds: 30));
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (error is FirebaseFunctionsException &&
          ['aborted', 'failed-precondition'].contains(error.code)) {
        _preview = null;
        _affected = null;
      }
      if (mounted) {
        setState(
          () => _error = error is FirebaseFunctionsException
              ? error.message
              : 'Request did not finish. Retry safely.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cancel event',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            DropdownButton<String>(
              value: _scope,
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
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      _scope = value!;
                      _preview = null;
                      _affected = null;
                    }),
            ),
            if (_affected != null)
              Text(
                '$_affected active registrations across the selected occurrences will be notified.',
              ),
            const Text(
              'The event page, registrations, tickets and attendance history will remain. Active registrants will receive an update. Refunds require separate organizer action.',
            ),
            TextField(
              controller: _reason,
              enabled: !_busy,
              maxLength: 1000,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Reason shared with attendees',
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: const Text('Keep event'),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _apply(false),
                  child: Text(
                    _busy
                        ? 'Working...'
                        : _preview == null
                        ? 'Review affected attendees'
                        : 'Confirm cancellation',
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _apply(true),
                  child: const Text('Delete empty event only'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
