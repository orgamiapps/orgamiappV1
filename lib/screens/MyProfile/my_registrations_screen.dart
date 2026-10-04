import 'package:attendus/Services/admission_selection.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:attendus/models/event_schedule.dart';
import 'package:attendus/widgets/deferred_shared_event_screen.dart';

class MyRegistrationsScreen extends StatefulWidget {
  const MyRegistrationsScreen({super.key});
  @override
  State<MyRegistrationsScreen> createState() => _MyRegistrationsScreenState();
}

class _MyRegistrationsScreenState extends State<MyRegistrationsScreen> {
  final List<Map<String, dynamic>> _rows = [];
  String? _cursor;
  String? _error;
  bool _busy = false;
  bool _history = false;
  final _requests = AdmissionRequestGuard();
  String? _uid;
  StreamSubscription<User?>? _auth;
  @override
  void initState() {
    super.initState();
    _auth = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) return;
      _requests.invalidate();
      setState(() {
        _uid = user?.uid;
        _rows.clear();
        _cursor = null;
        _error = null;
        _busy = false;
      });
      if (_uid != null) _load();
    });
  }

  @override
  void dispose() {
    _requests.invalidate();
    _auth?.cancel();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final uid = _uid;
    if (uid == null) return;
    final generation = _requests.begin(uid);
    bool current() =>
        mounted &&
        _requests.accepts(generation, FirebaseAuth.instance.currentUser?.uid);
    setState(() {
      if (!more) {
        _rows.clear();
        _cursor = null;
      }
      _busy = true;
      _error = null;
    });
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('listMyAdmissionsV1')
          .call({'history': _history, if (more) 'cursor': _cursor})
          .timeout(const Duration(seconds: 30));
      if (!current()) return;
      setState(() {
        if (!more) _rows.clear();
        _rows.addAll(
          (result.data['admissions'] as List).map(
            (row) => Map<String, dynamic>.from(row as Map),
          ),
        );
        _cursor = result.data['nextCursor'];
      });
    } catch (_) {
      if (current()) {
        setState(
          () => _error = 'Registrations could not be loaded. Please retry.',
        );
      }
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Registrations and tickets')),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Show past events'),
            value: _history,
            onChanged: _busy
                ? null
                : (value) {
                    _history = value;
                    _load();
                  },
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            ListTile(
              title: Text(_error!),
              trailing: TextButton(
                onPressed: _busy ? null : _load,
                child: const Text('Retry'),
              ),
            ),
          if (!_busy && _rows.isEmpty && _error == null)
            const ListTile(
              title: Text('No registrations yet'),
              subtitle: Text(
                'RSVPs, tickets, pending requests and waitlist places will appear here.',
              ),
            ),
          for (final row in _rows)
            Card(
              child: ListTile(
                title: Text(row['title'] as String),
                subtitle: Text(
                  '${row['ticketId'] == null ? 'RSVP' : 'Ticket'} · ${row['status']} · ${row['start'] == null ? 'Schedule needs confirmation' : EventSchedule(DateTime.parse(row['start']), null, row['timeZone']).cardLabel}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DeferredSharedEventScreen(
                      eventId: row['eventId'],
                      registrationId: row['registrationId'],
                      ticketId: row['ticketId'],
                    ),
                  ),
                ),
              ),
            ),
          if (_cursor != null)
            TextButton(
              onPressed: _busy ? null : () => _load(more: true),
              child: const Text('Load more'),
            ),
        ],
      ),
    ),
  );
}
