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
      final response = await context.read<AdminApiClient>().getJson(
        '/v1/metrics',
        query: {'from': day(from), 'to': day(to)},
      );
      final daily =
          ((response['data'] as Map<String, dynamic>)['daily'] as List? ??
          const []);
      if (mounted)
        setState(
          () => rows = daily
              .cast<Map>()
              .map((row) => row.cast<String, dynamic>())
              .toList(),
        );
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
              onPressed: rows.isEmpty ? null : export,
              tooltip: 'Export CSV',
              icon: const Icon(Icons.download),
            ),
          ],
        ),
        const SizedBox(height: 16),
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
  Future<void> export() async {
    final home = Platform.environment['USERPROFILE'];
    if (home == null) return;
    final path =
        '$home\\Downloads\\attendus_analytics_${day(from)}_${day(to)}.csv';
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
    ].join('\r\n');
    await File(path).writeAsBytes(utf8.encode(csv), flush: true);
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CSV exported to $path')));
  }
}
