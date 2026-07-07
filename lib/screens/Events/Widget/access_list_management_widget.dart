import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:share_plus/share_plus.dart';
import 'package:attendus/Utils/app_constants.dart';

class AccessListManagementWidget extends StatefulWidget {
  final EventModel eventModel;
  const AccessListManagementWidget({super.key, required this.eventModel});

  @override
  State<AccessListManagementWidget> createState() =>
      _AccessListManagementWidgetState();
}

class _AccessListManagementWidgetState
    extends State<AccessListManagementWidget> {
  final TextEditingController _searchController = TextEditingController();
  List<CustomerModel> _results = [];
  bool _isSearching = false;
  List<String> _accessList = [];
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _accessList = List<String>.from(widget.eventModel.accessList);
  }

  Future<void> _search() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _isSearching = true);
    try {
      final users = await FirebaseFirestoreHelper().searchUsers(
        searchQuery: q,
        limit: 20,
      );
      setState(() => _results = users);
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _addToAccess(String userId) async {
    setState(() => _updating = true);
    try {
      await FirebaseFirestore.instance
          .collection(EventModel.firebaseKey)
          .doc(widget.eventModel.id)
          .update({
            'accessList': FieldValue.arrayUnion([userId]),
          });
      setState(() => _accessList.add(userId));
      ShowToast().showNormalToast(msg: 'User added to access list');
    } catch (e) {
      ShowToast().showNormalToast(msg: 'Failed to add user: $e');
    } finally {
      setState(() => _updating = false);
    }
  }

  Future<void> _removeFromAccess(String userId) async {
    setState(() => _updating = true);
    try {
      await FirebaseFirestore.instance
          .collection(EventModel.firebaseKey)
          .doc(widget.eventModel.id)
          .update({
            'accessList': FieldValue.arrayRemove([userId]),
          });
      setState(() => _accessList.remove(userId));
      ShowToast().showNormalToast(msg: 'User removed from access list');
    } catch (e) {
      ShowToast().showNormalToast(msg: 'Failed to remove user: $e');
    } finally {
      setState(() => _updating = false);
    }
  }

  void _shareInviteLink() async {
    // Build a long dynamic link (no SDK) as fallback; Firebase will handle routing if configured
    final deepLink = AppConstants.buildInviteUri(
      widget.eventModel.id,
    ).toString();
    final dynamicLink = Uri.parse(AppConstants.dynamicLinksDomain)
        .replace(
          queryParameters: {
            'link': deepLink,
            'apn': AppConstants.androidPackageName,
            'ibi': AppConstants.iosBundleId,
            // Optional social tags (non-shortened):
            'st': widget.eventModel.title,
            'sd': widget.eventModel.description,
          },
        )
        .toString();

    // Prefer the dynamic link domain if configured; otherwise use the direct invite link
    final toShare = (AppConstants.dynamicLinksDomain.isNotEmpty)
        ? dynamicLink
        : deepLink;
    await Share.share('Join my private event: $toShare');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Manage Access',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed: _shareInviteLink,
                  icon: const Icon(CupertinoIcons.share),
                  tooltip: 'Share Invite Link',
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search users by name or username',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _isSearching ? null : _search,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),
            if (_isSearching) const LinearProgressIndicator(),
            if (_results.isNotEmpty)
              SizedBox(
                height: 220,
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, i) {
                    final u = _results[i];
                    final inAccess = _accessList.contains(u.uid);
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(u.name),
                      subtitle: Text(u.username ?? u.uid),
                      trailing: _updating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : ElevatedButton.icon(
                              onPressed: inAccess
                                  ? () => _removeFromAccess(u.uid)
                                  : () => _addToAccess(u.uid),
                              icon: Icon(inAccess ? Icons.remove : Icons.add),
                              label: Text(inAccess ? 'Remove' : 'Add'),
                            ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'Current Access',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection(EventModel.firebaseKey)
                    .doc(widget.eventModel.id)
                    .snapshots(),
                builder: (context, snapshot) {
                  final list = _accessList;
                  if (snapshot.hasData && snapshot.data!.exists) {
                    final data = snapshot.data!.data() as Map<String, dynamic>;
                    final List<dynamic>? arr =
                        data['accessList'] as List<dynamic>?;
                    if (arr != null) {
                      // Sync local cache to backend
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _accessList = arr.map((e) => e.toString()).toList();
                          });
                        }
                      });
                    }
                  }
                  if (list.isEmpty) {
                    return const Center(child: Text('No one has access yet'));
                  }
                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final uid = list[i];
                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.lock_open),
                        ),
                        title: Text(uid),
                        trailing: _updating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: () => _removeFromAccess(uid),
                              ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
