import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/customer_model.dart';

class SuggestedContactsScreen extends StatefulWidget {
  const SuggestedContactsScreen({super.key});

  @override
  State<SuggestedContactsScreen> createState() =>
      _SuggestedContactsScreenState();
}

class _SuggestedContactsScreenState extends State<SuggestedContactsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String? _ownerUid;
  StreamSubscription<User?>? _authSubscription;
  bool _accountChanged = false;
  bool get _currentAccount =>
      mounted &&
      !_accountChanged &&
      FirebaseAuth.instance.currentUser?.uid == _ownerUid;

  List<CustomerModel> _users = [];
  List<CustomerModel> _filtered = [];
  bool _isLoading = true;
  final Map<String, bool> _followStatus = {};
  final Set<String> _pendingFollows = {};

  @override
  void initState() {
    super.initState();
    _ownerUid = FirebaseAuth.instance.currentUser?.uid;
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (mounted && user?.uid != _ownerUid) {
        setState(() => _accountChanged = true);
      }
    });
    _loadSuggestions();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    setState(() => _isLoading = true);
    try {
      // Placeholder strategy: show popular discoverable users (or recently active)
      // You can later replace with actual contact-matched list
      final users = await FirebaseFirestoreHelper().searchUsers(
        searchQuery: '',
      );
      if (!_currentAccount) return;
      final currentId = _ownerUid;
      _users = users
          .where((u) => u.uid != currentId && (u.isDiscoverable))
          .toList();
      _filtered = List.from(_users);
      await _loadFollowStatuses(_filtered);
    } catch (_) {
      if (mounted && _currentAccount) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load people. Reopen to retry.'),
          ),
        );
      }
    } finally {
      if (mounted && _currentAccount) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadFollowStatuses(List<CustomerModel> users) async {
    final myId = _ownerUid;
    if (myId == null) return;
    for (final user in users) {
      final isFollowing = await FirebaseFirestoreHelper().isFollowingUser(
        followerId: myId,
        followingId: user.uid,
      );
      if (!_currentAccount) return;
      _followStatus[user.uid] = isFollowing;
    }
    if (mounted && _currentAccount) setState(() {});
  }

  void _onSearchChanged(String q) {
    q = q.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filtered = List.from(_users));
      return;
    }
    setState(() {
      _filtered = _users.where((u) {
        final name = u.name.toLowerCase();
        final username = u.username?.toLowerCase() ?? '';
        return name.contains(q) || username.contains(q);
      }).toList();
    });
  }

  Future<void> _toggleFollow(CustomerModel user) async {
    if (!_currentAccount ||
        _ownerUid == null ||
        _pendingFollows.contains(user.uid)) {
      return;
    }
    final myId = _ownerUid!;
    setState(() => _pendingFollows.add(user.uid));
    final isFollowing = _followStatus[user.uid] ?? false;
    try {
      if (isFollowing) {
        await FirebaseFirestoreHelper().unfollowUser(
          followerId: myId,
          followingId: user.uid,
        );
      } else {
        await FirebaseFirestoreHelper().followUser(
          followerId: myId,
          followingId: user.uid,
        );
      }
      if (!_currentAccount) return;
      _followStatus[user.uid] = !isFollowing;
      if (mounted && _currentAccount) setState(() {});
    } catch (_) {
      if (mounted && _currentAccount) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update your follow. Please retry.'),
          ),
        );
      }
    } finally {
      if (_currentAccount) setState(() => _pendingFollows.remove(user.uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_accountChanged) {
      return Scaffold(
        appBar: AppBar(title: const Text('People')),
        body: const Center(
          child: Text('Your account changed. Reopen this screen to continue.'),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('People You May Know')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search by name or @username',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    itemCount: _filtered.length,
                    separatorBuilder: (_, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final user = _filtered[index];
                      final isFollowing = _followStatus[user.uid] ?? false;
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            user.name.isNotEmpty
                                ? user.name[0].toUpperCase()
                                : '?',
                          ),
                        ),
                        title: Text(user.name),
                        subtitle: user.username != null
                            ? Text('@${user.username}')
                            : null,
                        trailing: TextButton(
                          onPressed: _pendingFollows.contains(user.uid)
                              ? null
                              : () => _toggleFollow(user),
                          style: TextButton.styleFrom(
                            backgroundColor: isFollowing
                                ? Colors.grey.shade200
                                : AppThemeColor.darkBlueColor,
                            foregroundColor: isFollowing
                                ? Colors.black87
                                : Colors.white,
                          ),
                          child: Text(isFollowing ? 'Following' : 'Follow'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
