import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:attendus/Services/attendance_check_in_service.dart';
import 'package:attendus/models/event_model.dart';

class PersonalAttendancePassScreen extends StatefulWidget {
  const PersonalAttendancePassScreen({super.key, required this.event});

  final EventModel event;

  @override
  State<PersonalAttendancePassScreen> createState() =>
      _PersonalAttendancePassScreenState();
}

class _PersonalAttendancePassScreenState
    extends State<PersonalAttendancePassScreen> {
  final AttendanceCheckInService _service = AttendanceCheckInService();
  final LocalAuthentication _localAuthentication = LocalAuthentication();
  PersonalAttendancePass? _pass;
  bool _loading = true;
  bool _unlocked = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPass();
  }

  Future<void> _loadPass() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var unlocked = _unlocked;
      if (widget.event.checkInPolicy.passLockEnabled && !unlocked) {
        unlocked = await _authenticateDevice();
        if (!unlocked) {
          if (mounted) {
            setState(() => _error = 'Your event pass stayed locked.');
          }
          return;
        }
      }
      final pass = await _service.getPersonalPass(eventId: widget.event.id);
      if (pass.passLockRequired && !unlocked) {
        unlocked = await _authenticateDevice();
        if (!unlocked) {
          if (mounted) {
            setState(() => _error = 'Your event pass stayed locked.');
          }
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _pass = pass;
        _unlocked = unlocked || !pass.passLockRequired;
      });
    } on FirebaseFunctionsException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unlock() async {
    final authenticated = await _authenticateDevice();
    if (!mounted) return;
    setState(() => _unlocked = authenticated);
    if (authenticated && _pass == null) await _loadPass();
  }

  Future<bool> _authenticateDevice() async {
    try {
      final supported = await _localAuthentication.isDeviceSupported();
      if (!supported) {
        if (mounted) {
          setState(() {
            _error =
                'This device has no screen lock. Ask event staff to check you in.';
          });
        }
        return false;
      }
      final authenticated = await _localAuthentication.authenticate(
        localizedReason: 'Unlock your ${widget.event.title} event pass',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      return authenticated;
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'The pass stayed locked. You can retry or ask event staff for help.';
        });
      }
      return false;
    }
  }

  Future<void> _openWallet(String? value) async {
    final uri = value == null ? null : Uri.tryParse(value);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Wallet delivery is not configured for this event.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My event pass')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading && _pass == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final pass = _pass;
    if (pass == null) {
      return _MessageCard(
        icon: Icons.schedule,
        title: 'Your pass is not ready',
        message: _error ?? 'The organizer has not opened check-in yet.',
        action: FilledButton.icon(
          onPressed: _loadPass,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      );
    }
    if (!_unlocked) {
      return _MessageCard(
        icon: Icons.lock_outline,
        title: 'Pass Lock',
        message:
            _error ??
            'Unlock with this device’s screen lock before showing your short-lived pass.',
        action: FilledButton.icon(
          onPressed: _unlock,
          icon: const Icon(Icons.lock_open),
          label: const Text('Unlock pass'),
        ),
      );
    }
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              widget.event.title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              pass.attendeeName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 20),
            Semantics(
              label: 'Personal event pass QR code for ${pass.attendeeName}',
              child: QrImageView(
                data: pass.qrData,
                size: 260,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Show this pass to event staff. Do not share it; it is signed for your account.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Valid until ${DateFormat('MMM d · h:mm a').format(pass.expiresAt.toLocal())}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 32),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: pass.appleWalletUrl == null
                      ? null
                      : () => _openWallet(pass.appleWalletUrl),
                  icon: const Icon(Icons.wallet_outlined),
                  label: const Text('Apple Wallet'),
                ),
                OutlinedButton.icon(
                  onPressed: pass.googleWalletUrl == null
                      ? null
                      : () => _openWallet(pass.googleWalletUrl),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text('Google Wallet'),
                ),
              ],
            ),
            if (pass.appleWalletUrl == null &&
                pass.googleWalletUrl == null) ...[
              const SizedBox(height: 8),
              Text(
                'Wallet delivery will appear when the organizer enables a Wallet issuer.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(icon, size: 54),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          action,
        ],
      ),
    ),
  );
}
