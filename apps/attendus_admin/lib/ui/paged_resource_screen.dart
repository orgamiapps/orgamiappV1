import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/api_models.dart';
import '../services/admin_api_client.dart';

class PagedResourceScreen extends StatefulWidget {
  const PagedResourceScreen({
    super.key,
    required this.title,
    required this.path,
    required this.columns,
    this.searchable = false,
    this.rowActions,
  });
  final String title, path;
  final List<String> columns;
  final bool searchable;
  final List<Widget> Function(BuildContext, Map<String, dynamic>, VoidCallback)?
  rowActions;
  @override
  State<PagedResourceScreen> createState() => _PagedResourceScreenState();
}

class _PagedResourceScreenState extends State<PagedResourceScreen> {
  final search = TextEditingController();
  final tokens = <String?>[null];
  int pageIndex = 0;
  AdminPage? page;
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
      final result = await context.read<AdminApiClient>().page(
        widget.path,
        search: search.text.trim(),
        pageToken: tokens[pageIndex],
      );
      if (mounted) setState(() => page = result);
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
                widget.title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            if (widget.searchable)
              SizedBox(
                width: 360,
                child: SearchBar(
                  controller: search,
                  hintText: 'Search by email, UID, or name',
                  leading: const Icon(Icons.search),
                  onSubmitted: (_) {
                    tokens
                      ..clear()
                      ..add(null);
                    pageIndex = 0;
                    load();
                  },
                ),
              ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Refresh',
              onPressed: load,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Export current page to CSV',
              onPressed: page?.items.isNotEmpty == true ? exportCsv : null,
              icon: const Icon(Icons.download),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Expanded(child: _body()),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Page ${pageIndex + 1}'),
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'Previous page',
              onPressed: pageIndex > 0
                  ? () {
                      setState(() => pageIndex--);
                      load();
                    }
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Next page',
              onPressed: page?.nextPageToken != null
                  ? () {
                      if (tokens.length == pageIndex + 1) {
                        tokens.add(page!.nextPageToken);
                      }
                      setState(() => pageIndex++);
                      load();
                    }
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    ),
  );
  Widget _body() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              error!.isOffline ? Icons.cloud_off : Icons.error_outline,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(error!.message),
            if (error!.requestId != null)
              SelectableText('Request ID: ${error!.requestId}'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (page?.items.isEmpty ?? true) {
      return const Center(child: Text('No results found.'));
    }
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            columns: [
              ...widget.columns.map((c) => DataColumn(label: Text(_label(c)))),
              if (widget.rowActions != null)
                const DataColumn(label: Text('Actions')),
            ],
            rows: page!.items
                .map(
                  (row) => DataRow(
                    cells: [
                      ...widget.columns.map(
                        (c) => DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 240),
                            child: SelectableText(_value(row[c]), maxLines: 3),
                          ),
                        ),
                      ),
                      if (widget.rowActions != null)
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: widget.rowActions!(context, row, load),
                          ),
                        ),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  String _label(String value) => value
      .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[1]}')
      .replaceFirstMapped(RegExp(r'^.'), (m) => m[0]!.toUpperCase());
  String _value(dynamic value) => value == null
      ? '—'
      : value is Iterable
      ? value.join(', ')
      : value.toString();
  Future<void> exportCsv() async {
    final rows = [
      widget.columns.join(','),
      ...page!.items.map(
        (row) => widget.columns
            .map((key) => '"${_value(row[key]).replaceAll('"', '""')}"')
            .join(','),
      ),
    ];
    final home = Platform.environment['USERPROFILE'];
    if (home == null) return;
    final safeName = widget.title.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '_',
    );
    final path =
        '$home\\Downloads\\${safeName}_${DateTime.now().millisecondsSinceEpoch}.csv';
    await File(path).writeAsBytes(utf8.encode(rows.join('\r\n')), flush: true);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CSV exported to $path')));
    }
  }
}
