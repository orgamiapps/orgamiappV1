import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:attendus/models/organization_model.dart';
import 'package:attendus/Utils/cached_image.dart';
import 'package:attendus/screens/Groups/group_profile_screen_v2.dart';
import 'package:attendus/screens/Groups/group_admin_settings_screen.dart';
import 'package:attendus/screens/Groups/manage_members_screen.dart';
import 'package:attendus/screens/Groups/create_announcement_screen.dart';
import 'package:attendus/screens/Groups/create_poll_screen.dart';
import 'package:attendus/screens/Groups/create_photo_post_screen.dart';
import 'package:attendus/screens/Events/premium_event_creation_wrapper.dart';
import 'package:attendus/screens/Groups/group_analytics_dashboard_screen.dart';
import 'package:attendus/Utils/router.dart';

class ManageGroupsScreen extends StatefulWidget {
  const ManageGroupsScreen({super.key});

  @override
  State<ManageGroupsScreen> createState() => _ManageGroupsScreenState();
}

class _ManageGroupsScreenState extends State<ManageGroupsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<_ManagedGroup> _groups = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadManagedGroups();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadManagedGroups() async {
    setState(() => _isLoading = true);

    final user = _auth.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final List<_ManagedGroup> groups = [];

      // Get all organizations
      final orgsSnapshot = await _db.collection('Organizations').get();

      for (final orgDoc in orgsSnapshot.docs) {
        final orgData = orgDoc.data();
        final createdBy = orgData['createdBy'];
        bool isAdmin = false;
        String role = '';

        // Check if user is creator
        if (createdBy == user.uid) {
          isAdmin = true;
          role = 'Creator';
        } else {
          // Check if user is admin
          final memberDoc = await _db
              .collection('Organizations')
              .doc(orgDoc.id)
              .collection('Members')
              .doc(user.uid)
              .get();

          if (memberDoc.exists) {
            final memberRole = memberDoc
                .data()?['role']
                ?.toString()
                .toLowerCase();
            if (memberRole == 'admin' || memberRole == 'owner') {
              isAdmin = true;
              role = memberRole == 'owner' ? 'Owner' : 'Admin';
            }
          }
        }

        if (isAdmin) {
          // Get stats
          final stats = await _getGroupStats(orgDoc.id);

          orgData['id'] = orgDoc.id;
          final org = OrganizationModel.fromJson(orgData);

          groups.add(
            _ManagedGroup(
              organization: org,
              role: role,
              memberCount: stats['memberCount'] ?? 0,
              eventCount: stats['eventCount'] ?? 0,
              activeEventCount: stats['activeEventCount'] ?? 0,
              pendingRequestCount: stats['pendingRequestCount'] ?? 0,
            ),
          );
        }
      }

      // Sort by name
      groups.sort((a, b) => a.organization.name.compareTo(b.organization.name));

      setState(() {
        _groups = groups;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading managed groups: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<Map<String, int>> _getGroupStats(String organizationId) async {
    try {
      final futures = await Future.wait([
        _db
            .collection('Organizations')
            .doc(organizationId)
            .collection('Members')
            .where('status', isEqualTo: 'approved')
            .count()
            .get(),
        _db
            .collection('Events')
            .where('organizationId', isEqualTo: organizationId)
            .count()
            .get(),
        _db
            .collection('Organizations')
            .doc(organizationId)
            .collection('JoinRequests')
            .where('status', isEqualTo: 'pending')
            .count()
            .get(),
        _db
            .collection('Events')
            .where('organizationId', isEqualTo: organizationId)
            .get(),
      ]);

      final memberCount = (futures[0] as AggregateQuerySnapshot).count ?? 0;
      final eventCount = (futures[1] as AggregateQuerySnapshot).count ?? 0;
      final pendingRequestCount =
          (futures[2] as AggregateQuerySnapshot).count ?? 0;

      // Count active events
      final eventsSnapshot = futures[3] as QuerySnapshot;
      final now = DateTime.now();
      final activeEventCount = eventsSnapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final endDateTime = (data['endDateTime'] as Timestamp?)?.toDate();
        return endDateTime?.isAfter(now) ?? false;
      }).length;

      return {
        'memberCount': memberCount,
        'eventCount': eventCount,
        'activeEventCount': activeEventCount,
        'pendingRequestCount': pendingRequestCount,
      };
    } catch (e) {
      debugPrint('Error getting group stats: $e');
      return {
        'memberCount': 0,
        'eventCount': 0,
        'activeEventCount': 0,
        'pendingRequestCount': 0,
      };
    }
  }

