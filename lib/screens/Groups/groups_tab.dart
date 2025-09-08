import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:attendus/firebase/organization_helper.dart';
import 'package:attendus/screens/Groups/create_group_screen.dart';
import 'package:attendus/screens/Groups/group_profile_screen_v2.dart';

class GroupsTab extends StatefulWidget {
  const GroupsTab({super.key});

  @override
  State<GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<GroupsTab> {
  final OrganizationHelper _helper = OrganizationHelper();
  List<Map<String, String>> _orgs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _helper.getUserOrganizationsLite();
    if (mounted) {
      setState(() {
        _orgs = items;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        titleTextStyle: const TextStyle(
          color: Colors.black87,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        title: const Text('Groups'),
        actions: [
          IconButton(
            tooltip: 'Create Group',
            icon: const Icon(Icons.add_business),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
              );
              if (!mounted) return;
              _load();
            },
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _orgs.isEmpty
          ? const Center(child: Text('No groups yet'))
          : ListView.separated(
              itemCount: _orgs.length,
              separatorBuilder: (_, index) => const Divider(height: 0),
              itemBuilder: (context, index) {
                final org = _orgs[index];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.apartment)),
                  title: Text(org['name'] ?? ''),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            GroupProfileScreenV2(organizationId: org['id']!),
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: null,
    );
  }
}
