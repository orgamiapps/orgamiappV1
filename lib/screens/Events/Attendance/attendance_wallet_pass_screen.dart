import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:local_auth/local_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class AttendanceWalletPassScreen extends StatefulWidget {
  const AttendanceWalletPassScreen({
    super.key,
    this.eventId,
    this.ticketId,
    this.registrationId,
  });
  final String? eventId;
  final String? ticketId;
  final String? registrationId;
  @override
  State<AttendanceWalletPassScreen> createState() =>
      _AttendanceWalletPassScreenState();
}

class _AttendanceWalletPassScreenState extends State<AttendanceWalletPassScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _pass;
  String? _error;
  String? _ticketId;
  String? _registrationId;
  String? _uid;
  int _generation = 0;
  StreamSubscription<User?>? _auth;
  bool _busy = false;
  bool _unlocked = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticketId = widget.ticketId;
    _registrationId = widget.registrationId;
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _auth = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) return;
      if (_uid != user?.uid) {
        _generation++;
        setState(() {
          _uid = user?.uid;
          _pass = null;
          _ticketId = null;
          _registrationId = null;
          _unlocked = false;
          _error = null;
        });
      }
      _load();
    });
  }

  @override
  void dispose() {
    _generation++;
    _auth?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(() => _unlocked = false);
    }
  }

  Future<void> _load({bool replace = false}) async {
    final generation = ++_generation;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    bool current() =>
        mounted &&
        generation == _generation &&
        FirebaseAuth.instance.currentUser?.uid == uid;
    if (uid == null) {
      setState(() {
        _pass = null;
        _busy = false;
        _error = 'Sign in to view your pass.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _pass = null;
      _error = null;
    });
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('getAttendancePass')
          .call({
            'kind': widget.eventId == null ? 'identity' : 'event',
            'eventId': ?widget.eventId,
            'ticketId': ?_ticketId,
            'registrationId': ?_registrationId,
            'replace': replace,
          });
      if (current()) {
        setState(() => _pass = Map<String, dynamic>.from(result.data as Map));
      }
    } on FirebaseFunctionsException catch (error) {
      if (!mounted || !current()) return;
      final details = error.details;
      if (details is Map &&
          (details['tickets'] is List || details['admissions'] is List)) {
        final choices = (details['admissions'] ?? details['tickets']) as List;
        final selected = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (context) => StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, _) =>
                FirebaseAuth.instance.currentUser?.uid != uid
                ? AlertDialog(
                    title: const Text('Account changed'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  )
                : SimpleDialog(
                    title: const Text('Choose your registration or ticket'),
                    children: [
                      for (final choice in choices.whereType<Map>())
                        SimpleDialogOption(
                          onPressed: () => Navigator.pop(context, {
                            'registrationId': choice['registrationId'],
                            'ticketId':
                                choice['ticketId'] ??
                                (details['tickets'] is List
                                    ? choice['id']
                                    : null),
                          }),
                          child: Text(
                            (choice['label'] ??
                                    choice['ticketId'] ??
                                    choice['registrationId'] ??
                                    choice['id'])
                                .toString(),
                          ),
                        ),
                    ],
                  ),
          ),
        );
        if (selected != null && current()) {
          _ticketId = selected['ticketId'] as String?;
          _registrationId = selected['registrationId'] as String?;
          await _load();
        } else if (current()) {
          setState(() => _error = 'Choose an admission to display its pass.');
        }
      } else {
        setState(
          () =>
              _error = error.message ?? 'Your pass is temporarily unavailable.',
        );
      }
    } catch (_) {
      if (current()) {
        setState(
          () => _error = 'Your pass could not be loaded. Please try again.',
        );
      }
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  Future<void> _openWallet(String field) async {
    final value = _pass?[field]?.toString();
    final uri = value == null ? null : Uri.tryParse(value);
    if (uri == null) return;
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      /* Keep the pass available when a Wallet app cannot open. */
    }
    if (mounted) {
      setState(
        () => _error = 'Could not open Wallet. Try again on your phone.',
      );
    }
  }

  Future<void> _unlock() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final generation = _generation;
    try {
      final authenticated = await LocalAuthentication().authenticate(
        localizedReason: 'Show your Attendus event pass',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      if (mounted &&
          generation == _generation &&
          FirebaseAuth.instance.currentUser?.uid == uid) {
        setState(() => _unlocked = authenticated);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Device authentication is unavailable here. Use the venue QR or code, Smart Arrival if offered, or ask staff for help.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pass = _pass;
    final locked = pass?['passLockRequired'] == true && !_unlocked;
    final platform = Theme.of(context).platform;
    final apple =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.eventId == null ? 'My Attendus pass' : 'My event pass',
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                if (pass != null) ...[
                  Text(
                    pass['title']?.toString() ?? 'Attendus',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(pass['attendeeName'].toString()),
                  const SizedBox(height: 20),
                  if (locked)
                    FilledButton.icon(
                      onPressed: _unlock,
                      icon: const Icon(Icons.lock_open),
                      label: const Text('Unlock in-app pass'),
                    )
                  else
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(12),
                      child: QrImageView(
                        data: pass['qrData'].toString(),
                        size: 240,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    widget.eventId == null
                        ? 'Show this pass to staff. They will check your eligibility for their event.'
                        : 'Show this pass to event staff when you arrive.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  if (apple && pass['appleWalletUrl'] != null)
                    FilledButton.icon(
                      onPressed: pass['appleWalletUrl'] == null
                          ? null
                          : () => _openWallet('appleWalletUrl'),
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      label: const Text('Add to Apple Wallet'),
                    ),
                  if (!apple && pass['googleWalletUrl'] != null)
                    FilledButton.icon(
                      onPressed: pass['googleWalletUrl'] == null
                          ? null
                          : () => _openWallet('googleWalletUrl'),
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      label: const Text('Add to Google Wallet'),
                    ),
                  if (locked)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Pass Lock protects the in-app display. If you cannot unlock it, use the venue QR or code, Smart Arrival if offered, or ask staff.',
                      ),
                    ),
                ],
                TextButton(
                  onPressed: _busy ? null : () => _load(),
                  child: const Text('Refresh pass'),
                ),
                if (widget.eventId == null && pass != null)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            final replace = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Replace your pass?'),
                                content: const Text(
                                  'Your previous code will stop working. Installed Wallet passes will receive an update.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Replace'),
                                  ),
                                ],
                              ),
                            );
                            if (replace == true) await _load(replace: true);
                          },
                    child: const Text('Replace pass'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