  List<_ManagedGroup> get _filteredGroups {
    if (_searchQuery.isEmpty) return _groups;

    return _groups.where((group) {
      return group.organization.name.toLowerCase().contains(
        _searchQuery.toLowerCase(),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Manage Groups'),
        titleTextStyle: const TextStyle(
          color: Colors.black87,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE5E7EB)),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _loadManagedGroups,
              child: Column(
                children: [
                  // Search bar
                  if (_groups.length > 3) _buildSearchBar(),

                  // Groups list
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredGroups.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        return _buildGroupCard(_filteredGroups[index]);
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search groups...',
          prefixIcon: const Icon(Icons.search, color: Color(0xFF6B7280)),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Color(0xFF6B7280)),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: const Color(0xFFF3F4F6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        onChanged: (value) {
          setState(() => _searchQuery = value);
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(60),
              ),
              child: const Icon(
                Icons.groups_outlined,
                size: 60,
                color: Color(0xFF9CA3AF),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Groups to Manage',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You are not a creator or admin of any groups yet. Create a group to get started!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Color(0xFF6B7280),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(_ManagedGroup group) {
    final org = group.organization;
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openGroupProfile(org.id),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with logo and title
                Row(
                  children: [
                    // Logo
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: org.logoUrl != null && org.logoUrl!.isNotEmpty
                          ? SafeNetworkImage(
                              imageUrl: org.logoUrl!,
                              fit: BoxFit.cover,
                            )
                          : Icon(
                              Icons.business,
                              size: 28,
                              color: Colors.grey[600],
                            ),
                    ),
                    const SizedBox(width: 12),
                    // Name and role
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            org.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F2937),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: _getRoleColor(
                                    group.role,
                                  ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  group.role,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _getRoleColor(group.role),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                org.category,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Stats Grid
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildStatItem(
                          Icons.people,
                          group.memberCount.toString(),
                          'Members',
                          const Color(0xFF3B82F6),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: const Color(0xFFE5E7EB),
                      ),
                      Expanded(
                        child: _buildStatItem(
                          Icons.event,
                          group.eventCount.toString(),
                          'Events',
                          const Color(0xFF10B981),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: const Color(0xFFE5E7EB),
                      ),
                      Expanded(
                        child: _buildStatItem(
                          Icons.event_available,
                          group.activeEventCount.toString(),
                          'Active',
                          const Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                ),

                // Pending requests notification
                if (group.pendingRequestCount > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFBBF24)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.notifications_active,
                          size: 16,
                          color: Color(0xFFD97706),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${group.pendingRequestCount} pending join ${group.pendingRequestCount == 1 ? 'request' : 'requests'}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFD97706),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Quick Actions
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildActionChip(
                      icon: Icons.settings,
                      label: 'Settings',
                      onTap: () => _openSettings(org.id),
                    ),
                    _buildActionChip(
                      icon: Icons.people,
                      label: 'Members',
                      onTap: () => _openMembers(org.id),
                    ),
                    _buildActionChip(
                      icon: Icons.add_circle,
                      label: 'Post',
                      onTap: () => _showCreatePostOptions(org.id, org.name),
                    ),
                    _buildActionChip(
                      icon: Icons.analytics,
                      label: 'Analytics',
                      onTap: () => _openAnalytics(org.id),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
        ),
      ],
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF6B7280)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF374151),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'creator':
        return const Color(0xFF8B5CF6); // Purple
      case 'owner':
        return const Color(0xFFEC4899); // Pink
      case 'admin':
        return const Color(0xFF3B82F6); // Blue
      default:
        return const Color(0xFF6B7280); // Gray
    }
  }

  void _openGroupProfile(String organizationId) {
    RouterClass.nextScreenNormal(
      context,
      GroupProfileScreenV2(organizationId: organizationId),
    );
  }

  void _openSettings(String organizationId) {
    RouterClass.nextScreenNormal(
      context,
      GroupAdminSettingsScreen(organizationId: organizationId),
    );
  }

  void _openMembers(String organizationId) {
    RouterClass.nextScreenNormal(
      context,
      ManageMembersScreen(organizationId: organizationId),
    );
  }

  void _showCreatePostOptions(String organizationId, String groupName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    const Icon(Icons.add_circle, color: Color(0xFF667EEA)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Create Post',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                          Text(
                            groupName,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF6B7280),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Options
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.photo_library,
                    color: Color(0xFF667EEA),
                    size: 22,
                  ),
                ),
                title: const Text('Share Photo'),
                subtitle: const Text('Post photos to the group feed'),
                onTap: () async {
                  Navigator.pop(context);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CreatePhotoPostScreen(organizationId: organizationId),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.event,
                    color: Color(0xFF10B981),
                    size: 22,
                  ),
                ),
                title: const Text('Create Event'),
                subtitle: const Text('Schedule a new event for this group'),
                onTap: () async {
                  Navigator.pop(context);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PremiumEventCreationWrapper(
                        preselectedOrganizationId: organizationId,
                        forceOrganizationEvent: true,
                      ),
                    ),
                  );
                  // Refresh after creating event
                  _loadManagedGroups();
                },
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.announcement,
                    color: Color(0xFFF59E0B),
                    size: 22,
                  ),
                ),
                title: const Text('Post Announcement'),
                subtitle: const Text('Share important updates with members'),
                onTap: () async {
                  Navigator.pop(context);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CreateAnnouncementScreen(organizationId: organizationId),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.poll,
                    color: Color(0xFF8B5CF6),
                    size: 22,
                  ),
                ),
                title: const Text('Create Poll'),
                subtitle: const Text('Get feedback from group members'),
                onTap: () async {
                  Navigator.pop(context);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CreatePollScreen(organizationId: organizationId),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _openAnalytics(String organizationId) {
    RouterClass.nextScreenNormal(
      context,
      GroupAnalyticsDashboardScreen(organizationId: organizationId),
    );
  }
}

class _ManagedGroup {
  final OrganizationModel organization;
  final String role;
  final int memberCount;
  final int eventCount;
  final int activeEventCount;
  final int pendingRequestCount;

  _ManagedGroup({
    required this.organization,
    required this.role,
    required this.memberCount,
    required this.eventCount,
    required this.activeEventCount,
    required this.pendingRequestCount,
  });
}
