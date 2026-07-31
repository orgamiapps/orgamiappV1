import 'package:flutter/material.dart';

class MutationRequest {
  const MutationRequest(this.reason);
  final String reason;
}

class MutationDialog extends StatefulWidget {
  const MutationDialog({
    super.key,
    required this.title,
    required this.description,
    this.confirmWord = 'CONFIRM',
  });
  final String title, description, confirmWord;
  @override
  State<MutationDialog> createState() => _MutationDialogState();
}

class _MutationDialogState extends State<MutationDialog> {
  final reason = TextEditingController(),
      confirmation = TextEditingController();
  bool acknowledged = false;
  bool get valid =>
      reason.text.trim().length >= 10 &&
      confirmation.text.trim() == widget.confirmWord &&
      acknowledged;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.description),
          const SizedBox(height: 18),
          TextField(
            controller: reason,
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Reason (required, at least 10 characters)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: confirmation,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Type ${widget.confirmWord}',
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: acknowledged,
            onChanged: (v) => setState(() => acknowledged = v ?? false),
            title: const Text(
              'I understand this action will be audited and may affect a real account.',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: valid
            ? () => Navigator.pop(context, MutationRequest(reason.text.trim()))
            : null,
        child: const Text('Confirm'),
      ),
    ],
  );
}
