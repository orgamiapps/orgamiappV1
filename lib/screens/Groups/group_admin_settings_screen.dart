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
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Quick Actions Grid (Most Used)
                    _buildSectionHeader(
                      title: 'Quick Actions',
                      icon: Icons.flash_on,
                      color: const Color(0xFF667EEA),
                    ),
                    const SizedBox(height: 12),
                    _buildCompactActionsGrid([
                      _CompactAction(
                        icon: Icons.edit,
                        title: 'Edit Group',
                        subtitle: 'Details & Info',
                        color: const Color(0xFF667EEA),
                        onTap: () => _editGroupDetails(),
                      ),
                      _CompactAction(
                        icon: Icons.people,
                        title: 'Members',
                        subtitle: 'Manage Access',
                        color: const Color(0xFF10B981),
                        onTap: () => _manageMembers(),
                      ),
                      _CompactAction(
                        icon: Icons.feed,
                        title: 'Feed Posts',
                        subtitle: 'Moderate Content',
                        color: const Color(0xFFEC4899),
                        onTap: () => _manageFeedPosts(),
                      ),
                      _CompactAction(
                        icon: Icons.person_add_alt_1,
                        title: 'Join Requests',
                        subtitle: 'Review Pending',
                        color: const Color(0xFFFF9800),
                        onTap: () => _manageJoinRequests(),
                      ),
                    ]),
                    
                    const SizedBox(height: 24),
                    
                    // Content & Events Management
                    _buildSectionHeader(
                      title: 'Content & Events',
                      icon: Icons.campaign,
                      color: const Color(0xFF8B5CF6),
                    ),
                    const SizedBox(height: 12),
                    _buildCompactActionsGrid([
                      _CompactAction(
                        icon: Icons.event,
                        title: 'Event Settings',
                        subtitle: 'Default Visibility',
                        color: const Color(0xFF3B82F6),
                        onTap: () => _editEventSettings(),
                      ),
                      _CompactAction(
                        icon: Icons.event_note,
                        title: 'Pending Events',
                        subtitle: 'Approve Events',
                        color: const Color(0xFF06B6D4),
                        onTap: () => _managePendingEvents(),
                      ),
                      _CompactAction(
                        icon: Icons.location_on,
                        title: 'Location',
                        subtitle: 'Update Place',
                        color: const Color(0xFFEF4444),
                        onTap: () => _editLocation(),
                      ),
                    ]),

                    const SizedBox(height: 24),

                    // Analytics & Insights
                    _buildSectionHeader(
                      title: 'Insights & Growth',
                      icon: Icons.trending_up,
                      color: const Color(0xFF10B981),
                    ),
                    const SizedBox(height: 12),
                    _buildCompactActionsGrid([
                      _CompactAction(
                        icon: Icons.analytics,
                        title: 'Analytics',
                        subtitle: 'View Insights',
                        color: const Color(0xFF059669),
                        onTap: () => _viewStatistics(),
                      ),
                    ]),

                    const SizedBox(height: 24),

                    // Danger Zone
                    _buildSectionHeader(
                      title: 'Danger Zone',
                      icon: Icons.warning,
                      color: const Color(0xFFEF4444),
                    ),
                    const SizedBox(height: 12),
                    _buildDangerZoneCompact(),

                    const SizedBox(height: 32), // Extra space at bottom
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w700,
            fontSize: 18,
            fontFamily: 'Roboto',
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactActionsGrid(List<_CompactAction> actions) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.15,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: actions.length,
      itemBuilder: (context, index) {
        final action = actions[index];
        return _buildCompactActionCard(action);
      },
    );
  }

  Widget _buildCompactActionCard(_CompactAction action) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: action.isDisabled ?? false 
              ? const Color(0xFFE5E7EB) 
              : action.color.withValues(alpha: 0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            spreadRadius: 0,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: action.isDisabled ?? false ? null : action.onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon with background
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: action.isDisabled ?? false
                        ? const Color(0xFFF3F4F6)
                        : action.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        action.icon,
                        color: action.isDisabled ?? false
                            ? const Color(0xFF9CA3AF)
                            : action.color,
                        size: 24,
                      ),
                      // Premium badge overlay (if needed)
                      if (action.isPremium ?? false)
                        Positioned(
                          top: 2,
                          right: 2,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD700),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white, width: 1),
                            ),
                            child: const Icon(
                              Icons.star,
                              color: Colors.white,
                              size: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Title
                Text(
                  action.title,
                  style: TextStyle(
                    color: action.isDisabled ?? false
                        ? const Color(0xFF9CA3AF)
                        : const Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    fontFamily: 'Roboto',
                    letterSpacing: -0.1,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                // Subtitle
                Text(
                  action.subtitle,
                  style: TextStyle(
                    color: action.isDisabled ?? false
                        ? const Color(0xFFD1D5DB)
                        : const Color(0xFF6B7280),
                    fontSize: 12,
                    fontFamily: 'Roboto',
                    letterSpacing: 0.1,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDangerZoneCompact() {
    return _buildCompactActionsGrid([
      _CompactAction(
        icon: Icons.delete_forever,
        title: 'Delete Group',
        subtitle: 'Permanent Removal',
        color: const Color(0xFFDC2626),
        onTap: () => _showDeleteGroupDialog(),
      ),
    ]);
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

/// Compact action class for the grid-based group admin interface
class _CompactAction {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;
  final bool? isPremium;
  final bool? isDisabled;

  const _CompactAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
    this.isPremium = false,
    this.isDisabled = false,
  });
}
