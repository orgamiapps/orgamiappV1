import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/api_models.dart';
import '../services/admin_api_client.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late DateTime from = DateTime.now().subtract(const Duration(days: 30));
  late DateTime to = DateTime.now();
  List<Map<String, dynamic>> rows = const [];
  Map<String, dynamic> funnel = const {};
  List<Map<String, dynamic>> markets = const [];
  bool loading = true;
  ApiException? error;
  static const columns = [
    'date',
    'usersTotal',
    'dau',
    'wau',
    'mau',
    'eventsTotal',
    'registrationsTotal',
    'checkInsTotal',
    'activeBasic',
    'activePremium',
    'trialConversion',
    'churnRate',
    'mrr',
    'arr',
    'refunds',
    'failedPayments',
    'groupsTotal',
    'openReports',
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  String day(DateTime value) => value.toIso8601String().substring(0, 10);
  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final client = context.read<AdminApiClient>();
      final response = await client.getJson(
        '/v1/metrics',
        query: {'from': day(from), 'to': day(to)},
      );
      final funnelResponse = await client.getJson(
        '/v1/guest-funnel',
        query: {'from': day(from), 'to': day(to)},
      );
      final marketResponse = await client.getJson(
        '/v1/discovery/market-health',
      );
      final daily =
          ((response['data'] as Map<String, dynamic>)['daily'] as List? ??
          const []);
      if (mounted) {
        setState(
          () => rows = daily
              .cast<Map>()
              .map((row) => row.cast<String, dynamic>())
              .toList(),
        );
        setState(
          () => markets = (marketResponse['data'] as List? ?? const [])
              .cast<Map>()
              .map((row) => row.cast<String, dynamic>())
              .toList(),
        );
        setState(
          () => funnel = Map<String, dynamic>.from(
            funnelResponse['data'] as Map? ?? const {},
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> pick(bool start) async {
    final value = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: start ? from : to,
    );
    if (value != null) {
      setState(() => start ? from = value : to = value);
      await load();
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
                'Analytics',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => pick(true),
              icon: const Icon(Icons.date_range),
              label: Text('From ${day(from)}'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => pick(false),
              icon: const Icon(Icons.event),
              label: Text('To ${day(to)}'),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: rows.isEmpty && funnel.isEmpty ? null : export,
              tooltip: 'Export CSV',
              icon: const Icon(Icons.download),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (funnel.isNotEmpty) ...[
          _buildFunnelSummary(context),
          const SizedBox(height: 16),
        ],
        if (markets.isNotEmpty) ...[
          _buildMarketHealth(context),
          const SizedBox(height: 16),
        ],
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error!.message),
                      FilledButton.icon(
                        onPressed: load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : rows.isEmpty
              ? const Center(
                  child: Text(
                    'No aggregate metrics exist for this date range.',
                  ),
                )
              : Card(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: DataTable(
                        columns: columns
                            .map((column) => DataColumn(label: Text(column)))
                            .toList(),
                        rows: rows
                            .map(
                              (row) => DataRow(
                                cells: columns
                                    .map(
                                      (column) => DataCell(
                                        SelectableText(
                                          row[column]?.toString() ?? '—',
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    ),
  );

  Widget _buildFunnelSummary(BuildContext context) {
    final totals = Map<String, dynamic>.from(
      funnel['totals'] as Map? ?? const {},
    );
    final conversion = Map<String, dynamic>.from(
      funnel['conversion'] as Map? ?? const {},
    );
    final methods = Map<String, dynamic>.from(
      funnel['byCheckInMethod'] as Map? ?? const {},
    );
    String percent(dynamic value) =>
        '${((value as num? ?? 0) * 100).toStringAsFixed(1)}%';
    Widget metric(String label, String value) => SizedBox(
      width: 180,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Guest conversion funnel',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            metric('Guest sessions', '${funnel['sessions'] ?? 0}'),
            metric('Discover views', '${totals['guest_discover_view'] ?? 0}'),
            metric('Auth conversion', percent(conversion['auth'])),
            metric('Check-in success', percent(conversion['checkIn'])),
          ],
        ),
        if (methods.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Check-in methods: ${methods.entries.map((entry) => '${entry.key}: ${entry.value}').join('  •  ')}',
          ),
        ],
      ],
    );
  }

  Widget _buildMarketHealth(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Discovery market health',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 190,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: markets.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, index) {
            final market = markets[index];
            final healthy = market['healthy'] == true;
            final noResult = ((market['noResultRate'] as num? ?? 0) * 100)
                .toStringAsFixed(1);
            return SizedBox(
              width: 250,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${market['city']}, ${market['regionCode']}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Icon(
                            healthy ? Icons.check_circle : Icons.warning_amber,
                            color: healthy ? Colors.green : Colors.orange,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text('${market['upcomingInventory']} upcoming events'),
                      Text('${market['activeOrganizers']} active organizers'),
                      Text('$noResult% no-result rate'),
                      Text('${market['registrations']} registrations'),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ],
  );

  Future<void> export() async {
    final home = Platform.environment['USERPROFILE'];
    if (home == null) return;
    final path =
        '$home\\Downloads\\attendus_analytics_${day(from)}_${day(to)}.csv';
    final funnelTotals = Map<String, dynamic>.from(
      funnel['totals'] as Map? ?? const {},
    );
    final csv = [
      columns.join(','),
      ...rows.map(
        (row) => columns
            .map(
              (column) =>
                  '"${(row[column] ?? '').toString().replaceAll('"', '""')}"',
            )
            .join(','),
      ),
      '',
      'guestFunnelMetric,value',
      'sessions,${funnel['sessions'] ?? 0}',
      ...funnelTotals.entries.map((entry) => '${entry.key},${entry.value}'),
    ].join('\r\n');
    await File(path).writeAsBytes(utf8.encode(csv), flush: true);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CSV exported to $path')));
    }
  }
}
