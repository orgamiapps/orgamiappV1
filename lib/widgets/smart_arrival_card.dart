import 'dart:async';
import 'package:attendus/Services/product_funnel_service.dart';
import 'package:flutter/material.dart';
import 'package:attendus/Services/arrival_route_observer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:geolocator/geolocator.dart';
import 'package:attendus/Services/smart_arrival_service.dart';
import 'package:attendus/Services/attendance_check_in_service.dart';
import 'package:attendus/Services/guest_mode_service.dart';

class SmartArrivalCard extends StatefulWidget {
  const SmartArrivalCard({super.key, this.eventId});
  final String? eventId;
  @override
  State<SmartArrivalCard> createState() => _SmartArrivalCardState();
}

class _SmartArrivalCardState extends State<SmartArrivalCard>
    with WidgetsBindingObserver, RouteAware {
  PageRoute<dynamic>? _route;
  bool _foreground = true;
  bool _locationExplained = false;
  bool get _visible => mounted && _foreground && (_route?.isCurrent ?? true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && route != _route) {
      arrivalRouteObserver.unsubscribe(this);
      _route = route;
      arrivalRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    _generation++;
    _location.cancel();
    if (mounted) setState(() => _busy = false);
  }

  @override
  void didPopNext() {
    _refreshIfPermitted();
  }

  final _location = SmartArrivalService();
  final _attendance = AttendanceCheckInService();
  List<Map<String, dynamic>> _events = [];
  bool _busy = false;
  bool _enabled = false;
  String? _message;
  bool _confirmed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFeature();
  }

  Future<void> _loadFeature() async {
    try {
      final config = await FirebaseFirestore.instance
          .collection('AppConfig')
          .doc('attendance')
          .get();
      final flag = config.data()?['smartArrival'];
      final allowed =
          flag is Map &&
          flag['enabled'] == true &&
          ((flag['userIds'] as List? ?? []).isEmpty ||
              (flag['userIds'] as List).contains(
                FirebaseAuth.instance.currentUser?.uid,
              )) &&
          (flag['allEvents'] == true ||
              (widget.eventId == null
                  ? (flag['eventIds'] as List? ?? []).isNotEmpty
                  : (flag['eventIds'] as List? ?? []).contains(
                      widget.eventId,
                    )));
      if (mounted) {
        setState(() => _enabled = allowed);
        if (allowed) await _refreshIfPermitted();
      }
    } catch (_) {
      /* A disabled pilot does not interrupt normal discovery. */
    }
  }

  @override
  void dispose() {
    _generation++;
    _location.cancel();
    arrivalRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      _refreshIfPermitted();
    } else {
      _generation++;
      _location.cancel();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshIfPermitted() async {
    if (!_enabled || !_visible || !_locationExplained) return;
    LocationPermission permission;
    try {
      permission = await Geolocator.checkPermission();
    } catch (_) {
      return;
    }
    if (_visible &&
        !_confirmed &&
        (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always)) {
      await _refresh(false);
    }
  }

  String _error(Object error) => error is FirebaseFunctionsException
      ? error.message ?? 'Check-in is temporarily unavailable.'
      : error.toString().replaceFirst('Bad state: ', '');

  void _recordFallback(Object error) {
    final details = error is FirebaseFunctionsException ? error.details : null;
    final reason = error is SmartArrivalFailure
        ? error.reason
        : error is TimeoutException
        ? 'timeout'
        : details is Map
        ? details['reason']?.toString() ?? 'unavailable'
        : 'unavailable';
    unawaited(
      ProductFunnelService().record(
        'smart_arrival_fallback',
        dimensions: {'errorCategory': reason},
      ),
    );
  }

  Future<void> _refresh(bool ask) async {
    if (_busy || !_visible) return;
    if (ask) _locationExplained = true;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final position = await _location.freshPosition(requestPermission: ask);
      if (!_visible || generation != _generation) return;
      final events = await _location.candidates(
        position,
        eventId: widget.eventId,
      );
      if (!_visible || generation != _generation) return;
      setState(() {
        _events = events;
        if (events.isEmpty) {
          _message =
              'No eligible check-ins nearby right now. You can use the venue QR or code, or ask staff.';
        }
      });
    } catch (error) {
      _recordFallback(error);
      if (mounted && generation == _generation) {
        setState(() => _message = _error(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _checkIn(Map<String, dynamic> event) async {
    final beganAt = DateTime.now();
    String? ticketId;
    final tickets = (event['ticketOptions'] as List? ?? [])
        .whereType<Map>()
        .toList();
    if (tickets.isNotEmpty) {
      ticketId = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Select your ticket'),
          children: [
            for (final ticket in tickets)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.pop(context, ticket['id'].toString()),
                child: Text(ticket['label'].toString()),
              ),
          ],
        ),
      );
      if (ticketId == null || !mounted || !_visible) return;
    }
    final guest = FirebaseAuth.instance.currentUser?.isAnonymous != false;
    final name = TextEditingController(
      text: event['attendeeName']?.toString().isNotEmpty == true
          ? event['attendeeName'].toString()
          : GuestModeService().guestDisplayName ?? '',
    );
    final saved = (event['answers'] as List? ?? [])
        .map((v) => v.toString())
        .toList();
    final questions = (event['questions'] as List? ?? [])
        .whereType<Map>()
        .where(
          (q) =>
              q['required'] == true &&
              !saved.any(
                (a) =>
                    a.startsWith("${q['questionTitle']}--ans--") &&
                    a.split('--ans--').last.trim().isNotEmpty,
              ),
        )
        .toList();
    final controllers = [for (final _ in questions) TextEditingController()];
    final form = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Check in to ${event['title']}?'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Confirm your arrival. We will check your current location once.',
                ),
                if (guest)
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Full name'),
                    validator: (v) => (v?.trim().length ?? 0) < 2
                        ? 'Enter your full name'
                        : null,
                  ),
                for (var i = 0; i < questions.length; i++)
                  TextFormField(
                    controller: controllers[i],
                    decoration: InputDecoration(
                      labelText:
                          questions[i]['questionTitle']?.toString() ??
                          'Required answer',
                    ),
                    validator: (v) => v?.trim().isNotEmpty == true
                        ? null
                        : 'Please answer this question',
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Check in'),
          ),
        ],
      ),
    );
    final fullName = name.text.trim();
    final answers = [
      ...saved,
      for (var i = 0; i < questions.length; i++)
        '${questions[i]['questionTitle']}--ans--${controllers[i].text.trim()}',
    ];
    name.dispose();
    for (final controller in controllers) {
      controller.dispose();
    }
    if (accepted != true || !_visible) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final position = await _location.freshPosition(requestPermission: true);
      if (!_visible || generation != _generation) return;
      final receipt = await _attendance.submitCheckIn(
        eventId: event['eventId'].toString(),
        sessionId: event['sessionId']?.toString() ?? '',
        credential: {
          'type': 'location',
          'position': position,
          'ticketId': ?ticketId,
          if (guest) 'fullName': fullName,
        },
        answers: answers,
      );
      unawaited(
        ProductFunnelService().record(
          'smart_arrival_completed',
          dimensions: {
            'durationMs': DateTime.now()
                .difference(beganAt)
                .inMilliseconds
                .toString(),
          },
        ),
      );
      if (!_visible || generation != _generation) return;
      setState(() {
        _confirmed = true;
        _message =
            '${receipt.attendeeName}, you’re checked in to ${event['title']}.';
        _events = [];
      });
    } catch (error) {
      _recordFallback(error);
      if (_visible && generation == _generation) {
        setState(() => _message = _error(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => !_enabled
      ? const SizedBox.shrink()
      : Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      _confirmed
                          ? Icons.check_circle_outline
                          : Icons.near_me_outlined,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _confirmed ? 'You’re checked in' : 'Smart Arrival',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_message != null) Text(_message!),
                if (!_confirmed && _message == null && _events.isEmpty)
                  const Text(
                    'At your event? Allow a one-time foreground location check to find nearby check-ins. Your coordinates are not saved. You will confirm before checking in. You can also use the venue QR or code, or ask staff.',
                  ),
                if (_events.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final event in _events)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(event['title']?.toString() ?? 'Event'),
                            subtitle: Text(event['location']?.toString() ?? ''),
                            trailing: const Icon(Icons.arrow_forward),
                            onTap: _busy ? null : () => _checkIn(event),
                          ),
                      ],
                    ),
                  ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (!_confirmed)
                  TextButton.icon(
                    onPressed: _busy ? null : () => _refresh(true),
                    icon: const Icon(Icons.my_location),
                    label: Text(
                      _message == null
                          ? 'Check in with location'
                          : 'Try location again',
                    ),
                  ),
              ],
            ),
          ),
        );
}
