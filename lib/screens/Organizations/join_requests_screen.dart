import 'package:flutter/material.dart';
import 'package:attendus/firebase/organization_helper.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/screens/MyProfile/user_profile_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _helper.getJoinRequests(widget.organizationId);
    // Fetch user profiles for requester IDs
    final List<String> userIds = items
        .map((r) => (r['userId'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    Map<String, CustomerModel> userMap = {};
    if (userIds.isNotEmpty) {
      final users = await FirebaseFirestoreHelper().getUsersByIds(userIds: userIds);
      for (final u in users) {
        userMap[u.uid] = u;
      }
    }

    if (mounted) {
      setState(() {
        _requests = items;
        _userById = userMap;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join Requests')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? const Center(child: Text('No pending requests'))
              : ListView.separated(
                  itemCount: _requests.length,
                  separatorBuilder: (_, index) => const Divider(height: 0),
                  itemBuilder: (context, i) {
                    final r = _requests[i];
                    final userId = (r['userId'] ?? '').toString();
                    final status = (r['status'] ?? 'pending').toString();
                    final user = _userById[userId];
                    final title = user?.name ?? userId;
                    final subtitle = user?.username != null && user!.username!.isNotEmpty
                        ? 'Status: $status  ·  @${user.username}'
                        : 'Status: $status';

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: user?.profilePictureUrl != null
                            ? NetworkImage(user!.profilePictureUrl!)
                            : null,
                        child: user?.profilePictureUrl == null
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text(title),
                      subtitle: Text(subtitle),
                      onTap: user != null
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => UserProfileScreen(
                                    user: user,
                                    isOwnProfile: false,
                                  ),
                                ),
                              );
                            }
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check, color: Colors.green),
                            onPressed: () async {
                              await _helper.approveJoinRequest(widget.organizationId, userId);
                              _load();
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () async {
                              await _helper.declineJoinRequest(widget.organizationId, userId);
                              _load();
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
