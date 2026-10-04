import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';

class ProfileSafetyDialog extends StatefulWidget {
  const ProfileSafetyDialog({
    super.key,
    required this.userId,
    required this.report,
  });
  final String userId;
  final bool report;
  @override
  State<ProfileSafetyDialog> createState() => _ProfileSafetyDialogState();
}

class _ProfileSafetyDialogState extends State<ProfileSafetyDialog> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      setState(() => _error = 'Sign in to continue.');
      return;
    }
    if (widget.report && _reason.text.trim().isEmpty) {
      setState(() => _error = 'Tell us what happened.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final helper = FirebaseFirestoreHelper();
      if (widget.report) {
        await helper
            .submitUserReport(
              type: 'user',
              targetUserId: widget.userId,
              reason: _reason.text.trim(),
            )
            .timeout(const Duration(seconds: 20));
      } else {
        await helper
            .blockUser(blockerId: user.uid, blockedUserId: widget.userId)
            .timeout(const Duration(seconds: 20));
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not finish. Please retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.report ? 'Report user' : 'Block user'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.report)
          TextField(
            controller: _reason,
            enabled: !_busy,
            maxLength: 1000,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'What happened?'),
          )
        else
          const Text(
            'Direct messages between you and this user will be blocked.',
          ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: Text(
          _busy
              ? 'Working…'
              : widget.report
              ? 'Submit report'
              : 'Block',
        ),
      ),
    ],
  );
}
