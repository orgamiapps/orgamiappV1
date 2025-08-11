import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:orgami/firebase/organization_helper.dart';
import 'package:orgami/firebase/firebase_storage_helper.dart';
import 'package:orgami/screens/Organizations/join_requests_screen.dart';
import 'package:orgami/screens/Organizations/role_permissions_screen.dart';

class OrganizationProfileScreen extends StatelessWidget {
  final String organizationId;
  const OrganizationProfileScreen({super.key, required this.organizationId});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          title: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('Organizations')
                .doc(organizationId)
                .snapshots(),
            builder: (context, snapshot) {
              final data = snapshot.data?.data() as Map<String, dynamic>?;
              final name = data?['name']?.toString();
              return Text(
                (name != null && name.isNotEmpty) ? name : 'Organization',
              );
            },
          ),
        ),
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
    final doc = FirebaseFirestore.instance
        .collection('Organizations')
        .doc(orgId);
    return FutureBuilder<DocumentSnapshot>(
      future: doc.get(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final bannerUrl = data?['bannerUrl']?.toString();
        final logoUrl = data?['logoUrl']?.toString();
        final name = data?['name']?.toString() ?? 'Organization';
        final category = data?['category']?.toString() ?? 'Other';
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
                child: logoUrl == null
                    ? const Icon(Icons.apartment, color: Color(0xFF667EEA))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      category,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              _JoinAction(orgId: orgId),
            ],
          ),
        );
      },
    );
  }
}

class _JoinAction extends StatefulWidget {
  final String orgId;
  const _JoinAction({required this.orgId});

  @override
  State<_JoinAction> createState() => _JoinActionState();
}

