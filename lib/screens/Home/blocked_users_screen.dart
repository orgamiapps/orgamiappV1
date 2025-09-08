import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/widgets/app_scaffold_wrapper.dart';

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
        final userDoc = await _firestore.collection('Customers').doc(targetId).get();
        final data = userDoc.data() ?? {};
        items.add(_BlockedUser(
          uid: targetId,
          name: (data['name'] ?? 'User') as String,
          profilePictureUrl: data['profilePictureUrl'] as String?,
        ));
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
    await FirebaseFirestoreHelper().unblockUser(blockerId: uid, blockedUserId: blockedUserId);
    if (mounted) {
      setState(() {
        _blocked.removeWhere((e) => e.uid == blockedUserId);
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User unblocked')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffoldWrapper(
      selectedBottomNavIndex: 5, // Account tab
      appBar: AppBar(title: const Text('Blocked Users')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _blocked.isEmpty
              ? const Center(child: Text('No blocked users'))
              : ListView.separated(
                  itemBuilder: (context, i) {
                    final u = _blocked[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage:
                            (u.profilePictureUrl != null && u.profilePictureUrl!.isNotEmpty)
                                ? NetworkImage(u.profilePictureUrl!)
                                : null,
                        child: (u.profilePictureUrl == null || u.profilePictureUrl!.isEmpty)
                            ? Text(u.name.isNotEmpty ? u.name[0].toUpperCase() : '?')
                            : null,
                      ),
                      title: Text(u.name),
                      trailing: TextButton(
                        onPressed: () => _unblock(u.uid),
                        child: const Text('Unblock'),
                      ),
                    );
                  },
                  separatorBuilder: (_, index) => const Divider(height: 0),
                  itemCount: _blocked.length,
                ),
    );
  }
}

class _BlockedUser {
  final String uid;
  final String name;
  final String? profilePictureUrl;
  _BlockedUser({required this.uid, required this.name, this.profilePictureUrl});
}
