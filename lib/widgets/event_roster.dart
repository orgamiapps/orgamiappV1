import 'package:attendus/Services/artifact_download_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:attendus/screens/Events/Attendance/attendance_history_screen.dart';
import 'package:attendus/Services/event_export_service.dart';

class EventRoster extends StatefulWidget {
  const EventRoster({
    super.key,
    required this.eventId,
    required this.onCheckIn,
    required this.onDecision,
    required this.canCheckIn,
  });
  final String eventId;
  final Future<void> Function(Map<String, dynamic>) onCheckIn;
  final Future<void> Function(String, String) onDecision;
  final bool canCheckIn;
  @override
  State<EventRoster> createState() => _EventRosterState();
}

class _EventRosterState extends State<EventRoster> {
  final _search = TextEditingController();
  final List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _summary = {};
  String _registration = 'all', _attendance = 'all';
  String? _cursor, _error;
  final _exportService = EventExportService();
  bool _loading = false, _manager = false;
  int _generation = 0;
  int _matchingCount = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _search.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _filters => {
    'eventId': widget.eventId,
    'query': _search.text.trim(),
    'registrationStatus': _registration,
    'attendanceStatus': _attendance,
  };
  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> args,
  ) async {
    final response = await FirebaseFunctions.instance
        .httpsCallable(name)
        .call(args)
        .timeout(const Duration(seconds: 120));
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) {
        _rows.clear();
        _cursor = null;
      }
    });
    try {
      final result = await _call('listEventRosterV2', {
        ..._filters,
        if (more) 'cursor': _cursor,
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        _rows.addAll(
          (result['rows'] as List).map(
            (row) => Map<String, dynamic>.from(row as Map),
          ),
        );
        _cursor = result['nextCursor'];
        _summary = Map<String, dynamic>.from(result['summary'] as Map);
        _matchingCount =
            (result['matchingCount'] as num?)?.toInt() ?? _rows.length;
        _manager = (result['permissions'] as Map)['manageEvent'] == true;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = error is FirebaseFunctionsException
              ? error.message
              : 'Roster unavailable. Retry.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _export() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final outcome = await _exportService.download(
        widget.eventId,
        sharePositionOrigin: artifactShareOrigin(context),
        query: _search.text.trim(),
        registrationStatus: _registration,
        attendanceStatus: _attendance,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(outcome.message)));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Event roster',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: _loading ? null : _load,
                tooltip: 'Refresh roster',
                icon: const Icon(Icons.refresh),
              ),
              if (_manager)
                IconButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AttendanceHistoryScreen(eventId: widget.eventId),
                    ),
                  ),
                  tooltip: 'Attendance history',
                  icon: const Icon(Icons.history),
                ),
              if (_manager)
                IconButton(
                  onPressed: _loading ? null : _export,
                  tooltip: 'Export all matching records',
                  icon: const Icon(Icons.download),
                ),
            ],
          ),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (final entry in _summary.entries)
                if (entry.value != null)
                  Text(
                    '${switch (entry.key) {
                      'noShow' => 'No-shows',
                      'inside' => 'Currently inside',
                      _ => entry.key[0].toUpperCase() + entry.key.substring(1),
                    }}: ${entry.value}',
                  ),
            ],
          ),
          Text('${_rows.length} of $_matchingCount matching attendees'),
          TextField(
            controller: _search,
            enabled: !_loading,
            decoration: InputDecoration(
              labelText: 'Name, exact email, or #ticket code',
              suffixIcon: IconButton(
                onPressed: _loading
                    ? null
                    : () {
                        _load();
                      },
                icon: const Icon(Icons.search),
              ),
            ),
            onSubmitted: (_) {
              _load();
            },
          ),
          Wrap(
            spacing: 16,
            children: [
              DropdownButton<String>(
                value: _registration,
                items: [
                  for (final value in [
                    'all',
                    'confirmed',
                    'pending',
                    'waitlisted',
                    'cancelled',
                  ])
                    DropdownMenuItem(
                      value: value,
                      child: Text(value == 'all' ? 'All registrations' : value),
                    ),
                ],
                onChanged: _loading
                    ? null
                    : (value) {
                        _registration = value!;

                        _load();
                      },
              ),
              DropdownButton<String>(
                value: _attendance,
                items: [
                  for (final value in [
                    'all',
                    'not_arrived',
                    'checked_in',
                    'checked_out',
                  ])
                    DropdownMenuItem(
                      value: value,
                      child: Text(
                        value == 'all'
                            ? 'All attendance'
                            : value.replaceAll('_', ' '),
                      ),
                    ),
                ],
                onChanged: _loading
                    ? null
                    : (value) {
                        _attendance = value!;

                        _load();
                      },
              ),
            ],
          ),
          if (_error != null)
            Row(
              children: [
                Expanded(child: Text(_error!)),
                TextButton(
                  onPressed: _loading ? null : _load,
                  child: const Text('Retry'),
                ),
              ],
            ),
          if (_loading) const LinearProgressIndicator(),
          if (!_loading && _rows.isEmpty && _error == null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No matching attendees.'),
            ),
          for (final row in _rows)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(row['name'] as String? ?? 'Attendee'),
              subtitle: Text(
                '${row['status']} · ${row['attendanceStatus']}'.replaceAll(
                  '_',
                  ' ',
                ),
              ),
              trailing:
                  _manager && ['pending', 'waitlisted'].contains(row['status'])
                  ? PopupMenuButton<String>(
                      enabled: !_loading,
                      onSelected: (action) async {
                        await widget.onDecision(
                          row['registrationId'] as String,
                          action,
                        );
                        await _load();
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: row['status'] == 'waitlisted'
                              ? 'promote'
                              : 'approve',
                          child: const Text('Approve / offer place'),
                        ),
                        const PopupMenuItem(
                          value: 'decline',
                          child: Text('Decline'),
                        ),
                      ],
                    )
                  : row['attendanceStatus'] == 'not_arrived' &&
                        row['status'] == 'confirmed'
                  ? TextButton(
                      onPressed: !_loading && widget.canCheckIn
                          ? () async {
                              await widget.onCheckIn(row);
                              await _load();
                            }
                          : null,
                      child: const Text('Check in'),
                    )
                  : null,
            ),
          if (_cursor != null)
            TextButton(
              onPressed: _loading ? null : () => _load(more: true),
              child: const Text('Load more'),
            ),
        ],
      ),
    ),
  );
}
