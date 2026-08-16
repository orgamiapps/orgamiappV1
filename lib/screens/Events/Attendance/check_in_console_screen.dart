import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:attendus/Services/attendance_check_in_service.dart';
import 'package:attendus/models/check_in_session.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/Events/Attendance/attendance_sheet_screen.dart';
import 'package:attendus/screens/Events/ticket_scanner_screen.dart';

class CheckInConsoleScreen extends StatefulWidget {
  const CheckInConsoleScreen({super.key, required this.event});

  final EventModel event;

  @override
  State<CheckInConsoleScreen> createState() => _CheckInConsoleScreenState();
}

class _CheckInConsoleScreenState extends State<CheckInConsoleScreen> {
  final AttendanceCheckInService _service = AttendanceCheckInService();
  Timer? _refreshTimer;
  CheckInSession? _session;
  VenueCredential? _venueCredential;
  bool _busy = false;
  bool _online = true;
  int _pendingScans = 0;
  bool _offlineReady = false;
  late List<String> _staffIds;

  bool get _isOwner =>
      FirebaseAuth.instance.currentUser?.uid == widget.event.customerUid;

  @override
  void initState() {
    super.initState();
    _staffIds = List<String>.from(widget.event.checkInStaff);
    _loadSession();
    _refreshTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      _refreshOperationalState();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSession() async {
    try {
      final session = await _service.findActiveSession(widget.event.id);
      if (!mounted) return;
      setState(() => _session = session);
      if (session != null) {
        await _refreshCredential();
        await _prepareOfflineKit(session, silent: true);
      }
    } catch (error) {
      _showError(error);
    }
    await _refreshConnectivity();
  }

  Future<void> _refreshOperationalState() async {
    await _refreshConnectivity();
    if (_session != null) await _refreshCredential(silent: true);
  }

  Future<void> _refreshConnectivity() async {
    final dynamic result = await Connectivity().checkConnectivity();
    final isOffline = result is List
        ? result.every((item) => item == ConnectivityResult.none)
        : result == ConnectivityResult.none;
    final pending = await _service.pendingCount();
    if (!mounted) return;
    setState(() {
      _online = !isOffline;
      _pendingScans = pending;
    });
  }

  Future<void> _refreshCredential({bool silent = false}) async {
    final session = _session;
    if (session == null ||
        !widget.event.checkInPolicy.attendeeSelfCheckInEnabled) {
      return;
    }
    try {
      final credential = await _service.mintVenueCredential(session.id);
      if (mounted) setState(() => _venueCredential = credential);
    } catch (error) {
      if (!silent) _showError(error);
    }
  }

  Future<void> _startSession() async {
    if (widget.event.checkInPolicy.needsOrganizerReview) {
      _showError('Review and save the event arrival profile first.');
      return;
    }
    await _run(() async {
      final session = await _service.startSession(widget.event.id);
      if (!mounted) return;
      setState(() => _session = session);
      await _refreshCredential();
      await _prepareOfflineKit(session);
    });
  }

  Future<void> _endSession() async {
    final session = _session;
    if (session == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End check-in session?'),
        content: const Text(
          'Venue credentials will stop working immediately. Attendance records '
          'and exports are preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep open'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End session'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await _service.endSession(session.id);
      if (mounted) {
        setState(() {
          _session = null;
          _venueCredential = null;
          _offlineReady = false;
        });
      }
    });
  }

  Future<void> _syncOffline() async {
    await _run(() async {
      final result = await _service.syncPending();
      if (!mounted) return;
      setState(() => _pendingScans = result.remaining);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Synced ${result.synced} scan${result.synced == 1 ? '' : 's'}; '
            '${result.remaining} remaining.',
          ),
        ),
      );
    });
  }

  Future<void> _prepareOfflineKit(
    CheckInSession session, {
    bool silent = false,
  }) async {
    try {
      await _service.prepareOfflineKit(
        eventId: widget.event.id,
        session: session,
        eligibility: widget.event.checkInPolicy.eligibility.value,
      );
      if (mounted) setState(() => _offlineReady = true);
    } catch (error) {
      if (!silent) _showError(error);
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    final message = error is FirebaseFunctionsException
        ? error.message ?? 'The attendance request could not be completed.'
        : error.toString().replaceFirst('Exception: ', '');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  DateTime _date(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return DateTime.tryParse(value?.toString() ?? '') ?? DateTime(1970);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _activeAttendance(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final entries = snapshot.docs
        .where((doc) => doc.data()['status'] != 'voided')
        .toList();
    entries.sort((a, b) {
      final aDate = _date(
        a.data()['checkedInAt'] ?? a.data()['attendanceDateTime'],
      );
      final bDate = _date(
        b.data()['checkedInAt'] ?? b.data()['attendanceDateTime'],
      );
      return bDate.compareTo(aDate);
    });
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Check-in Console'),
        actions: [
          if (_isOwner)
            IconButton(
              tooltip: 'Manage event staff',
              onPressed: _manageStaff,
              icon: const Icon(Icons.manage_accounts_outlined),
            ),
          IconButton(
            tooltip: 'Attendance export',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AttendanceSheetScreen(eventModel: widget.event),
              ),
            ),
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _service.watchAttendance(widget.event.id),
        builder: (context, attendanceSnapshot) {
          final attendance = attendanceSnapshot.hasData
              ? _activeAttendance(attendanceSnapshot.data!)
              : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('RegisterAttendance')
                .where('eventId', isEqualTo: widget.event.id)
                .snapshots(),
            builder: (context, registrationSnapshot) {
              final registrations = registrationSnapshot.data?.docs ?? [];
              return RefreshIndicator(
                onRefresh: _loadSession,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildStatusCard(attendance, registrations),
                    const SizedBox(height: 16),
                    if (_session == null)
                      _buildClosedCard()
                    else ...[
                      _buildCredentialCard(),
                      const SizedBox(height: 16),
                      _buildOperationsCard(),
                    ],
                    const SizedBox(height: 16),
                    _buildRosterCard(registrations, attendance),
                    const SizedBox(height: 16),
                    _buildRecentActivity(attendance),
                    const SizedBox(height: 80),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatusCard(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attendance,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> registrations,
  ) {
    final now = DateTime.now();
    final arrivalsLastMinute = attendance.where((doc) {
      final value =
          doc.data()['checkedInAt'] ?? doc.data()['attendanceDateTime'];
      return now.difference(_date(value)).inSeconds <= 60;
    }).length;
    final attendedIds = attendance
        .map((doc) => doc.data()['customerUid']?.toString())
        .whereType<String>()
        .toSet();
    final noShows = registrations.where((doc) {
      return !attendedIds.contains(doc.data()['customerUid']?.toString());
    }).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.event.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        _session == null ? 'Check-in closed' : 'Check-in live',
                        style: TextStyle(
                          color: _session == null
                              ? Colors.grey
                              : Colors.green.shade700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusChip(
                  icon: _online ? Icons.cloud_done_outlined : Icons.cloud_off,
                  label: _online ? 'Online' : 'Offline',
                  color: _online ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message: _offlineReady
                      ? 'Roster and signed-pass verifier stored on this device'
                      : 'Offline verifier is not ready',
                  child: Icon(
                    _offlineReady
                        ? Icons.offline_pin
                        : Icons.offline_bolt_outlined,
                    color: _offlineReady ? Colors.green : Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: 'Checked in',
                    value: '${attendance.length}',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Arrivals/min',
                    value: '$arrivalsLastMinute',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'RSVP',
                    value: '${registrations.length}',
                  ),
                ),
                Expanded(
                  child: _Metric(label: 'No-show', value: '$noShows'),
                ),
              ],
            ),
            if (_pendingScans > 0) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$_pendingScans offline scan${_pendingScans == 1 ? '' : 's'} waiting',
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _online ? _syncOffline : null,
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync now'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildClosedCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.door_front_door_outlined, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Ready for arrivals?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Starting a session activates venue credentials, personal passes, '
            'the roster, and the live activity feed.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _startSession,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start check-in'),
          ),
        ],
      ),
    ),
  );

  Widget _buildCredentialCard() {
    final credential = _venueCredential;
    if (!widget.event.checkInPolicy.attendeeSelfCheckInEnabled) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Venue check-in',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh credentials',
                  onPressed: _refreshCredential,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const Text(
              'Display this on-site. The QR rotates every 30 seconds and the '
              'six-character code rotates every minute.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (credential == null)
              const Padding(
                padding: EdgeInsets.all(36),
                child: CircularProgressIndicator(),
              )
            else ...[
              Semantics(
                label: 'Rotating venue check-in QR code',
                child: QrImageView(
                  data: credential.qrData,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(
                credential.code,
                style: const TextStyle(
                  fontSize: 34,
                  letterSpacing: 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'Code valid until ${DateFormat('h:mm:ss a').format(credential.codeExpiresAt.toLocal())}',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOperationsCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Door tools',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TicketScannerScreen(
                      eventId: widget.event.id,
                      eventTitle: widget.event.title,
                      sessionId: _session?.id,
                    ),
                  ),
                ),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan personal pass'),
              ),
              OutlinedButton.icon(
                onPressed: _showGuestDialog,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add guest'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _endSession,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('End session'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _buildRosterCard(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> registrations,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attendance,
  ) {
    final attended = attendance
        .map((entry) => entry.data()['customerUid']?.toString())
        .whereType<String>()
        .toSet();
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: const Text(
          'Roster',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: const Text(
          'Search and check in anyone who needs assistance.',
        ),
        children: [
          if (registrations.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No registrations yet. Staff guest check-in remains available.',
              ),
            )
          else
            ...registrations.take(200).map((doc) {
              final data = doc.data();
              final uid = data['customerUid']?.toString() ?? '';
              final name =
                  data['realName']?.toString() ??
                  data['userName']?.toString() ??
                  'Attendee';
              final checkedIn = attended.contains(uid);
              return ListTile(
                leading: CircleAvatar(
                  child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
                ),
                title: Text(name),
                subtitle: Text(checkedIn ? 'Already checked in' : 'Registered'),
                trailing: checkedIn
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : FilledButton.tonal(
                        onPressed: _session == null
                            ? null
                            : () => _checkInRoster(uid: uid, name: name),
                        child: const Text('Check in'),
                      ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildRecentActivity(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> attendance,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent activity',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (attendance.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('Arrivals will appear here in real time.'),
              ),
            )
          else
            ...attendance.take(30).map((doc) {
              final data = doc.data();
              final time = _date(
                data['checkedInAt'] ?? data['attendanceDateTime'],
              );
              final source =
                  data['source']?.toString().replaceAll('_', ' ') ?? 'check in';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(Icons.check)),
                title: Text(data['userName']?.toString() ?? 'Attendee'),
                subtitle: Text(
                  '${DateFormat('h:mm:ss a').format(time)} · $source',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'checkout') _checkout(doc.id);
                    if (action == 'void') _void(doc.id);
                  },
                  itemBuilder: (_) => [
                    if (widget.event.checkInPolicy.checkoutEnabled)
                      const PopupMenuItem(
                        value: 'checkout',
                        child: Text('Check out'),
                      ),
                    const PopupMenuItem(
                      value: 'void',
                      child: Text('Void entry'),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    ),
  );

  Future<List<String>?> _collectAnswers(String title) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('Events')
        .doc(widget.event.id)
        .collection('EventQuestions')
        .get();
    final questions = snapshot.docs;
    if (questions.isEmpty) return const [];
    if (!mounted) return null;
    final controllers = {
      for (final doc in questions) doc.id: TextEditingController(),
    };
    final answers = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: questions.map((doc) {
              final data = doc.data();
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: controllers[doc.id],
                  decoration: InputDecoration(
                    labelText:
                        '${data['questionTitle']}${data['required'] == true ? ' *' : ''}',
                    border: const OutlineInputBorder(),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final missing = questions.any(
                (doc) =>
                    doc.data()['required'] == true &&
                    controllers[doc.id]!.text.trim().isEmpty,
              );
              if (missing) return;
              Navigator.pop(
                context,
                questions
                    .map(
                      (doc) =>
                          '${doc.data()['questionTitle']}--ans--${controllers[doc.id]!.text.trim()}',
                    )
                    .toList(),
              );
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
    return answers;
  }

  Future<void> _checkInRoster({
    required String uid,
    required String name,
  }) async {
    final session = _session;
    if (session == null) return;
    final answers = await _collectAnswers('Check in $name');
    if (answers == null) return;
    await _run(() async {
      final receipt = await _service.submitCheckIn(
        eventId: widget.event.id,
        sessionId: session.id,
        credential: {
          'type': 'staff_roster',
          'attendeeId': uid,
          'displayName': name,
        },
        answers: answers,
        allowOfflineQueue: true,
      );
      _showReceipt(receipt);
      await _refreshConnectivity();
    });
  }

  Future<void> _showGuestDialog() async {
    final session = _session;
    if (session == null) return;
    final name = TextEditingController();
    final reason = TextEditingController();
    final values = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Staff-assisted guest'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full name',
                border: OutlineInputBorder(),
              ),
            ),
            if (widget.event.checkInPolicy.eligibility.value != 'open') ...[
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                decoration: const InputDecoration(
                  labelText: 'Override reason',
                  helperText: 'Required because this event is restricted.',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().length < 2) return;
              if (widget.event.checkInPolicy.eligibility.value != 'open' &&
                  reason.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(context, [name.text.trim(), reason.text.trim()]);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    name.dispose();
    reason.dispose();
    if (values == null) return;
    final answers = await _collectAnswers('Guest questions');
    if (answers == null) return;
    await _run(() async {
      final receipt = await _service.submitCheckIn(
        eventId: widget.event.id,
        sessionId: session.id,
        credential: {
          'type': 'staff_guest',
          'fullName': values[0],
          if (values[1].isNotEmpty) 'overrideReason': values[1],
        },
        answers: answers,
        allowOfflineQueue: true,
      );
      _showReceipt(receipt);
      await _refreshConnectivity();
    });
  }

  void _showReceipt(CheckInReceipt receipt) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          receipt.queuedOffline
              ? '${receipt.attendeeName} was saved offline and will sync automatically.'
              : '${receipt.attendeeName} checked in at ${DateFormat('h:mm:ss a').format(receipt.checkedInAt.toLocal())}.',
        ),
        backgroundColor: receipt.queuedOffline
            ? Colors.orange.shade800
            : Colors.green.shade700,
      ),
    );
  }

  Future<void> _checkout(String attendanceId) async {
    final session = _session;
    if (session == null) return;
    await _run(
      () => _service.checkout(
        eventId: widget.event.id,
        sessionId: session.id,
        attendanceId: attendanceId,
      ),
    );
  }

  Future<void> _void(String attendanceId) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Void attendance entry'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Reason',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Void'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null) return;
    await _run(
      () => _service.voidAttendance(attendanceId: attendanceId, reason: reason),
    );
  }

  Future<void> _manageStaff() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Event-day staff access'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Co-hosts already have console access. Add an account email or '
                  'user ID for door staff; they cannot edit the event.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Email or user ID',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ..._staffIds.map(
                  (uid) => ListTile(
                    dense: true,
                    title: Text(uid),
                    trailing: IconButton(
                      tooltip: 'Remove access',
                      onPressed: () async {
                        final next = List<String>.from(_staffIds)..remove(uid);
                        await _saveStaff(next);
                        setDialogState(() {});
                      },
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final input = controller.text.trim();
                if (input.isEmpty) return;
                var uid = input;
                if (input.contains('@')) {
                  final match = await FirebaseFirestore.instance
                      .collection('Customers')
                      .where('email', isEqualTo: input.toLowerCase())
                      .limit(1)
                      .get();
                  if (match.docs.isEmpty) {
                    _showError('No Attendus account uses that email.');
                    return;
                  }
                  uid = match.docs.first.id;
                }
                final next = {..._staffIds, uid}.toList();
                await _saveStaff(next);
                controller.clear();
                setDialogState(() {});
              },
              icon: const Icon(Icons.add),
              label: const Text('Add staff'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _saveStaff(List<String> staff) async {
    await FirebaseFirestore.instance
        .collection('Events')
        .doc(widget.event.id)
        .update({'checkInStaff': staff});
    if (mounted) setState(() => _staffIds = staff);
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
      ),
      Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
