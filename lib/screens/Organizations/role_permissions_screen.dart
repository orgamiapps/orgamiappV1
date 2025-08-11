import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:orgami/firebase/organization_helper.dart';

class RolePermissionsScreen extends StatelessWidget {
  final String organizationId;
  const RolePermissionsScreen({super.key, required this.organizationId});

  @override
  Widget build(BuildContext context) {
    final members = FirebaseFirestore.instance
        .collection('Organizations')
        .doc(organizationId)
        .collection('Members')
        .orderBy('joinedAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Roles & Permissions')),
      body: StreamBuilder<QuerySnapshot>(
        stream: members,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No members'));
          }
          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, i) {
              final doc = snapshot.data!.docs[i];
              final data = doc.data() as Map<String, dynamic>;
              final userId = (data['userId'] ?? '').toString();
              final role = (data['role'] ?? 'Member').toString();
              final List<dynamic> perms = (data['permissions'] as List<dynamic>?) ?? [];
              return _MemberTile(
                organizationId: organizationId,
                userId: userId,
                role: role,
                permissions: perms.map((e) => e.toString()).toList(),
              );
            },
          );
        },
      ),
    );
  }
}

class _MemberTile extends StatefulWidget {
  final String organizationId;
  final String userId;
  final String role;
  final List<String> permissions;
  const _MemberTile({required this.organizationId, required this.userId, required this.role, required this.permissions});

  @override
  State<_MemberTile> createState() => _MemberTileState();
}

class _MemberTileState extends State<_MemberTile> {
  late String _role = widget.role;
  late final OrganizationHelper _helper = OrganizationHelper();
  final Map<String, bool> _permMap = {
    'CreateEditEvents': false,
    'ApproveJoinRequests': false,
    'ManageMembersRoles': false,
    'ViewAnalytics': false,
  };
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final k in _permMap.keys) {
      _permMap[k] = widget.permissions.contains(k);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final selected = _permMap.entries.where((e) => e.value).map((e) => e.key).toList();
    await _helper.updateMemberPermissions(widget.organizationId, widget.userId, permissions: selected, role: _role);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.person)),
                const SizedBox(width: 12),
                Expanded(child: Text(widget.userId)),
                DropdownButton<String>(
                  value: _role,
                  items: const [
                    DropdownMenuItem(value: 'Admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'Member', child: Text('Member')),
                  ],
                  onChanged: (v) => setState(() => _role = v ?? 'Member'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _permMap.keys.map((p) {
                return FilterChip(
                  label: Text(p),
                  selected: _permMap[p]!,
                  onSelected: (sel) => setState(() => _permMap[p] = sel),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
