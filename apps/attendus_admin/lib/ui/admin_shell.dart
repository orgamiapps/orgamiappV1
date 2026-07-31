import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/api_models.dart';
import '../services/admin_api_client.dart';
import '../services/session_controller.dart';
import 'dashboard_screen.dart';
import 'analytics_screen.dart';
import 'mutation_dialog.dart';
import 'paged_resource_screen.dart';
import 'settings_screen.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.onThemeChanged});
  final VoidCallback onThemeChanged;
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int selected = 0;
  @override
  Widget build(BuildContext context) {
    final permissions = context.watch<SessionController>().permissions;
    final destinations = <_Destination>[
      const _Destination(
        'Dashboard',
        Icons.dashboard_outlined,
        DashboardScreen(),
      ),
      if (permissions.accountsRead)
        _Destination(
          'Accounts',
          Icons.people_outline,
          PagedResourceScreen(
            title: 'Accounts',
            path: '/v1/accounts',
            searchable: true,
            columns: const [
              'uid',
              'email',
              'displayName',
              'disabled',
              'emailVerified',
              'lastSignInAt',
            ],
            rowActions: accountActions,
          ),
        ),
      if (permissions.subscriptionsRead)
        _Destination(
          'Subscriptions',
          Icons.credit_card,
          PagedResourceScreen(
            title: 'Subscriptions & billing',
            path: '/v1/subscriptions',
            searchable: true,
            columns: const [
              'userId',
              'planId',
              'tier',
              'status',
              'stripeCustomerId',
              'stripeSubscriptionId',
              'currentPeriodEnd',
              'paymentState',
            ],
            rowActions: permissions.subscriptionsMutate
                ? subscriptionActions
                : null,
          ),
        ),
      if (permissions.analyticsRead)
        const _Destination(
          'Analytics',
          Icons.analytics_outlined,
          AnalyticsScreen(),
        ),
      if (permissions.moderation)
        _Destination(
          'Moderation',
          Icons.flag_outlined,
          PagedResourceScreen(
            title: 'Reports & moderation',
            path: '/v1/reports',
            columns: [
              'id',
              'type',
              'reason',
              'status',
              'reporterUid',
              'targetUid',
              'eventId',
              'createdAt',
            ],
            rowActions: moderationActions,
          ),
        ),
      if (permissions.moderation)
        _Destination(
          'Events',
          Icons.event_outlined,
          PagedResourceScreen(
            title: 'Events',
            path: '/v1/events',
            columns: [
              'id',
              'title',
              'status',
              'customerUid',
              'organizationId',
              'selectedDateTime',
              'private',
              'issuedTickets',
            ],
            rowActions: eventActions,
          ),
        ),
      if (permissions.moderation)
        _Destination(
          'Organizations',
          Icons.groups_outlined,
          PagedResourceScreen(
            title: 'Organizations',
            path: '/v1/organizations',
            columns: [
              'id',
              'name',
              'category',
              'createdBy',
              'createdAt',
              'defaultEventVisibility',
            ],
            rowActions: organizationActions,
          ),
        ),
      const _Destination(
        'Audit logs',
        Icons.history,
        PagedResourceScreen(
          title: 'Immutable audit logs',
          path: '/v1/audit-logs',
          columns: [
            'id',
            'actorEmail',
            'actorRoles',
            'action',
            'targetType',
            'targetId',
            'reason',
            'requestId',
            'createdAt',
          ],
        ),
      ),
      const _Destination(
        'Operations',
        Icons.build_outlined,
        PagedResourceScreen(
          title: 'Operations & jobs',
          path: '/v1/jobs',
          columns: [
            'id',
            'type',
            'status',
            'targetUid',
            'requestedBy',
            'createdAt',
            'startedAt',
            'completedAt',
            'errorCode',
          ],
        ),
      ),
      const _Destination('Settings', Icons.settings_outlined, SettingsScreen()),
    ];
    if (selected >= destinations.length) selected = 0;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: MediaQuery.sizeOf(context).width >= 1500,
            selectedIndex: selected,
            onDestinationSelected: (value) => setState(() => selected = value),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Image.asset(
                'assets/attendus_logo.png',
                width: 44,
                height: 44,
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: IconButton(
                    tooltip: 'Toggle light/dark theme',
                    onPressed: widget.onThemeChanged,
                    icon: const Icon(Icons.brightness_6_outlined),
                  ),
                ),
              ),
            ),
            destinations: destinations
                .map(
                  (item) => NavigationRailDestination(
                    icon: Icon(item.icon),
                    label: Text(item.label),
                  ),
                )
                .toList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: SafeArea(child: destinations[selected].screen)),
        ],
      ),
    );
  }

  static List<Widget> accountActions(
    BuildContext context,
    Map<String, dynamic> row,
    VoidCallback reload,
  ) => [
    PopupMenuButton<String>(
      tooltip: 'Account actions',
      onSelected: (action) => _accountMutation(context, row, action, reload),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'view', child: Text('View details')),
        if (context.read<SessionController>().permissions.accountsMutate) ...[
          PopupMenuItem(
            value: row['disabled'] == true ? 'enable' : 'disable',
            child: Text(
              row['disabled'] == true ? 'Enable account' : 'Disable account',
            ),
          ),
          const PopupMenuItem(
            value: 'revoke-sessions',
            child: Text('Revoke sessions'),
          ),
          const PopupMenuItem(
            value: 'password-reset',
            child: Text('Generate password reset'),
          ),
          const PopupMenuItem(
            value: 'anonymize',
            child: Text('Begin anonymization'),
          ),
        ],
      ],
    ),
  ];
  static Future<void> _accountMutation(
    BuildContext context,
    Map<String, dynamic> row,
    String action,
    VoidCallback reload,
  ) async {
    if (action == 'view') {
      try {
        final response = await context.read<AdminApiClient>().getJson(
          '/v1/accounts/${row['uid']}',
        );
        if (context.mounted)
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(row['email']?.toString() ?? row['uid'].toString()),
              content: SizedBox(
                width: 700,
                child: SingleChildScrollView(
                  child: SelectableText(
                    const JsonEncoder.withIndent(
                      '  ',
                    ).convert(response['data']),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
      } on ApiException catch (e) {
        if (context.mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    final request = await showDialog<MutationRequest>(
      context: context,
      builder: (_) => MutationDialog(
        title: 'Confirm ${action.replaceAll('-', ' ')}',
        description:
            'This operation affects ${row['email'] ?? row['uid']} and will be recorded in the immutable audit log.',
      ),
    );
    if (request == null || !context.mounted) return;
    try {
      final result = await context.read<AdminApiClient>().postMutation(
        '/v1/accounts/${row['uid']}/$action',
        reason: request.reason,
        confirmed: true,
      );
      if (context.mounted) {
        final data = result['data'] as Map?;
        final reset = data?['resetLink'];
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Action completed'),
            content: reset == null
                ? const Text('The action completed and was audited.')
                : SelectableText('Approved password-reset link:\n$reset'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
        reload();
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${e.message}${e.requestId == null ? '' : ' (${e.requestId})'}',
            ),
          ),
        );
      }
    }
  }

  static List<Widget> subscriptionActions(
    BuildContext context,
    Map<String, dynamic> row,
    VoidCallback reload,
  ) => [
    PopupMenuButton<String>(
      tooltip: 'Billing actions',
      onSelected: (action) =>
          _subscriptionMutation(context, row, action, reload),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'cancel',
          child: Text('Cancel at period end'),
        ),
        const PopupMenuItem(value: 'reactivate', child: Text('Reactivate')),
        const PopupMenuItem(
          value: 'change-plan',
          child: Text('Schedule plan change'),
        ),
        const PopupMenuItem(
          value: 'sync',
          child: Text('Synchronize from Stripe'),
        ),
        const PopupMenuItem(value: 'refund', child: Text('Refund payment')),
      ],
    ),
  ];
  static Future<void> _subscriptionMutation(
    BuildContext context,
    Map<String, dynamic> row,
    String action,
    VoidCallback reload,
  ) async {
    final extra = <String, dynamic>{};
    if (action == 'change-plan' || action == 'refund') {
      final value = await _valueDialog(
        context,
        action == 'change-plan' ? 'Plan alias' : 'Stripe payment intent ID',
        action == 'change-plan' ? 'premium_monthly' : 'pi_...',
      );
      if (value == null || !context.mounted) return;
      extra[action == 'change-plan' ? 'planId' : 'paymentIntentId'] = value;
    }
    final request = await showDialog<MutationRequest>(
      context: context,
      builder: (_) => MutationDialog(
        title: 'Confirm billing operation',
        description:
            'Stripe is the source of truth. No client-supplied amount or entitlement will be accepted.',
      ),
    );
    if (request == null || !context.mounted) return;
    try {
      await context.read<AdminApiClient>().postMutation(
        '/v1/subscriptions/${row['userId']}/$action',
        reason: request.reason,
        confirmed: true,
        values: extra,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Billing action completed and audited.'),
          ),
        );
        reload();
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  static Future<String?> _valueDialog(
    BuildContext context,
    String title,
    String hint,
  ) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  static List<Widget> moderationActions(
    BuildContext context,
    Map<String, dynamic> row,
    VoidCallback reload,
  ) => [
    PopupMenuButton<String>(
      tooltip: 'Moderation actions',
      onSelected: (action) => _moderationMutation(
        context,
        '/v1/reports/${row['id']}/$action',
        action,
        reload,
      ),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'resolve', child: Text('Resolve report')),
        PopupMenuItem(value: 'dismiss', child: Text('Dismiss report')),
      ],
    ),
  ];
  static List<Widget> eventActions(
    BuildContext context,
    Map<String, dynamic> row,
    VoidCallback reload,
  ) => [
    IconButton(
      tooltip: 'Unpublish event',
      onPressed: () => _moderationMutation(
        context,
        '/v1/events/${row['id']}/unpublish',
        'unpublish event',
        reload,
      ),
      icon: const Icon(Icons.visibility_off_outlined),
    ),
  ];
  static List<Widget> organizationActions(
    BuildContext context,
    Map<String, dynamic> row,
    VoidCallback reload,
  ) => [
    IconButton(
      tooltip: 'Suspend organization',
      onPressed: () => _moderationMutation(
        context,
        '/v1/organizations/${row['id']}/suspend',
        'suspend organization',
        reload,
      ),
      icon: const Icon(Icons.block),
    ),
  ];
  static Future<void> _moderationMutation(
    BuildContext context,
    String path,
    String action,
    VoidCallback reload,
  ) async {
    final request = await showDialog<MutationRequest>(
      context: context,
      builder: (_) => MutationDialog(
        title: 'Confirm $action',
        description:
            'This moderation action changes public platform state and will be audited.',
      ),
    );
    if (request == null || !context.mounted) return;
    try {
      await context.read<AdminApiClient>().postMutation(
        path,
        reason: request.reason,
        confirmed: true,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Moderation action completed and audited.'),
          ),
        );
        reload();
      }
    } on ApiException catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.screen);
  final String label;
  final IconData icon;
  final Widget screen;
}
