import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/api_models.dart';
import '../services/admin_api_client.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? data;
  ApiException? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final response = await context.read<AdminApiClient>().getJson(
        '/v1/metrics',
      );
      if (mounted) {
        setState(
          () =>
              data = ((response['data'] as Map)['current'] as Map? ?? const {})
                  .cast<String, dynamic>(),
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Dashboard',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            IconButton(
              tooltip: 'Refresh dashboard',
              onPressed: load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48),
                      Text(error!.message),
                      FilledButton(onPressed: load, child: const Text('Retry')),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      _Metric('Total users', data?['usersTotal'], Icons.people),
                      _Metric(
                        'DAU / WAU / MAU',
                        '${data?['dau'] ?? '—'} / ${data?['wau'] ?? '—'} / ${data?['mau'] ?? '—'}',
                        Icons.timeline,
                      ),
                      _Metric('Events', data?['eventsTotal'], Icons.event),
                      _Metric(
                        'Registrations',
                        data?['registrationsTotal'],
                        Icons.how_to_reg,
                      ),
                      _Metric(
                        'Check-ins',
                        data?['checkInsTotal'],
                        Icons.qr_code_scanner,
                      ),
                      _Metric(
                        'Basic / Premium',
                        '${data?['activeBasic'] ?? '—'} / ${data?['activePremium'] ?? '—'}',
                        Icons.workspace_premium,
                      ),
                      _Metric(
                        'MRR / ARR',
                        '${data?['mrr'] ?? '—'} / ${data?['arr'] ?? '—'}',
                        Icons.payments,
                      ),
                      _Metric('Churn', data?['churnRate'], Icons.trending_down),
                      _Metric('Groups', data?['groupsTotal'], Icons.groups),
                      _Metric('Open reports', data?['openReports'], Icons.flag),
                    ],
                  ),
                ),
        ),
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon);
  final String label;
  final dynamic value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 260,
    height: 132,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(radius: 24, child: Icon(icon)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label),
                  const SizedBox(height: 8),
                  Text(
                    value?.toString() ?? '—',
                    style: Theme.of(context).textTheme.headlineSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
