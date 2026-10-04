import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

class EventAnnouncementComposer extends StatefulWidget {
  const EventAnnouncementComposer({super.key, required this.eventId});
  final String eventId;
  @override
  State<EventAnnouncementComposer> createState() =>
      _EventAnnouncementComposerState();
}

class _EventAnnouncementComposerState extends State<EventAnnouncementComposer> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _audience = 'confirmed';
  String? _preview, _job, _error;
  int _count = 0;
  bool _busy = false;
  Map<String, dynamic>? _status;
  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable(name)
        .call({'eventId': widget.eventId, ...data})
        .timeout(const Duration(seconds: 30));
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
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

  void _invalidate() {
    setState(() {
      _preview = null;
      _job = null;
      _status = null;
    });
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Text(
        'Send an event update',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        initialValue: _audience,
        decoration: const InputDecoration(labelText: 'Audience'),
        items: const [
          DropdownMenuItem(value: 'confirmed', child: Text('Confirmed')),
          DropdownMenuItem(value: 'pending', child: Text('Pending approval')),
          DropdownMenuItem(value: 'waitlisted', child: Text('Waitlisted')),
          DropdownMenuItem(value: 'attendees', child: Text('Checked in')),
        ],
        onChanged: _busy
            ? null
            : (value) {
                _audience = value!;
                _invalidate();
              },
      ),
      TextField(
        controller: _title,
        enabled: !_busy,
        maxLength: 160,
        decoration: const InputDecoration(labelText: 'Title'),
        onChanged: (_) => _invalidate(),
      ),
      TextField(
        controller: _body,
        enabled: !_busy,
        minLines: 5,
        maxLines: 12,
        maxLength: 4000,
        decoration: const InputDecoration(labelText: 'Message'),
        onChanged: (_) => _invalidate(),
      ),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (_preview != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text('This message will be queued for $_count recipients.'),
        ),
      if (_status != null)
        Text(
          'Queued: ${_status!['queued']} · Provider accepted: ${_status!['accepted']} · Failed: ${_status!['failed']} · Unreachable: ${_status!['unreachable']} · Outcome unknown: ${_status!['unknown'] ?? 0}\nProvider acceptance does not confirm delivery.',
        ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy
            ? null
            : () => _run(() async {
                if (_job != null) {
                  final result = await _call('getEventAnnouncementV1', {
                    'announcementId': _job,
                  });
                  if (mounted) setState(() => _status = result);
                } else if (_preview == null) {
                  final result = await _call('previewEventAnnouncementV1', {
                    'audience': _audience,
                    'title': _title.text,
                    'body': _body.text,
                  });
                  if (mounted) {
                    setState(() {
                      _preview = result['previewToken'];
                      _count = result['count'];
                    });
                  }
                } else {
                  final result = await _call('sendEventAnnouncementV1', {
                    'previewToken': _preview,
                  });
                  if (mounted) setState(() => _job = result['announcementId']);
                }
              }),
        child: Text(
          _busy
              ? 'Working…'
              : _job != null
              ? 'Refresh delivery status'
              : _preview == null
              ? 'Preview recipients'
              : 'Send announcement',
        ),
      ),
    ],
  );
}
