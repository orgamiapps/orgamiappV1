import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/permissions.dart';
import '../models/api_models.dart';
import '../services/admin_api_client.dart';
import '../services/session_controller.dart';
import 'mutation_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final uid = TextEditingController();
  final selected = <AdminRole>{AdminRole.support};
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Administrator settings',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: const Icon(Icons.account_circle),
            title: Text(session.user?.email ?? 'Administrator'),
            subtitle: Text(
              'Roles: ${session.permissions.roles.map((r) => r.wire).join(', ')}',
            ),
            trailing: OutlinedButton.icon(
              onPressed: session.signOut,
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.security),
            title: const Text('Security model'),
            subtitle: const Text(
              'Firebase ID tokens are checked on every request. Permissions are loaded server-side. All mutations require reason, confirmation, idempotency, and an audit record.',
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (session.permissions.roleManagement)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Role management',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Assign roles to an existing Firebase Auth UID. This action is limited to super administrators.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: uid,
                    decoration: const InputDecoration(
                      labelText: 'Target Firebase UID',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: AdminRole.values
                        .map(
                          (role) => FilterChip(
                            label: Text(role.wire),
                            selected: selected.contains(role),
                            onSelected: (value) => setState(
                              () => value
                                  ? selected.add(role)
                                  : selected.remove(role),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed:
                          busy || uid.text.trim().isEmpty || selected.isEmpty
                          ? null
                          : assign,
                      icon: const Icon(Icons.admin_panel_settings),
                      label: const Text('Assign selected roles'),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> assign() async {
    final confirmation = await showDialog<MutationRequest>(
      context: context,
      builder: (_) => const MutationDialog(
        title: 'Confirm role assignment',
        description:
            'The target will receive the selected administrative permissions after their token refresh.',
      ),
    );
    if (confirmation == null || !mounted) return;
    setState(() => busy = true);
    try {
      await context.read<AdminApiClient>().postMutation(
        '/v1/accounts/${uid.text.trim()}/roles',
        reason: confirmation.reason,
        confirmed: true,
        values: {'roles': selected.map((r) => r.wire).toList(), 'active': true},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Roles assigned and audited.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