class _JoinActionState extends State<_JoinAction> {
  bool _isMember = false;
  bool _hasPending = false;
  bool _loading = true;
  String _role = 'Member';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _isMember = false;
          _hasPending = false;
          _loading = false;
        });
        return;
      }

      final memberSnap = await firestore
          .collection('Organizations')
          .doc(widget.orgId)
          .collection('Members')
          .doc(user.uid)
          .get();

      final memberData = memberSnap.data();
      final isApproved =
          memberSnap.exists &&
          ((memberData?['status'] ?? 'approved') == 'approved');
      final role = (memberData?['role'] ?? 'Member').toString();

      final joinSnap = await firestore
          .collection('Organizations')
          .doc(widget.orgId)
          .collection('JoinRequests')
          .doc(user.uid)
          .get();

      setState(() {
        _isMember = isApproved;
        _role = role.isEmpty ? 'Member' : role;
        _hasPending =
            !isApproved &&
            joinSnap.exists &&
            ((joinSnap.data()?['status'] ?? 'pending') == 'pending');
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 36,
        width: 36,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    }
    if (_isMember) {
      return Chip(label: Text(_role));
    }
    if (_hasPending) {
      return const Chip(label: Text('Requested'));
    }
    return FilledButton(
      onPressed: () async {
        await OrganizationHelper().requestToJoinOrganization(widget.orgId);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Join request sent')));
        await _load();
      },
      child: const Text('Join'),
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
            final String userId = (data['userId'] ?? '').toString();
            final String role = (data['role'] ?? 'Member').toString();

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('Customers')
                  .doc(userId)
                  .get(),
              builder: (context, userSnap) {
                final userData = userSnap.data?.data() as Map<String, dynamic>?;
                final String displayName = (userData?['name'] ?? userId)
                    .toString();
                final String username = (userData?['username'] ?? '')
                    .toString();
                final String photoUrl = (userData?['profilePictureUrl'] ?? '')
                    .toString();
                final bool hasPhoto = photoUrl.isNotEmpty;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
                    child: hasPhoto ? null : const Icon(Icons.person),
                  ),
                  title: Text(displayName),
                  subtitle: username.isNotEmpty
                      ? Text('@$username')
                      : Text(role),
                  trailing: username.isNotEmpty ? Text(role) : null,
                );
              },
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
    final orgDoc = FirebaseFirestore.instance
        .collection('Organizations')
        .doc(orgId);
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
              Text(
                data['name'] ?? '',
                style: Theme.of(context).textTheme.titleLarge,
              ),
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
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('Sign in to manage'));
    }
    final memberDoc = FirebaseFirestore.instance
        .collection('Organizations')
        .doc(orgId)
        .collection('Members')
        .doc(uid)
        .snapshots();

    return StreamBuilder<DocumentSnapshot>(
      stream: memberDoc,
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final role = (data?['role'] ?? '').toString();
        final List<dynamic> perms =
            (data?['permissions'] as List<dynamic>?) ?? const [];
        final bool canManage =
            role == 'Admin' ||
            perms.contains('ManageMembersRoles') ||
            perms.contains('ApproveJoinRequests');

        if (!canManage) {
          return const Center(
            child: Text('You do not have admin access for this organization'),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Admin Tools',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit Organization'),
                subtitle: const Text('Update name, description, and category'),
                onTap: () => _showEditOrganizationSheet(context, orgId),
              ),
              ListTile(
                leading: const Icon(Icons.image),
                title: const Text('Update Logo'),
                subtitle: const Text('Upload or change organization logo'),
                onTap: () =>
                    _pickAndUploadImage(context, orgId, isBanner: false),
              ),
              ListTile(
                leading: const Icon(Icons.wallpaper),
                title: const Text('Update Banner'),
                subtitle: const Text('Upload or change header banner'),
                onTap: () =>
                    _pickAndUploadImage(context, orgId, isBanner: true),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.group_add),
                title: const Text('Join Requests'),
                subtitle: const Text(
                  'Approve or decline organization join requests',
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => JoinRequestsScreen(organizationId: orgId),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.admin_panel_settings),
                title: const Text('Roles & Permissions'),
                subtitle: const Text('Manage member roles and permissions'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        RolePermissionsScreen(organizationId: orgId),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditOrganizationSheet(BuildContext context, String orgId) {
    final nameCtlr = TextEditingController();
    final descCtlr = TextEditingController();
    final categoryCtlr = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: MediaQuery.of(ctx).viewInsets + const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Edit Organization',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtlr,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtlr,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: categoryCtlr,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final updates = <String, dynamic>{};
                    if (nameCtlr.text.trim().isNotEmpty) {
                      updates['name'] = nameCtlr.text.trim();
                      updates['name_lowercase'] = nameCtlr.text
                          .trim()
                          .toLowerCase();
                    }
                    if (descCtlr.text.trim().isNotEmpty) {
                      updates['description'] = descCtlr.text.trim();
                    }
                    if (categoryCtlr.text.trim().isNotEmpty) {
                      updates['category'] = categoryCtlr.text.trim();
                      updates['category_lowercase'] = categoryCtlr.text
                          .trim()
                          .toLowerCase();
                    }
                    if (updates.isNotEmpty) {
                      await FirebaseFirestore.instance
                          .collection('Organizations')
                          .doc(orgId)
                          .set(updates, SetOptions(merge: true));
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadImage(
    BuildContext context,
    String orgId, {
    required bool isBanner,
  }) async {
    try {
      final picked = await FirebaseStorageHelper.pickImageFromGallery();
      if (picked == null) return;
      final url = await FirebaseStorageHelper.uploadOrganizationImage(
        organizationId: orgId,
        imageFile: picked,
        isBanner: isBanner,
      );
      if (url == null) return;
      await FirebaseFirestore.instance
          .collection('Organizations')
          .doc(orgId)
          .set({
            isBanner ? 'bannerUrl' : 'logoUrl': url,
          }, SetOptions(merge: true));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${isBanner ? 'Banner' : 'Logo'} updated')),
        );
      }
    } catch (_) {}
  }
}
