import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:attendus/models/organization_model.dart';
import 'package:attendus/screens/Groups/edit_group_details_screen.dart';
import 'package:attendus/screens/Groups/edit_event_settings_screen.dart';
import 'package:attendus/screens/Groups/join_requests_screen.dart';
import 'package:attendus/screens/Groups/manage_members_screen.dart';
import 'package:attendus/screens/Groups/manage_feed_posts_screen.dart';
import 'package:attendus/screens/Groups/group_analytics_dashboard_screen.dart';
import 'package:attendus/screens/Groups/group_location_settings_screen.dart';
import 'package:attendus/screens/Groups/pending_events_screen.dart';
import 'package:attendus/Utils/app_app_bar_view.dart';

class GroupAdminSettingsScreen extends StatefulWidget {
  final String organizationId;
  const GroupAdminSettingsScreen({super.key, required this.organizationId});

  @override
  State<GroupAdminSettingsScreen> createState() =>
      _GroupAdminSettingsScreenState();
}

class _GroupAdminSettingsScreenState extends State<GroupAdminSettingsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isLoading = true;
  bool _isAdmin = false;
  OrganizationModel? _organization;

  @override
  void initState() {
    super.initState();
    _checkAdminAndLoadData();
  }

  Future<void> _checkAdminAndLoadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Load organization data
      final orgDoc = await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .get();

      if (!orgDoc.exists) {
        setState(() => _isLoading = false);
        return;
      }

      final orgData = orgDoc.data()!;
      orgData['id'] = orgDoc.id;

      final createdBy = orgData['createdBy'];

      // Check if user is creator
      if (createdBy == user.uid) {
        setState(() {
          _isAdmin = true;
          _organization = OrganizationModel.fromJson(orgData);
          _isLoading = false;
        });
        return;
      }

      // Check if user is admin in Members collection
      final memberDoc = await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Members')
          .doc(user.uid)
          .get();

      if (memberDoc.exists) {
        final role = memberDoc.data()?['role'];
        setState(() {
          _isAdmin = role == 'admin' || role == 'owner';
          _organization = OrganizationModel.fromJson(orgData);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              AppAppBarView.modernHeader(
                context: context,
                title: 'Admin Settings',
                subtitle: 'Manage group settings and content',
              ),
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isAdmin || _organization == null) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              AppAppBarView.modernHeader(
                context: context,
                title: 'Admin Settings',
                subtitle: 'Manage group settings and content',
              ),
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'Access Denied',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'You need admin privileges to access this page.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppAppBarView.modernHeader(
              context: context,
              title: 'Admin Settings',
              subtitle: 'Manage group settings and content',
            ),
            Expanded(
              child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Group Information Section
          _buildSectionCard('Group Information', Icons.info_outline, [
            _buildSettingTile(
              'Edit Group Details',
              'Change name, description, category, images',
              Icons.edit,
              () => _editGroupDetails(),
            ),
            _buildSettingTile(
              'Location Settings',
              'Update group location',
              Icons.location_on,
              () => _editLocation(),
            ),
          ]),

          const SizedBox(height: 16),

          // Content Management Section
          _buildSectionCard('Content Management', Icons.manage_accounts, [
            _buildSettingTile(
              'Manage Feed Posts',
              'Delete or moderate announcements and polls',
              Icons.feed,
              () => _manageFeedPosts(),
            ),
            _buildSettingTile(
              'Event Settings',
              'Manage default event visibility',
              Icons.event,
              () => _editEventSettings(),
            ),
            _buildSettingTile(
              'Pending Events',
              'Review and approve member events',
              Icons.event_note,
              () => _managePendingEvents(),
            ),
          ]),

          const SizedBox(height: 16),

          // Member Management Section
          _buildSectionCard('Member Management', Icons.people, [
            _buildSettingTile(
              'Manage Members',
              'Promote admins, remove members',
              Icons.person_add,
              () => _manageMembers(),
            ),
            _buildSettingTile(
              'Join Requests',
              'Review pending membership requests',
              Icons.person_add_alt_1,
              () => _manageJoinRequests(),
            ),
          ]),

          const SizedBox(height: 16),

          // Advanced Settings Section
          _buildSectionCard('Advanced', Icons.settings, [
            _buildSettingTile(
              'Group Analytics',
              'View detailed analytics',
              Icons.analytics,
              () => _viewStatistics(),
            ),
          ]),

          const SizedBox(height: 32),

          // Danger Zone
          _buildDangerZone(),
        ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(String title, IconData icon, List<Widget> children) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF667EEA)),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSettingTile(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF667EEA).withValues(alpha: 0.1),
        child: Icon(icon, color: const Color(0xFF667EEA), size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600])),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Widget _buildDangerZone() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning, color: Colors.red.shade600),
                const SizedBox(width: 8),
                Text(
                  'Danger Zone',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: Colors.red.shade100,
                child: Icon(
                  Icons.delete_forever,
                  color: Colors.red.shade600,
                  size: 20,
                ),
              ),
              title: Text(
                'Delete Group',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Colors.red.shade700,
                ),
              ),
              subtitle: Text(
                'Permanently delete this group and all its data',
                style: TextStyle(color: Colors.red.shade600),
              ),
              trailing: Icon(Icons.chevron_right, color: Colors.red.shade600),
              onTap: () => _showDeleteGroupDialog(),
            ),
          ],
        ),
      ),
    );
  }

  void _editGroupDetails() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditGroupDetailsScreen(
          organizationId: widget.organizationId,
          organization: _organization!,
        ),
      ),
    ).then((_) => _checkAdminAndLoadData());
  }

  void _editLocation() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupLocationSettingsScreen(
          organizationId: widget.organizationId,
          organization: _organization!,
        ),
      ),
    ).then((result) {
      // Refresh organization data if location was updated
      if (result == true) {
        _checkAdminAndLoadData();
      }
    });
  }

  void _manageFeedPosts() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ManageFeedPostsScreen(organizationId: widget.organizationId),
      ),
    );
  }

  void _editEventSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditEventSettingsScreen(
          organizationId: widget.organizationId,
          organization: _organization!,
        ),
      ),
    ).then((_) => _checkAdminAndLoadData());
  }

  void _manageMembers() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ManageMembersScreen(organizationId: widget.organizationId),
      ),
    );
  }

  void _manageJoinRequests() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            JoinRequestsScreen(organizationId: widget.organizationId),
      ),
    );
  }

  void _managePendingEvents() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PendingEventsScreen(organizationId: widget.organizationId),
      ),
    );
  }

  void _viewStatistics() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupAnalyticsDashboardScreen(
          organizationId: widget.organizationId,
        ),
      ),
    );
  }

  void _showDeleteGroupDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Group'),
        content: const Text(
          'Are you sure you want to delete this group? This action cannot be undone and will permanently remove all group data, including members, events, and posts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteGroup();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteGroup() async {
    // Implementation for group deletion would go here
    // This is a complex operation that should be handled carefully
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Group deletion functionality needs to be implemented with proper safeguards',
        ),
      ),
    );
  }
}

// Import the actual implementation
// The EditGroupDetailsScreen is implemented in edit_group_details_screen.dart

// Removed placeholder ManageFeedPostsScreen in favor of the full
// implementation in manage_feed_posts_screen.dart

// Removed placeholder ManageMembersScreen. The real implementation is
// in manage_members_screen.dart (imported above).

// Removed placeholder ManageJoinRequestsScreen. The real implementation is
// in join_requests_screen.dart (imported above).
