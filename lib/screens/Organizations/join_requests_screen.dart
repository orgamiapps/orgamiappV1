import 'package:flutter/material.dart';
import 'package:orgami/firebase/organization_helper.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _helper.getJoinRequests(widget.organizationId);
    if (mounted) setState(() {
      _requests = items;
      _loading = false;
    });
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
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (context, i) {
                    final r = _requests[i];
                    final userId = (r['userId'] ?? '').toString();
                    final status = (r['status'] ?? 'pending').toString();
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(userId),
                      subtitle: Text('Status: $status'),
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
