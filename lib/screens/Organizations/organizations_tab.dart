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
        appBar: AppBar(
          title: const Text('Organization'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Events'),
              Tab(text: 'Members'),
              Tab(text: 'About'),
              Tab(text: 'Settings'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OrgEventsTab(orgId: organizationId),
            _OrgMembersTab(orgId: organizationId),
            _OrgAboutTab(orgId: organizationId),
            _OrgSettingsTab(orgId: organizationId),
          ],
        ),
      ),
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

class _OrgSettingsTab extends StatelessWidget {
  final String orgId;
  const _OrgSettingsTab({required this.orgId});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('Settings for $orgId (Admins only)'),
    );
  }
}