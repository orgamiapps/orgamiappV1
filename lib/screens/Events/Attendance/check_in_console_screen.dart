import 'package:attendus/Services/public_profile_service.dart';
import 'package:attendus/widgets/event_roster.dart';
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
  String _controlStatus = 'scheduled';
  int _pendingScans = 0;
  int _rejectedScans = 0;
  bool _offlineReady = false;
  Map<String, dynamic> _kitStatus = {};
  late List<String> _staffIds;

  bool _serverManager = false;
  String? _capabilityUid;
  bool get _isOwner =>
      _serverManager &&
      _capabilityUid == FirebaseAuth.instance.currentUser?.uid;

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
    unawaited(_refreshStaffNames().catchError((Object _) {}));
    try {
      await _refreshControl();
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

  Future<void> _decideRegistration(
    String registrationId,
    String decision,
  ) async {
    await _run(() async {
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('decideEventRegistrationV1').call<Map<String, dynamic>>({
        'eventId': widget.event.id,
        'registrationId': registrationId,
        'decision': decision,
      });
      if (!mounted) return;
      final resultLabel = switch (decision) {
        'approve' => 'approved',
        'decline' => 'declined',
        _ => 'promoted',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Registration $resultLabel.')));
    });
  }

  Future<void> _refreshOperationalState() async {
    await _refreshControl();
    await _refreshConnectivity();
    if (_session != null) await _refreshCredential(silent: true);
  }

  Future<void> _refreshConnectivity() async {
    final kitStatus = await _service.offlineKitStatus(widget.event.id);
    if (mounted) setState(() => _kitStatus = kitStatus);
    final dynamic result = await Connectivity().checkConnectivity();
    final isOffline = result is List
        ? result.every((item) => item == ConnectivityResult.none)
        : result == ConnectivityResult.none;
    final pending = await _service.pendingCount();
    final rejected = await _service.rejectedScans();
    if (!mounted) return;
    setState(() {
      _online = !isOffline;
      _pendingScans = pending;
      _rejectedScans = rejected.length;
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
      setState(() {
        _pendingScans = result.remaining;
        _rejectedScans = result.rejected;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Synced ${result.synced} scan${result.synced == 1 ? '' : 's'}; '
            '${result.remaining} pending; ${result.rejected} need review.',
          ),
        ),
      );
    });
  }

  Future<void> _refreshControl() async {
    try {
      final response =
          await FirebaseFunctions.instanceFor(region: 'us-central1')
              .httpsCallable('getAttendanceControl')
              .call({'eventId': widget.event.id});
      if (mounted) {
        setState(() => _controlStatus = response.data['status'].toString());
      }
    } catch (_) {
      /* Keep the last known control state while disconnected. */
    }
  }

  Future<void> _setControl(String status) => _run(() async {
    await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('setAttendanceControl')
        .call({'eventId': widget.event.id, 'status': status});
    if (mounted) setState(() => _controlStatus = status);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'paused'
                ? 'Check-in paused. New arrivals will be rejected until resumed.'
                : 'Check-in resumed for its scheduled window.',
          ),
        ),
      );
    }
  });

  Future<void> _reviewRejected() async {
    final rejected = await _service.rejectedScans();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Offline scans requiring review'),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final scan in rejected.where(
                (scan) => scan['eventId'] == widget.event.id,
              ))
                ListTile(
                  trailing: TextButton(
                    onPressed: () async {
                      final key = scan['idempotencyKey']?.toString();
                      if (key == null) return;
                      await _service.acknowledgeRejectedScans(
                        idempotencyKey: key,
                      );
                      if (context.mounted) Navigator.pop(context);
                      await _refreshConnectivity();
                    },
                    child: const Text('Acknowledge'),
                  ),
                  title: Text(
                    scan['rejectionMessage']?.toString() ?? 'Rejected scan',
                  ),
                  subtitle: Text(
                    'Event: ${scan['eventId']} • Observed: ${scan['observedAt']}',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep for review'),
          ),
        ],
      ),
    );
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
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: _busy ? null : () => _setControl('paused'),
                          child: const Text('Pause check-in'),
                        ),
                        TextButton(
                          onPressed: _busy ? null : () => _setControl('open'),
                          child: const Text('Resume check-in'),
                        ),
                        if (_rejectedScans > 0)
                          TextButton(
                            onPressed: _reviewRejected,
                            child: Text(
                              'Review $_rejectedScans rejected scans',
                            ),
                          ),
                      ],
                    ),
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
                        _controlStatus == 'paused'
                            ? 'Check-in paused'
                            : _controlStatus == 'closed'
                            ? 'Check-in closed'
                            : _session == null
                            ? 'Check-in awaiting opening'
                            : 'Check-in live',
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
            Text(
              'Offline kit: ${_kitStatus['preparedAt'] ?? 'Not downloaded'}\nLast successful reconciliation: ${_kitStatus['lastSync'] ?? 'Not recorded'}',
            ),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: 'Arrivals/min',
                    value: '$arrivalsLastMinute',
                  ),
                ),
                const Expanded(
                  child: Text(
                    'Confirmed, pending, waitlisted and attendance totals appear in the complete roster below.',
                  ),
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
            'Start venue credentials, staff scanning, and the live activity feed. '
            'Event passes are available before check-in opens.',
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
    return EventRoster(
      eventId: widget.event.id,
      canCheckIn: _session != null && !_busy,
      onDecision: _decideRegistration,
      onCheckIn: (row) => _checkInRoster(
        uid: row['uid']?.toString() ?? '',
        name: row['name']?.toString() ?? 'Attendee',
        registrationId: row['registrationId']?.toString(),
        ticketId: row['ticketId']?.toString(),
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

  Future<T?> _showDialogWithCleanup<T>({
    required WidgetBuilder builder,
    required VoidCallback cleanup,
  }) async {
    final route = DialogRoute<T>(context: context, builder: builder);
    try {
      return await Navigator.of(context, rootNavigator: true).push(route);
    } finally {
      // push() resolves at pop; fields still exist during the reverse transition.
      unawaited(route.completed.then((_) => cleanup()));
    }
  }

  Future<List<String>?> _collectAnswers(String title) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('Events')
        .doc(widget.event.id)
        .collection('EventQuestions')
        .get();
    // Legacy questions omitted timing and were collected at the door.
    final questions = snapshot.docs
        .where((doc) => (doc.data()['timing'] ?? 'check_in') == 'check_in')
        .toList();
    String prompt(Map<String, dynamic> data) {
      final current = data['prompt']?.toString().trim();
      return current?.isNotEmpty == true
          ? current!
          : (data['questionTitle'] ?? 'Event question').toString();
    }

    if (questions.isEmpty) return const [];
    if (!mounted) return null;
    final controllers = {
      for (final doc in questions) doc.id: TextEditingController(),
    };
    final route = DialogRoute<List<String>>(
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
                        '${prompt(data)}${data['required'] == true ? ' *' : ''}',
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
                          '${prompt(doc.data())}--ans--${controllers[doc.id]!.text.trim()}',
                    )
                    .toList(),
              );
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    try {
      return await Navigator.of(context, rootNavigator: true).push(route);
    } finally {
      // Popping resolves push() before the reverse transition removes the
      // TextFields. Keep their controllers alive until the route is removed.
      unawaited(
        route.completed.then((_) {
          for (final controller in controllers.values) {
            controller.dispose();
          }
        }),
      );
    }
  }

  Future<void> _checkInRoster({
    required String uid,
    required String name,
    String? registrationId,
    String? ticketId,
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
          'registrationId': ?registrationId,
          'ticketId': ?ticketId,
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
    final values = await _showDialogWithCleanup<List<String>>(
      cleanup: () {
        name.dispose();
        reason.dispose();
      },
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
    final reason = await _showDialogWithCleanup<String>(
      cleanup: controller.dispose,
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
    if (reason == null) return;
    await _run(
      () => _service.voidAttendance(attendanceId: attendanceId, reason: reason),
    );
  }

  final Map<String, String> _staffNames = {};
  Future<void> _refreshStaffNames() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final result = await FirebaseFunctions.instance
        .httpsCallable('getEventCapabilitiesV1')
        .call({'eventId': widget.event.id})
        .timeout(const Duration(seconds: 15));
    if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
    setState(() {
      _capabilityUid = uid;
      _serverManager = result.data['permissions']['manageEvent'] == true;
    });
    for (final person in result.data['staff'] as List) {
      _staffNames[person['uid']] = person['name'];
    }
  }

  Future<void> _manageStaff() async {
    try {
      await _refreshStaffNames();
    } catch (_) {
      _showError('Staff names are unavailable. Retry to refresh them.');
    }
    if (!mounted) return;
    final controller = TextEditingController();
    await _showDialogWithCleanup<void>(
      cleanup: controller.dispose,
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
                    title: Text(_staffNames[uid] ?? 'Unavailable account'),
                    subtitle: const Text('Door staff · Check-in access'),
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
                final actor = FirebaseAuth.instance.currentUser?.uid;
                final input = controller.text.trim();
                if (input.isEmpty || !_isOwner || actor == null) return;
                try {
                  var uid = input;
                  if (input.contains('@')) {
                    final profile = await PublicProfileService()
                        .lookupEventStaffAccount(
                          eventId: widget.event.id,
                          email: input,
                        );
                    if (!mounted ||
                        !dialogContext.mounted ||
                        FirebaseAuth.instance.currentUser?.uid != actor) {
                      return;
                    }
                    if (profile == null) {
                      _showError(
                        'No eligible verified Attendus account was found.',
                      );
                      return;
                    }
                    uid = profile.uid;
                  }
                  if (!_isOwner ||
                      FirebaseAuth.instance.currentUser?.uid != actor) {
                    return;
                  }
                  final next = {..._staffIds, uid}.toList();
                  await _saveStaff(next);
                  if (!mounted ||
                      !dialogContext.mounted ||
                      FirebaseAuth.instance.currentUser?.uid != actor) {
                    return;
                  }
                  controller.clear();
                  setDialogState(() {});
                } catch (error) {
                  if (mounted) _showError(error);
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Add staff'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveStaff(List<String> staff) async {
    await FirebaseFunctions.instance
        .httpsCallable('setEventStaffV1')
        .call({'eventId': widget.event.id, 'staff': staff})
        .timeout(const Duration(seconds: 15));
    await _refreshStaffNames();
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
