import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key, required this.eventId});
  final String eventId;
  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  final List<Map<String, dynamic>> _records = [];
  String? _cursor, _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async => Map<String, dynamic>.from(
    (await FirebaseFunctions.instance
                .httpsCallable(name)
                .call({'eventId': widget.eventId, ...data})
                .timeout(const Duration(seconds: 30)))
            .data
        as Map,
  );
  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await _call('getAttendanceHistoryV1', {
        if (_cursor != null) 'cursor': _cursor,
      });
      if (mounted) {
        setState(() {
          _records.addAll(
            (data['records'] as List).map(
              (row) => Map<String, dynamic>.from(row as Map),
            ),
          );
          _cursor = data['nextCursor'];
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FirebaseFunctionsException
              ? error.message
              : 'History unavailable. Retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _action(Map<String, dynamic> record, String action) async {
    final reason = TextEditingController();
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          action == 'identity'
              ? 'View identifying information'
              : 'Add attendance correction',
        ),
        content: TextField(
          controller: reason,
          maxLength: 500,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Reason (recorded in the audit history)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    final explanation = reason.text.trim();
    reason.dispose();
    if (proceed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (action == 'identity') {
        final result = await _call('getAttendanceHistoryIdentityV1', {
          'historyId': record['id'],
          'reason': explanation,
        });
        final identity = result['identity'] as Map;
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Recorded attendee identity'),
            content: SingleChildScrollView(
              child: SelectableText(
                'Recorded name: ${identity['recordedName'] ?? 'Unavailable'}\nRegistration name: ${identity['registrationName'] ?? 'Unavailable'}\nRegistration contact: ${identity['registrationContact'] ?? 'Unavailable'}\nOriginal account: ${identity['originalAccountId'] ?? 'Unavailable'}\n\nMissing fields are not inferred from the current profile.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      } else {
        await _call('correctAttendanceHistoryV1', {
          'historyId': record['id'],
          'reason': explanation,
          'operation': action,
        });
        _records.clear();
        _cursor = null;
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Correction recorded. Original evidence is preserved.',
              ),
            ),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FirebaseFunctionsException
              ? error.message
              : 'Request failed. Retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Attendance history')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Permanent attendance evidence. Identifying information is restricted and may have been removed following account deletion. Times below are UTC.',
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_busy) const LinearProgressIndicator(),
        for (final record in _records)
          ListTile(
            title: Text('Recorded: ${record['checkedInAt']}'),
            subtitle: Text(
              'Check-out: ${record['checkedOutAt'] ?? 'Not recorded'}\nVerification: ${record['verificationSource']}\n${(record['corrections'] as List? ?? []).map((change) => '${change['operation']}: ${change['reason'] ?? 'Updated source evidence'}').join('\n')}',
            ),
            trailing: PopupMenuButton<String>(
              enabled: !_busy,
              onSelected: (action) => _action(record, action),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'identity',
                  child: Text('View identity (audited)'),
                ),
                PopupMenuItem(
                  value: 'note',
                  child: Text('Add correction note'),
                ),
                PopupMenuItem(
                  value: 'void',
                  child: Text('Void attendance with reason'),
                ),
              ],
            ),
          ),
        if (!_busy && (_cursor != null || _records.isEmpty))
          TextButton(
            onPressed: _load,
            child: Text(_error != null ? 'Retry' : 'Load history'),
          ),
      ],
    ),
  );
}
