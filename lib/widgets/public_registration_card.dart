import 'package:attendus/Services/admission_selection.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/Services/public_registration_service.dart';
import 'package:attendus/Services/guest_mode_service.dart';
import 'package:attendus/firebase/firebase_messaging_helper.dart';

class PublicRegistrationCard extends StatefulWidget {
  static Future<Map<String, dynamic>?> showForm(
    BuildContext context,
    EventModel event,
  ) => showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _RegistrationForm(event: event, service: PublicRegistrationService()),
  );
  const PublicRegistrationCard({
    super.key,
    required this.event,
    required this.onCheckIn,
    this.registrationId,
    this.ticketId,
    this.onAdmissionSelected,
    this.onViewPass,
  });
  final EventModel event;
  final VoidCallback onCheckIn;
  final VoidCallback? onViewPass;
  final String? registrationId;
  final String? ticketId;
  final ValueChanged<Map<String, dynamic>>? onAdmissionSelected;
  @override
  State<PublicRegistrationCard> createState() => _PublicRegistrationCardState();
}

class _PublicRegistrationCardState extends State<PublicRegistrationCard> {
  final _service = PublicRegistrationService();
  StreamSubscription<User?>? _auth;
  Map<String, dynamic> _status = const {'status': 'none'};
  String? _error;
  bool _loading = true;
  int _generation = 0;
  String? _statusUid;
  List<Map<String, dynamic>> get _admissions =>
      (_status['admissions'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
  bool get _needsSelection =>
      _admissions.length > 1 &&
      selectAdmission(
            _admissions,
            registrationId: _status['registrationId'] as String?,
            ticketId: _status['ticketId'] as String?,
          ) ==
          null;

  @override
  void didUpdateWidget(covariant PublicRegistrationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.id != widget.event.id ||
        oldWidget.registrationId != widget.registrationId ||
        oldWidget.ticketId != widget.ticketId) {
      _load();
    }
  }

  @override
  void initState() {
    super.initState();
    _auth = FirebaseAuth.instance.authStateChanges().listen((_) => _load());
  }

  @override
  void dispose() {
    _generation++;
    _auth?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _statusUid = uid;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _status = const {'status': 'none'};
      });
    }
    try {
      final result = await _service.status(
        widget.event.id,
        registrationId: widget.registrationId,
        ticketId: widget.ticketId,
      );
      if (mounted &&
          generation == _generation &&
          FirebaseAuth.instance.currentUser?.uid == uid) {
        setState(() => _status = result);
        if (result['registrationId'] != null || result['ticketId'] != null) {
          widget.onAdmissionSelected?.call(result);
        }
      }
    } catch (_) {
      if (mounted &&
          generation == _generation &&
          FirebaseAuth.instance.currentUser?.uid == uid) {
        setState(
          () => _error = 'Could not load your registration. Please retry.',
        );
      }
    } finally {
      if (mounted &&
          generation == _generation &&
          FirebaseAuth.instance.currentUser?.uid == uid) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _register() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final result = await PublicRegistrationCard.showForm(context, widget.event);
    if (!mounted ||
        result == null ||
        (uid != null && FirebaseAuth.instance.currentUser?.uid != uid)) {
      return;
    }
    setState(() {
      _status = result;
      _error = null;
    });
    await _load();
  }

  void _view() {
    final displayedUid = _statusUid;
    showDialog<void>(
      context: context,
      builder: (context) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, _) =>
            FirebaseAuth.instance.currentUser?.uid != displayedUid
            ? AlertDialog(
                title: const Text('Account changed'),
                content: const Text(
                  'Close this view and load your current registrations.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              )
            : AlertDialog(
                title: const Text('Your registration'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.event.title),
                      const SizedBox(height: 12),
                      Text(switch (_status['status']) {
                        'pending' => 'Awaiting organizer approval',
                        'waitlisted' =>
                          'You are on the waitlist. We will email you if a place becomes available.',
                        'confirmation_pending' =>
                          'Check your email for your existing registration and its current status.',
                        'cancelled' || 'canceled' => 'Registration cancelled',
                        'declined' => 'Registration declined',
                        'confirmed' =>
                          _status['ticketId'] == null
                              ? 'RSVP confirmed'
                              : 'Ticket confirmed',
                        _ => 'Registration status unavailable',
                      }),
                      if (_status['status'] == 'confirmed' &&
                          !_needsSelection &&
                          _status['ticketCode'] is String) ...[
                        QrImageView(
                          data: _status['ticketCode'] as String,
                          size: 180,
                        ),
                        SelectableText(_status['ticketCode'] as String),
                      ],
                      TextButton(
                        onPressed: () async {
                          await FirebaseMessagingHelper()
                              .requestEventReminders();
                          if (context.mounted) Navigator.pop(context);
                        },
                        child: const Text('Enable event reminders'),
                      ),
                    ],
                  ),
                ),
                actions: [
                  if (_status['status'] == 'confirmed' &&
                      !_needsSelection &&
                      widget.onViewPass != null)
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onViewPass!();
                      },
                      child: const Text('View personal pass'),
                    ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _load();
                    },
                    child: const Text('Refresh status'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final state = _status['status'];
    final cancelled = [
      'cancelled',
      'canceled',
    ].contains(_status['eventStatus'] ?? event.status);
    DateTime? instant(dynamic value) => value is Timestamp
        ? value.toDate()
        : value is DateTime
        ? value
        : DateTime.tryParse(value?.toString() ?? '');
    final closesAt =
        instant(event.registrationPolicy['closesAt']) ?? event.eventEndTime;
    final opensAt = instant(event.registrationPolicy['opensAt']);
    final closed = DateTime.now().isAfter(closesAt);
    final notOpen = opensAt != null && DateTime.now().isBefore(opensAt);
    final confirmed = state == 'confirmed' && !_needsSelection;
    final checkInTime =
        DateTime.now().isAfter(
          event.selectedDateTime.subtract(
            Duration(minutes: event.checkInPolicy.opensBeforeMinutes),
          ),
        ) &&
        DateTime.now().isBefore(
          event.eventEndTime.add(
            Duration(minutes: event.checkInPolicy.closesAfterMinutes),
          ),
        );
    final full =
        event.maxTickets > 0 &&
        (event.ticketsEnabled
                ? event.issuedTickets
                : event.confirmedRegistrationCount) >=
            event.maxTickets;
    final waitlist =
        full && event.registrationPolicy['waitlistEnabled'] != false;
    String label;
    VoidCallback? action;
    if (cancelled) {
      label = 'Event cancelled';
    } else if (_loading) {
      label = 'Loading registration…';
    } else if (_error != null) {
      label = 'Retry registration status';
      action = _load;
    } else if (_needsSelection) {
      label = 'Choose a registration or ticket below';
    } else if (confirmed && checkInTime) {
      label = 'Check in';
      action = widget.onCheckIn;
    } else if ([
      'confirmed',
      'pending',
      'waitlisted',
      'confirmation_pending',
    ].contains(state)) {
      label = confirmed ? 'View my registration' : 'View registration status';
      action = _view;
    } else if (state == 'cancelled' || state == 'declined') {
      label = 'Registration ${state == 'declined' ? 'declined' : 'cancelled'}';
      action = _view;
    } else if (notOpen) {
      label = 'Registration opens soon';
    } else if (closed) {
      label = 'Registration closed';
    } else if (full && !waitlist) {
      label = 'Event full';
    } else {
      label = waitlist
          ? 'Join waitlist'
          : event.registrationPolicy['approvalMode'] == 'manual'
          ? 'Request a place'
          : event.ticketsEnabled
          ? 'Get free ticket'
          : 'RSVP';
      action = _register;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_loading && _admissions.length > 1)
          ..._admissions.map(
            (admission) => ListTile(
              leading: Icon(
                admission['ticketId'] == null
                    ? Icons.event_available
                    : Icons.confirmation_number_outlined,
              ),
              title: Text(
                '${admission['ticketId'] == null ? 'RSVP' : 'Ticket'} · ${admission['status']}',
              ),
              subtitle: Text('Reference ${admission['id']}'),
              selected: admission['ticketId'] != null
                  ? admission['ticketId'] == _status['ticketId']
                  : admission['registrationId'] == _status['registrationId'],
              onTap: () {
                setState(() => _status = {..._status, ...admission});
                widget.onAdmissionSelected?.call(admission);
              },
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, semanticsLabel: _error),
          ),
        FilledButton(
          onPressed: action,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(label),
          ),
        ),
        if (confirmed && checkInTime)
          TextButton(
            onPressed: _view,
            child: const Text('View registration or ticket'),
          ),
        if (state == 'none' && !closed && !cancelled)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Register with your name and email. Creating an account is optional.',
            ),
          ),
      ],
    );
  }
}

