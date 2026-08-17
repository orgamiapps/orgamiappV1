import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/admin_api_client.dart';
import '../models/api_models.dart';
import 'mutation_dialog.dart';
import 'paged_resource_screen.dart';

class CommunicationsScreen extends StatelessWidget {
  const CommunicationsScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _testSend(context),
              icon: const Icon(Icons.send_outlined),
              label: const Text('Send provider test'),
            ),
          ),
        ),
        const Material(
          child: TabBar(
            tabs: [
              Tab(icon: Icon(Icons.outbox_outlined), text: 'Delivery queue'),
              Tab(
                icon: Icon(Icons.badge_outlined),
                text: 'Guest registrations',
              ),
              Tab(icon: Icon(Icons.article_outlined), text: 'Templates'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            children: [
              PagedResourceScreen(
                title: 'Confirmation delivery',
                path: '/v1/communications/messages',
                columns: const [
                  'id',
                  'channel',
                  'status',
                  'maskedContact',
                  'attempts',
                  'providerStatus',
                  'lastError',
                  'createdAt',
                ],
                rowActions: _messageActions,
              ),
              PagedResourceScreen(
                title: 'Named guest registrations',
                path: '/v1/communications/guests',
                columns: const [
                  'id',
                  'fullName',
                  'contactType',
                  'maskedContact',
                  'deliveryStatus',
                  'verificationStatus',
                  'claimedByUid',
                  'createdAt',
                ],
                rowActions: _guestActions,
              ),
              PagedResourceScreen(
                title: 'Confirmation templates',
                path: '/v1/communications/templates',
                columns: const [
                  'id',
                  'name',
                  'status',
                  'version',
                  'updatedBy',
                  'updatedAt',
                ],
                rowActions: _templateActions,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  static Future<void> _testSend(BuildContext context) async {
    final contact = TextEditingController();
    var type = 'email';
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Send provider test'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Channel'),
                items: const [
                  DropdownMenuItem(value: 'email', child: Text('Email')),
                  DropdownMenuItem(value: 'phone', child: Text('U.S. mobile')),
                ],
                onChanged: (value) => setState(() => type = value ?? 'email'),
              ),
              TextField(
                controller: contact,
                keyboardType: type == 'phone'
                    ? TextInputType.phone
                    : TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: type == 'phone'
                      ? 'U.S. mobile number'
                      : 'Email address',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'contactType': type,
                'contactValue': contact.text.trim(),
              }),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    contact.dispose();
    if (values == null || !context.mounted) return;
    final request = await showDialog<MutationRequest>(
      context: context,
      builder: (_) => const MutationDialog(
        title: 'Confirm provider test',
        description:
            'Send one audited transactional test through the selected provider.',
      ),
    );
    if (request == null || !context.mounted) return;
    try {
      await context.read<AdminApiClient>().postMutation(
        '/v1/communications/test',
        reason: request.reason,
        confirmed: true,
        values: values,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Provider test queued. Check the delivery queue.'),
          ),
        );
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  static List<Widget> _messageActions(
    BuildContext context,
    Map<String, dynamic> row,
    VoidCallback reload,
  ) => [
    IconButton(
      tooltip: 'Retry delivery',
      onPressed: ['failed', 'dead_letter', 'retry'].contains(row['status'])
          ? () => _retry(context, row['id'].toString(), reload)
          : null,
      icon: const Icon(Icons.replay_outlined),
    ),
  ];

  static Future<void> _retry(
    BuildContext context,
    String id,
    VoidCallback reload,
  ) async {
    final request = await showDialog<MutationRequest>(
      context: context,
      builder: (_) => const MutationDialog(
        title: 'Retry confirmation',
        description:
            'Queue this message for another provider attempt. The operation is audited.',
      ),
    );
    if (request == null || !context.mounted) return;
    try {
      await context.read<AdminApiClient>().postMutation(
        '/v1/communications/messages/$id/retry',
        reason: request.reason,
        confirmed: true,
      );
      reload();
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  static List<Widget> _guestActions(
    BuildContext context,
    Map<String, dynamic> row,
    VoidCallback _,
  ) => [
    IconButton(
      tooltip: 'View full contact (audited)',
      onPressed: () => _guestDetail(context, row['id'].toString()),
      icon: const Icon(Icons.visibility_outlined),
    ),
  ];

  static Future<void> _guestDetail(BuildContext context, String id) async {
    try {
      final response = await context.read<AdminApiClient>().getJson(
        '/v1/communications/guests/$id',
      );
      final data = response['data'] as Map<String, dynamic>;
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(data['fullName']?.toString() ?? 'Guest registration'),
          content: SelectableText(
            'Contact: ${data['contact']}\n'
            'Delivery: ${data['deliveryStatus']}\n'
            'Verification: ${data['verificationStatus']}\n\n'
            'This full-contact access has been recorded in the audit log.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  static List<Widget> _templateActions(
    BuildContext context,
    Map<String, dynamic> row,
    VoidCallback reload,
  ) => [
    IconButton(
      tooltip: 'Edit and publish template',
      onPressed: () => _editTemplate(context, row['id'].toString(), reload),
      icon: const Icon(Icons.edit_outlined),
    ),
  ];

  static Future<void> _editTemplate(
    BuildContext context,
    String id,
    VoidCallback reload,
  ) async {
    try {
      final response = await context.read<AdminApiClient>().getJson(
        '/v1/communications/templates/$id',
      );
      final data = response['data'] as Map<String, dynamic>;
      if (!context.mounted) return;
      final subject = TextEditingController(text: data['subject']?.toString());
      final text = TextEditingController(text: data['text']?.toString());
      final html = TextEditingController(text: data['html']?.toString());
      final sms = TextEditingController(text: data['sms']?.toString());
      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Publish ${id.replaceAll('_', ' ')}'),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const Text(
                    'Allowed placeholders: {{firstName}}, {{eventTitle}}, '
                    '{{manageUrl}}, {{supportEmail}}',
                  ),
                  TextField(
                    controller: subject,
                    decoration: const InputDecoration(
                      labelText: 'Email subject',
                    ),
                  ),
                  TextField(
                    controller: text,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Plain text'),
                  ),
                  TextField(
                    controller: html,
                    maxLines: 8,
                    decoration: const InputDecoration(labelText: 'HTML'),
                  ),
                  TextField(
                    controller: sms,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'SMS'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'subject': subject.text,
                'text': text.text,
                'html': html.text,
                'sms': sms.text,
              }),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (result == null || !context.mounted) return;
      final request = await showDialog<MutationRequest>(
        context: context,
        builder: (_) => const MutationDialog(
          title: 'Publish communication template',
          description:
              'This immediately changes future guest confirmations and is audited.',
        ),
      );
      if (request == null || !context.mounted) return;
      await context.read<AdminApiClient>().postMutation(
        '/v1/communications/templates/$id/publish',
        reason: request.reason,
        confirmed: true,
        values: result,
      );
      reload();
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}
