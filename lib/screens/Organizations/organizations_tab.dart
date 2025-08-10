import 'package:flutter/material.dart';
import 'package:orgami/firebase/organization_helper.dart';
import 'package:orgami/screens/Organizations/create_organization_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class OrganizationsTab extends StatefulWidget {
  const OrganizationsTab({super.key});

  @override
  State<OrganizationsTab> createState() => _OrganizationsTabState();
}

class _OrganizationsTabState extends State<OrganizationsTab> {
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
    if (mounted) setState(() {
      _orgs = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Organizations')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _orgs.isEmpty
              ? const Center(child: Text('No organizations yet'))
              : ListView.separated(
                  itemCount: _orgs.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (context, index) {
                    final org = _orgs[index];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.apartment)),
                      title: Text(org['name'] ?? ''),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrganizationProfileScreen(organizationId: org['id']!),
                          ),
                        );
                      },
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateOrganizationScreen()),
          );
          _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('Create Organization'),
      ),
    );
  }
}

class OrganizationProfileScreen extends StatelessWidget {
  final String organizationId;
  const OrganizationProfileScreen({super.key, required this.organizationId});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        body: Column(
          children: [
            _OrgHeader(orgId: organizationId),
            const TabBar(
              tabs: [
                Tab(text: 'Events'),
                Tab(text: 'Members'),
                Tab(text: 'About'),
                Tab(text: 'Settings'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _OrgEventsTab(orgId: organizationId),
                  _OrgMembersTab(orgId: organizationId),
                  _OrgAboutTab(orgId: organizationId),
                  _OrgSettingsTab(orgId: organizationId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrgHeader extends StatelessWidget {
  final String orgId;
  const _OrgHeader({required this.orgId});

  @override
  Widget build(BuildContext context) {
    final doc = FirebaseFirestore.instance.collection('Organizations').doc(orgId);
    return FutureBuilder<DocumentSnapshot>(
      future: doc.get(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final bannerUrl = data?['bannerUrl']?.toString();
        final logoUrl = data?['logoUrl']?.toString();
        final name = data?['name']?.toString() ?? 'Organization';
        return Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            image: bannerUrl != null
                ? DecorationImage(
                    image: NetworkImage(bannerUrl),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                      Colors.black.withOpacity(0.2),
                      BlendMode.darken,
                    ),
                  )
                : null,
          ),
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white,
                backgroundImage: logoUrl != null ? NetworkImage(logoUrl) : null,
                child: logoUrl == null ? const Icon(Icons.apartment, color: Color(0xFF667EEA)) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              FilledButton(
                onPressed: () {
                  OrganizationHelper().requestToJoinOrganization(orgId);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Join request sent')),
                  );
                },
                child: const Text('Join'),
              )
            ],
          ),
        );
      },
    );
  }
}

class _OrgEventsTab extends StatelessWidget {
  final String orgId;
  const _OrgEventsTab({required this.orgId});

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('Events')
        .where('organizationId', isEqualTo: orgId)
        .orderBy('selectedDateTime');

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No events yet'));
        }
        final docs = snapshot.data!.docs;
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 0),
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            return ListTile(
              leading: const Icon(Icons.event),
              title: Text((data['title'] ?? '').toString()),
              subtitle: Text((data['description'] ?? '').toString()),
            );
          },
        );
      },
    );
  }
}

class _OrgMembersTab extends StatelessWidget {
  final String orgId;
  const _OrgMembersTab({required this.orgId});

  @override
  Widget build(BuildContext context) {
    final membersQuery = FirebaseFirestore.instance
        .collection('Organizations')
        .doc(orgId)
        .collection('Members')
        .orderBy('joinedAt', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: membersQuery.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No members yet'));
        }
        final docs = snapshot.data!.docs;
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 0),
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text((data['userId'] ?? '').toString()),
              subtitle: Text((data['role'] ?? 'Member').toString()),
            );
          },
        );
      },
    );
  }
}

class _OrgAboutTab extends StatelessWidget {
  final String orgId;
  const _OrgAboutTab({required this.orgId});

  @override
  Widget build(BuildContext context) {
    final orgDoc = FirebaseFirestore.instance.collection('Organizations').doc(orgId);
    return FutureBuilder<DocumentSnapshot>(
      future: orgDoc.get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: Text('Organization not found'));
        }
        final data = snapshot.data!.data() as Map<String, dynamic>;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(data['name'] ?? '', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(data['description'] ?? ''),
              const SizedBox(height: 16),
              Text('Category: ${data['category'] ?? 'Other'}'),
            ],
          ),
        );
      },
    );
  }
}

import 'package:orgami/screens/Organizations/join_requests_screen.dart';
import 'package:orgami/screens/Organizations/role_permissions_screen.dart';

class _OrgSettingsTab extends StatelessWidget {
  final String orgId;
  const _OrgSettingsTab({required this.orgId});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Admin Tools', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.group_add),
            title: const Text('Join Requests'),
            subtitle: const Text('Approve or decline organization join requests'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => JoinRequestsScreen(organizationId: orgId)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.admin_panel_settings),
            title: const Text('Roles & Permissions'),
            subtitle: const Text('Manage member roles and permissions'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => RolePermissionsScreen(organizationId: orgId)),
            ),
          ),
        ],
      ),
    );
  }
}