class _RegistrationForm extends StatefulWidget {
  const _RegistrationForm({required this.event, required this.service});
  final EventModel event;
  final PublicRegistrationService service;
  @override
  State<_RegistrationForm> createState() => _RegistrationFormState();
}

class _RegistrationFormState extends State<_RegistrationForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(
    text: FirebaseAuth.instance.currentUser?.displayName,
  );
  final _email = TextEditingController(
    text: FirebaseAuth.instance.currentUser?.email,
  );
  final Map<String, dynamic> _answers = {};
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _questions;
  String? _error;
  bool _busy = false;
  String? _formUid = FirebaseAuth.instance.currentUser?.uid;
  StreamSubscription<User?>? _auth;
  @override
  void initState() {
    super.initState();
    _auth = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) return;
      if (_formUid != null && _formUid != user?.uid) {
        setState(() {
          _name.clear();
          _email.clear();
          _answers.clear();
          _questions = null;
          _error =
              'Account changed. Reload the questions and review your details before submitting.';
        });
      }
      _formUid = user?.uid;
    });
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    setState(() => _error = null);
    try {
      final user = await GuestModeService().ensureGuestSession().timeout(
        const Duration(seconds: 15),
      );
      if (user == null) {
        throw StateError('Secure registration session unavailable.');
      }
      final result = await FirebaseFirestore.instance
          .collection('Events')
          .doc(widget.event.id)
          .collection('EventQuestions')
          .where('timing', isEqualTo: 'registration')
          .get()
          .timeout(const Duration(seconds: 15));
      if (mounted && FirebaseAuth.instance.currentUser?.uid == user.uid) {
        setState(
          () => _questions = result.docs
            ..sort(
              (a, b) => ((a.data()['order'] as num?) ?? 0).compareTo(
                (b.data()['order'] as num?) ?? 0,
              ),
            ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not load the required questions. Retry before registering.',
        );
      }
    }
  }

  @override
  void dispose() {
    _auth?.cancel();
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _questions == null || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.service.register(
        widget.event.id,
        _name.text,
        _email.text,
        _answers,
      );
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FirebaseFunctionsException
              ? error.message ?? 'Registration could not finish. Retry safely.'
              : 'Registration could not finish. Retry safely.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _question(QueryDocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data();
    final prompt =
        '${data['prompt'] ?? data['questionTitle'] ?? 'Question'}${data['required'] == true ? ' *' : ''}';
    final options = (data['options'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    if (data['type'] == 'acknowledgement') {
      return FormField<bool>(
        validator: (_) =>
            data['required'] == true && _answers[document.id] != true
            ? 'Please acknowledge this item.'
            : null,
        builder: (field) => Column(
          children: [
            CheckboxListTile(
              title: Text(prompt),
              value: _answers[document.id] == true,
              onChanged: (value) => setState(() {
                _answers[document.id] = value;
                field.didChange(value);
              }),
            ),
            if (field.errorText != null)
              Text(
                field.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      );
    }
    if (data['type'] == 'multiple_choice') {
      return FormField<List<String>>(
        validator: (_) =>
            data['required'] == true &&
                ((_answers[document.id] as List?)?.isEmpty ?? true)
            ? 'Choose at least one option.'
            : null,
        builder: (field) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(prompt),
            for (final option in options)
              CheckboxListTile(
                title: Text(option),
                value: (_answers[document.id] as List? ?? []).contains(option),
                onChanged: (selected) => setState(() {
                  final chosen = List<String>.from(
                    _answers[document.id] as List? ?? [],
                  );
                  selected == true ? chosen.add(option) : chosen.remove(option);
                  _answers[document.id] = chosen;
                  field.didChange(chosen);
                }),
              ),
            if (field.errorText != null) Text(field.errorText!),
          ],
        ),
      );
    }
    if (data['type'] == 'single_choice') {
      return DropdownButtonFormField<String>(
        decoration: InputDecoration(labelText: prompt),
        items: options
            .map((value) => DropdownMenuItem(value: value, child: Text(value)))
            .toList(),
        onChanged: (value) => _answers[document.id] = value,
        validator: (value) => data['required'] == true && value == null
            ? 'Choose an option.'
            : null,
      );
    }
    return TextFormField(
      decoration: InputDecoration(labelText: prompt),
      maxLength: 4000,
      onChanged: (value) => _answers[document.id] = value,
      validator: (value) =>
          data['required'] == true && (value?.trim().isEmpty ?? true)
          ? 'An answer is required.'
          : null,
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      24,
      24,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.event.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Full name'),
              textCapitalization: TextCapitalization.words,
              validator: (value) =>
                  value?.trim().isEmpty != false ? 'Enter your name.' : null,
            ),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (value) =>
                  RegExp(
                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                  ).hasMatch(value?.trim() ?? '')
                  ? null
                  : 'Enter a valid email.',
            ),
            if (_questions != null) ..._questions!.map(_question),
            if (_questions == null && _error == null)
              const LinearProgressIndicator(),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              if (_questions == null)
                TextButton(
                  onPressed: _loadQuestions,
                  child: const Text('Retry'),
                ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy || _questions == null ? null : _submit,
              child: Text(_busy ? 'Submitting…' : 'Confirm registration'),
            ),
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );
}
