import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/firebase/organization_helper.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/customer_model.dart';

class JoinRequestsScreen extends StatefulWidget {
  final String organizationId;
  const JoinRequestsScreen({super.key, required this.organizationId});

  @override
  State<JoinRequestsScreen> createState() => _JoinRequestsScreenState();
}

class _JoinRequestsScreenState extends State<JoinRequestsScreen> {
  final OrganizationHelper _helper = OrganizationHelper();
  bool _loading = true;
  List<Map<String, dynamic>> _requests = [];
  Map<String, CustomerModel> _userById = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'pending'; // pending | declined | all
  final Set<String> _processing = <String>{};
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _subscribeToRequests();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _subscription?.cancel();
    super.dispose();
  }

  void _subscribeToRequests() {
    setState(() => _loading = true);
    _subscription?.cancel();
    final query = FirebaseFirestore.instance
        .collection('Organizations')
        .doc(widget.organizationId)
        .collection('JoinRequests')
        .orderBy('createdAt', descending: true);

    _subscription = query.snapshots().listen(
      (snapshot) async {
        final List<Map<String, dynamic>> items = snapshot.docs
            .map((d) => d.data())
            .toList();

        // Determine which user IDs we need to fetch that we don't already have
        final List<String> allIds = items
            .map((r) => (r['userId'] ?? '').toString())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
        final List<String> missing = allIds
            .where((id) => !_userById.containsKey(id))
            .toList();

        Map<String, CustomerModel> fetched = {};
        if (missing.isNotEmpty) {
          try {
            final users = await FirebaseFirestoreHelper().getUsersByIds(
              userIds: missing,
            );
            for (final u in users) {
              fetched[u.uid] = u;
            }
          } catch (_) {}
        }

        if (!mounted) return;
        setState(() {
          _requests = items;
          if (fetched.isNotEmpty) {
            _userById.addAll(fetched);
          }
          _loading = false;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _loading = false);
      },
    );
  }

  Future<void> _refreshUsers() async {
    try {
      final List<String> ids = _requests
          .map((r) => (r['userId'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (ids.isEmpty) return;
      final users = await FirebaseFirestoreHelper().getUsersByIds(userIds: ids);
      if (!mounted) return;
      setState(() {
        final Map<String, CustomerModel> refreshed = {};
        for (final u in users) {
          refreshed[u.uid] = u;
        }
        _userById = refreshed;
      });
    } catch (_) {}
  }

  List<Map<String, dynamic>> _filteredRequests() {
    final List<Map<String, dynamic>> source = List<Map<String, dynamic>>.from(
      _requests,
    );

    // Filter by status
    final List<Map<String, dynamic>> byStatus = _statusFilter == 'all'
        ? source
        : source
              .where((r) => (r['status'] ?? 'pending') == _statusFilter)
              .toList();

    // Filter by search query (name or username or userId)
    if (_searchQuery.trim().isEmpty) {
      return byStatus;
    }
    final q = _searchQuery.toLowerCase().trim();
    return byStatus.where((r) {
      final uid = (r['userId'] ?? '').toString();
      final user = _userById[uid];
      final name = user?.name.toLowerCase() ?? '';
      final username = user?.username?.toLowerCase() ?? '';
      return name.contains(q) ||
          username.contains(q) ||
          uid.toLowerCase().contains(q);
    }).toList();
  }

  Map<String, int> _computeCounts() {
    int pending = 0;
    int declined = 0;
    for (final r in _requests) {
      final s = (r['status'] ?? 'pending').toString();
      if (s == 'pending') pending++;
      if (s == 'declined') declined++;
    }
    return <String, int>{
      'pending': pending,
      'declined': declined,
      'all': _requests.length,
    };
  }

  String _relativeTime(dynamic createdAt) {
    try {
      DateTime ts;
      if (createdAt is Timestamp) {
        ts = createdAt.toDate();
      } else if (createdAt is DateTime) {
        ts = createdAt;
      } else if (createdAt is String) {
        ts = DateTime.tryParse(createdAt) ?? DateTime.now();
      } else {
        ts = DateTime.now();
      }

      final Duration diff = DateTime.now().difference(ts);
      if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      final int weeks = (diff.inDays / 7).floor();
      if (weeks < 5) return '${weeks}w ago';
      final int months = (diff.inDays / 30).floor();
      if (months < 12) return '${months}mo ago';
      final int years = (diff.inDays / 365).floor();
      return '${years}y ago';
    } catch (_) {
      return '';
    }
  }

  Future<void> _approve(String userId) async {
    if (_processing.contains(userId)) return;
    setState(() => _processing.add(userId));
    final ok = await _helper.approveJoinRequest(widget.organizationId, userId);
    if (mounted) {
      setState(() => _processing.remove(userId));
      if (ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Request approved')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to approve request')),
        );
      }
    }
  }

  Future<void> _decline(String userId) async {
    if (_processing.contains(userId)) return;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Decline request?'),
        content: const Text(
          'Are you sure you want to decline this join request?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _processing.add(userId));
    final ok = await _helper.declineJoinRequest(widget.organizationId, userId);
    if (mounted) {
      setState(() => _processing.remove(userId));
      if (ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Request declined')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to decline request')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final counts = _computeCounts();
    final filtered = _filteredRequests();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Join Requests${counts['pending'] != null && counts['pending']! > 0 ? ' (${counts['pending']})' : ''}',
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.inbox_outlined, size: 72, color: Colors.grey),
                    SizedBox(height: 12),
                    Text(
                      'No join requests',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'When users request to join your group, they will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by name or @username',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text('Pending (${counts['pending']})'),
                        selected: _statusFilter == 'pending',
                        onSelected: (_) =>
                            setState(() => _statusFilter = 'pending'),
                      ),
                      ChoiceChip(
                        label: Text('Declined (${counts['declined']})'),
                        selected: _statusFilter == 'declined',
                        onSelected: (_) =>
                            setState(() => _statusFilter = 'declined'),
                      ),
                      ChoiceChip(
                        label: Text('All (${counts['all']})'),
                        selected: _statusFilter == 'all',
                        onSelected: (_) =>
                            setState(() => _statusFilter = 'all'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 0),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refreshUsers,
                    child: filtered.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 120),
                              Center(
                                child: Text('No requests match your filters'),
                              ),
                            ],
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 0),
                            itemBuilder: (context, i) {
                              final r = filtered[i];
                              final userId = (r['userId'] ?? '').toString();
                              final status = (r['status'] ?? 'pending')
                                  .toString();
                              final createdAt = r['createdAt'];
                              final user = _userById[userId];
                              final title = user?.name ?? userId;
                              final username =
                                  (user?.username != null &&
                                      user!.username!.isNotEmpty)
                                  ? '@${user.username}'
                                  : null;
                              final time = _relativeTime(createdAt);
                              final bool isPending = status == 'pending';
                              final bool isBusy = _processing.contains(userId);

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final double width = constraints.maxWidth;
                                    final bool showLabels = width >= 360;
                                    return Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          radius: 22,
                                          backgroundImage:
                                              user?.profilePictureUrl != null
                                              ? NetworkImage(
                                                  user!.profilePictureUrl!,
                                                )
                                              : null,
                                          child: user?.profilePictureUrl == null
                                              ? const Icon(Icons.person)
                                              : null,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      title,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: isPending
                                                          ? const Color(
                                                              0xFFFF9800,
                                                            ).withValues(
                                                              alpha: 0.12,
                                                            )
                                                          : const Color(
                                                              0xFF9E9E9E,
                                                            ).withValues(
                                                              alpha: 0.12,
                                                            ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            999,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      status,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: isPending
                                                            ? Colors
                                                                  .orange
                                                                  .shade700
                                                            : Colors
                                                                  .grey
                                                                  .shade700,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  if (username != null)
                                                    Flexible(
                                                      child: Text(
                                                        username,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          color: Colors.grey,
                                                        ),
                                                      ),
                                                    ),
                                                  if (username != null &&
                                                      time.isNotEmpty)
                                                    const Padding(
                                                      padding:
                                                          EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                          ),
                                                      child: Text(
                                                        '·',
                                                        style: TextStyle(
                                                          color: Colors.grey,
                                                        ),
                                                      ),
                                                    ),
                                                  if (time.isNotEmpty)
                                                    Text(
                                                      time,
                                                      style: const TextStyle(
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.end,
                                                children: [
                                                  if (isPending) ...[
                                                    if (showLabels)
                                                      OutlinedButton.icon(
                                                        onPressed: isBusy
                                                            ? null
                                                            : () => _decline(
                                                                userId,
                                                              ),
                                                        icon: const Icon(
                                                          Icons.close,
                                                          size: 18,
                                                        ),
                                                        label: const Text(
                                                          'Deny',
                                                        ),
                                                        style: OutlinedButton.styleFrom(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 10,
                                                                vertical: 8,
                                                              ),
                                                          minimumSize:
                                                              const Size(0, 36),
                                                        ),
                                                      )
                                                    else
                                                      IconButton(
                                                        tooltip: 'Deny',
                                                        onPressed: isBusy
                                                            ? null
                                                            : () => _decline(
                                                                userId,
                                                              ),
                                                        icon: const Icon(
                                                          Icons.close,
                                                        ),
                                                      ),
                                                    const SizedBox(width: 8),
                                                    if (showLabels)
                                                      FilledButton.icon(
                                                        onPressed: isBusy
                                                            ? null
                                                            : () => _approve(
                                                                userId,
                                                              ),
                                                        icon: const Icon(
                                                          Icons.check,
                                                          size: 18,
                                                        ),
                                                        label: const Text(
                                                          'Approve',
                                                        ),
                                                        style: FilledButton.styleFrom(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 12,
                                                                vertical: 10,
                                                              ),
                                                          minimumSize:
                                                              const Size(0, 36),
                                                        ),
                                                      )
                                                    else
                                                      IconButton(
                                                        tooltip: 'Approve',
                                                        onPressed: isBusy
                                                            ? null
                                                            : () => _approve(
                                                                userId,
                                                              ),
                                                        icon: const Icon(
                                                          Icons.check,
                                                        ),
                                                      ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}
