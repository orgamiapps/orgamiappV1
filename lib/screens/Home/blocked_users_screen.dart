import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/widgets/app_scaffold_wrapper.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/Utils/app_app_bar_view.dart';
import 'package:attendus/widgets/attendus_design_system.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  bool _loading = true;
  List<_BlockedUser> _blocked = [];

  @override
  void initState() {
    super.initState();
    _loadBlocked();
  }

  Future<void> _loadBlocked() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _loading = false;
      });
      return;
    }
    try {
      final snap = await _firestore
          .collection('Customers')
          .doc(uid)
          .collection('blocks')
          .get();
      final items = <_BlockedUser>[];
      for (final d in snap.docs) {
        final targetId = d.id;
        final userDoc = await _firestore
            .collection('Customers')
            .doc(targetId)
            .get();
        final data = userDoc.data() ?? {};
        items.add(
          _BlockedUser(
            uid: targetId,
            name: (data['name'] ?? 'User') as String,
            profilePictureUrl: data['profilePictureUrl'] as String?,
          ),
        );
      }
      setState(() {
        _blocked = items;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _unblock(String blockedUserId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestoreHelper().unblockUser(
      blockerId: uid,
      blockedUserId: blockedUserId,
    );
    if (mounted) {
      setState(() {
        _blocked.removeWhere((e) => e.uid == blockedUserId);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User unblocked')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffoldWrapper(
      selectedBottomNavIndex: 4, // Account tab
      body: SafeArea(
        child: Column(
          children: [
            AppAppBarView.modernHeader(
              context: context,
              title: 'Blocked Users',
              subtitle: 'Manage your blocked users',
              trailing: IconButton(
                onPressed: _openBlockUserSearch,
                icon: const Icon(Icons.add),
                tooltip: 'Block users',
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: _loading
                      ? const AttendUsLoadingState(
                          label: 'Loading blocked users...',
                        )
                      : _blocked.isEmpty
                      ? const AttendUsEmptyState(
                          icon: Icons.block_outlined,
                          title: 'No blocked users',
                          message:
                              'People you block will appear here so you can review or unblock them later.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(20),
                          itemBuilder: (context, i) {
                            final u = _blocked[i];
                            return AttendUsListTile(
                              leading: AttendUsAvatar(
                                name: u.name,
                                imageUrl: u.profilePictureUrl,
                              ),
                              title: u.name,
                              subtitle: 'Blocked account',
                              trailing: TextButton(
                                onPressed: () => _unblock(u.uid),
                                child: const Text('Unblock'),
                              ),
                            );
                          },
                          separatorBuilder: (_, index) =>
                              const SizedBox(height: 10),
                          itemCount: _blocked.length,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openBlockUserSearch() {
    final blockedIds = _blocked.map((e) => e.uid).toSet();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        return AttendUsBottomSheet(
          title: 'Block users',
          subtitle:
              'Search for an account to block. Blocked users can be unblocked from this page.',
          child: _BlockUserSearchSheet(
            initiallyBlockedUserIds: blockedIds,
            onUserBlocked: (CustomerModel user) {
              if (!mounted) return;
              setState(() {
                // Avoid duplicates
                if (_blocked.indexWhere((e) => e.uid == user.uid) == -1) {
                  _blocked.add(
                    _BlockedUser(
                      uid: user.uid,
                      name: user.name,
                      profilePictureUrl: user.profilePictureUrl,
                    ),
                  );
                }
              });
            },
          ),
        );
      },
    );
  }
}

class _BlockedUser {
  final String uid;
  final String name;
  final String? profilePictureUrl;
  _BlockedUser({required this.uid, required this.name, this.profilePictureUrl});
}

class _BlockUserSearchSheet extends StatefulWidget {
  const _BlockUserSearchSheet({
    required this.initiallyBlockedUserIds,
    required this.onUserBlocked,
  });

  final Set<String> initiallyBlockedUserIds;
  final void Function(CustomerModel user) onUserBlocked;

  @override
  State<_BlockUserSearchSheet> createState() => _BlockUserSearchSheetState();
}

class _BlockUserSearchSheetState extends State<_BlockUserSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  final _auth = FirebaseAuth.instance;
  Timer? _debounce;
  bool _isLoading = false;
  List<CustomerModel> _results = [];
  late Set<String> _blockedIds;

  @override
  void initState() {
    super.initState();
    _blockedIds = {...widget.initiallyBlockedUserIds};
    // Initial load of discoverable users
    _performSearch('');
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(_searchController.text.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final users = await FirebaseFirestoreHelper().searchUsers(
        searchQuery: query,
        limit: 50,
      );
      final currentUid = _auth.currentUser?.uid;
      // Filter out self
      final filtered = users.where((u) => u.uid != currentUid).toList();
      if (!mounted) return;
      setState(() {
        _results = filtered;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _blockUser(CustomerModel user) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestoreHelper().blockUser(
        blockerId: uid,
        blockedUserId: user.uid,
      );
      if (!mounted) return;
      setState(() {
        _blockedIds.add(user.uid);
      });
      widget.onUserBlocked(user);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User blocked')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to block user')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AttendUsSearchField(
          controller: _searchController,
          hintText: 'Search users by name or @username',
        ),
        const SizedBox(height: 12),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: AttendUsLoadingState(label: 'Searching users...'),
          )
        else
          Flexible(
            child: _results.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: AttendUsEmptyState(
                      icon: Icons.person_search_outlined,
                      title: 'No users found',
                      message: 'Try a different name or username.',
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _results.length,
                    separatorBuilder: (context, _) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final user = _results[index];
                      final isBlocked = _blockedIds.contains(user.uid);
                      return AttendUsListTile(
                        leading: AttendUsAvatar(
                          name: user.name,
                          imageUrl: user.profilePictureUrl,
                        ),
                        title: user.name,
                        subtitle:
                            user.username != null && user.username!.isNotEmpty
                            ? '@${user.username}'
                            : 'Attendus member',
                        trailing: isBlocked
                            ? const AttendUsStatusBadge(
                                label: 'Blocked',
                                tone: AttendUsStatusTone.warning,
                              )
                            : TextButton(
                                onPressed: () => _blockUser(user),
                                child: const Text('Block'),
                              ),
                      );
                    },
                  ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}
