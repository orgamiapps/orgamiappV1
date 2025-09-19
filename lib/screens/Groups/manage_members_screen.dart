import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:attendus/screens/MyProfile/user_profile_screen.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';

class ManageMembersScreen extends StatefulWidget {
  final String organizationId;

  const ManageMembersScreen({super.key, required this.organizationId});

  @override
  State<ManageMembersScreen> createState() => _ManageMembersScreenState();
}

class _ManageMembersScreenState extends State<ManageMembersScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'all';
  String _searchQuery = '';
  bool _isCurrentUserOwner = false;
  bool _isCurrentUserAdmin = false;
  bool _isCurrentUserEventCreator = false;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _checkCurrentUserRole();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
    });
  }

  Future<void> _checkCurrentUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _currentUserId = user.uid;

    try {
      // Check if current user is the owner
      final orgDoc = await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .get();

      final createdBy = orgDoc.data()?['createdBy'];
      setState(() {
        _isCurrentUserOwner = createdBy == user.uid;
      });

      // Check if current user is an admin (from membership role)
      try {
        final memberDoc = await _db
            .collection('Organizations')
            .doc(widget.organizationId)
            .collection('Members')
            .doc(user.uid)
            .get();

        final role = (memberDoc.data()?['role']?.toString() ?? '')
            .toLowerCase();
        setState(() {
          _isCurrentUserAdmin = _isCurrentUserOwner || role == 'admin';
        });
      } catch (_) {
        // Ignore, default admin stays false unless owner
        setState(() {
          _isCurrentUserAdmin = _isCurrentUserOwner;
        });
      }

      // Check if current user is the creator of any event within this organization
      try {
        final eventsQuery = await _db
            .collection('Events')
            .where('organizationId', isEqualTo: widget.organizationId)
            .where('customerUid', isEqualTo: user.uid)
            .limit(1)
            .get();
        setState(() {
          _isCurrentUserEventCreator = eventsQuery.docs.isNotEmpty;
        });
      } catch (_) {
        // Leave as false on error
      }
    } catch (e) {
      // Handle error
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Manage Members',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.black87),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(120),
          child: Column(
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search members...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              // Filter Chips
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All Members', 'all'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Admins', 'admin'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Members', 'member'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Pending', 'pending'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getMembersStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red.shade300,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Error loading members',
                      style: TextStyle(fontSize: 18),
                    ),
                  ],
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState();
          }

          final members = snapshot.data!.docs;
          final filteredMembers = _filterMembers(members);

          if (filteredMembers.isEmpty) {
            return _buildEmptyState(isFiltered: true);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filteredMembers.length,
            itemBuilder: (context, index) {
              final member = filteredMembers[index];
              final memberData = member.data() as Map<String, dynamic>;

              return FutureBuilder<Map<String, dynamic>>(
                future: _enrichMemberData(member.id, memberData),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: const Color(
                                0xFF667EEA,
                              ).withValues(alpha: 0.1),
                              child: const Icon(
                                Icons.person,
                                color: Color(0xFF667EEA),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Loading...',
                                    style: TextStyle(fontSize: 16),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Please wait',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final enrichedData = snapshot.data ?? memberData;
                  return _buildMemberCard(member.id, enrichedData);
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = value;
        });
      },
      selectedColor: const Color(0xFF667EEA).withValues(alpha: 0.2),
      checkmarkColor: const Color(0xFF667EEA),
    );
  }

  Stream<QuerySnapshot> _getMembersStream() {
    return _db
        .collection('Organizations')
        .doc(widget.organizationId)
        .collection('Members')
        .snapshots();
  }

  Future<Map<String, dynamic>> _enrichMemberData(
    String memberId,
    Map<String, dynamic> memberData,
  ) async {
    try {
      // Fetch user profile data from Customers collection
      final userDoc = await _db.collection('Customers').doc(memberId).get();
      if (userDoc.exists) {
        final userData = userDoc.data()!;
        // Merge membership data with user profile data
        return {
          ...memberData, // membership data (role, status, joinedAt, etc.)
          'name': userData['name'] ?? userData['displayName'] ?? 'Unknown User',
          'email': userData['email'] ?? '',
          'profilePictureUrl': userData['profilePictureUrl'],
        };
      }
    } catch (e) {
      // If user fetch fails, return original data
    }
    return memberData;
  }

  List<QueryDocumentSnapshot> _filterMembers(
    List<QueryDocumentSnapshot> members,
  ) {
    return members.where((member) {
      final data = member.data() as Map<String, dynamic>;
      final name = (data['name']?.toString() ?? '').toLowerCase();
      final email = (data['email']?.toString() ?? '').toLowerCase();
      final role = data['role']?.toString() ?? 'member';
      final status = data['status']?.toString() ?? 'approved';

      // Filter by search query
      if (_searchQuery.isNotEmpty) {
        if (!name.contains(_searchQuery) && !email.contains(_searchQuery)) {
          return false;
        }
      }

      // Filter by role/status
      switch (_selectedFilter) {
        case 'admin':
          return role == 'admin' || role == 'owner';
        case 'member':
          return role == 'member' && status == 'approved';
        case 'pending':
          return status == 'pending';
        default:
          return true;
      }
    }).toList();
  }

  Widget _buildEmptyState({bool isFiltered = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isFiltered ? Icons.search_off : Icons.people_outline,
              size: 80,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 24),
            Text(
              isFiltered ? 'No members found' : 'No members yet',
              style: TextStyle(fontSize: 20, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Text(
              isFiltered
                  ? 'Try adjusting your search or filters'
                  : 'Members will appear here when they join the group',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberCard(String memberId, Map<String, dynamic> data) {
    final name = data['name']?.toString() ?? 'Unknown';
    final role = data['role']?.toString() ?? 'member';
    final status = data['status']?.toString() ?? 'approved';
    final joinedAt = (data['joinedAt'] as Timestamp?)?.toDate();
    final profilePictureUrl = data['profilePictureUrl']?.toString();

    final isOwner = role == 'owner';
    final isAdmin = role == 'admin' || isOwner;
    final isPending = status == 'pending';
    final isCurrentUser = memberId == _currentUserId;

    // Permission logic for action visibility
    final bool canCurrentUserManage =
        !isCurrentUser &&
        (_isCurrentUserOwner ||
            _isCurrentUserEventCreator ||
            (_isCurrentUserAdmin && !isAdmin));

    Color roleColor;
    IconData roleIcon;
    String roleLabel;

    if (isOwner) {
      roleColor = Colors.purple;
      roleIcon = Icons.star;
      roleLabel = 'Owner';
    } else if (isAdmin) {
      roleColor = Colors.blue;
      roleIcon = Icons.admin_panel_settings;
      roleLabel = 'Admin';
    } else if (isPending) {
      roleColor = Colors.orange;
      roleIcon = Icons.hourglass_empty;
      roleLabel = 'Pending';
    } else {
      roleColor = const Color(0xFF667EEA);
      roleIcon = Icons.person;
      roleLabel = 'Member';
    }

    return InkWell(
      onTap: () => _openMemberProfile(memberId),
      borderRadius: BorderRadius.circular(12),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Profile Picture
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFF667EEA).withValues(alpha: 0.1),
                backgroundImage: profilePictureUrl != null
                    ? NetworkImage(profilePictureUrl)
                    : null,
                child: profilePictureUrl == null
                    ? Icon(
                        Icons.person,
                        color: const Color(0xFF667EEA),
                        size: 24,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              // Member Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCurrentUser) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'You',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (joinedAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Joined ${_formatDate(joinedAt)}',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Role Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(roleIcon, size: 16, color: roleColor),
                    const SizedBox(width: 4),
                    Text(
                      roleLabel,
                      style: TextStyle(
                        color: roleColor,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Actions Menu
              if (canCurrentUserManage) ...[
                const SizedBox(width: 8),
                Builder(
                  builder: (context) {
                    final actions = _buildMemberActions(data);
                    if (actions.isEmpty) return const SizedBox.shrink();
                    return PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) =>
                          _handleMemberAction(value, memberId, data),
                      itemBuilder: (context) => actions,
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMemberActions(Map<String, dynamic> data) {
    final role = data['role']?.toString() ?? 'member';
    final status = data['status']?.toString() ?? 'approved';
    final isAdmin = role == 'admin' || role == 'owner';
    final isOwner = role == 'owner';
    final isPending = status == 'pending';

    List<PopupMenuEntry<String>> actions = [];

    if (isPending) {
      // Owner and Admins can approve/reject pending requests
      if (_isCurrentUserOwner || _isCurrentUserAdmin) {
        actions.addAll([
          const PopupMenuItem(
            value: 'approve',
            child: Row(
              children: [
                Icon(Icons.check_circle, color: const Color(0xFF667EEA)),
                SizedBox(width: 12),
                Text('Approve'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'reject',
            child: Row(
              children: [
                Icon(Icons.cancel, color: Colors.red),
                SizedBox(width: 12),
                Text('Reject'),
              ],
            ),
          ),
        ]);
      }
    } else {
      // Owner can promote/demote admins and remove anyone (except self handled elsewhere)
      if (_isCurrentUserOwner) {
        actions.add(
          PopupMenuItem(
            value: isAdmin ? 'demote' : 'promote',
            child: Row(
              children: [
                Icon(
                  isAdmin ? Icons.person_remove : Icons.person_add,
                  color: isAdmin ? Colors.orange : Colors.blue,
                ),
                const SizedBox(width: 12),
                Text(isAdmin ? 'Demote to Member' : 'Make Admin'),
              ],
            ),
          ),
        );
        actions.add(
          const PopupMenuItem(
            value: 'remove',
            child: Row(
              children: [
                Icon(Icons.person_remove, color: Colors.red),
                SizedBox(width: 12),
                Text('Remove from Group', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        );
      } else if (_isCurrentUserEventCreator) {
        // Event creators can promote members to admin and demote admins to member (but not the owner)
        if (!isAdmin) {
          actions.add(
            const PopupMenuItem(
              value: 'promote',
              child: Row(
                children: [
                  Icon(Icons.person_add, color: Colors.blue),
                  SizedBox(width: 12),
                  Text('Make Admin'),
                ],
              ),
            ),
          );
        } else if (!isOwner) {
          actions.add(
            const PopupMenuItem(
              value: 'demote',
              child: Row(
                children: [
                  Icon(Icons.person_remove, color: Colors.orange),
                  SizedBox(width: 12),
                  Text('Demote to Member'),
                ],
              ),
            ),
          );
        }
        // Event creators do not gain extra remove permissions
      } else if (_isCurrentUserAdmin && !isAdmin) {
        // Admins can remove regular members only
        actions.add(
          const PopupMenuItem(
            value: 'remove',
            child: Row(
              children: [
                Icon(Icons.person_remove, color: Colors.red),
                SizedBox(width: 12),
                Text('Remove from Group', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        );
      }
    }

    return actions;
  }

  void _handleMemberAction(
    String action,
    String memberId,
    Map<String, dynamic> data,
  ) {
    switch (action) {
      case 'approve':
        _approveMember(memberId);
        break;
      case 'reject':
        _rejectMember(memberId);
        break;
      case 'promote':
        _promoteMember(memberId, data);
        break;
      case 'demote':
        _demoteMember(memberId, data);
        break;
      case 'remove':
        _showRemoveMemberDialog(memberId, data);
        break;
    }
  }

  Future<void> _approveMember(String memberId) async {
    try {
      await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Members')
          .doc(memberId)
          .update({
            'status': 'approved',
            'approvedAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Member approved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error approving member: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rejectMember(String memberId) async {
    try {
      await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Members')
          .doc(memberId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Member request rejected'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error rejecting member: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _promoteMember(
    String memberId,
    Map<String, dynamic> data,
  ) async {
    if (!(_isCurrentUserOwner || _isCurrentUserEventCreator)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Only the event creator or group owner can make admins',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    try {
      await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Members')
          .doc(memberId)
          .update({
            'role': 'admin',
            'promotedAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${data['name']} promoted to admin'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error promoting member: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _demoteMember(String memberId, Map<String, dynamic> data) async {
    if (!(_isCurrentUserOwner || _isCurrentUserEventCreator)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Only the event creator or group owner can demote admins',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    try {
      await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Members')
          .doc(memberId)
          .update({
            'role': 'member',
            'demotedAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${data['name']} removed from admin role'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error demoting member: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showRemoveMemberDialog(String memberId, Map<String, dynamic> data) {
    final name = data['name']?.toString() ?? 'this member';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text(
          'Are you sure you want to remove $name from this group? They will no longer have access to group content and events.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _removeMember(memberId, data);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Future<void> _removeMember(String memberId, Map<String, dynamic> data) async {
    try {
      await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Members')
          .doc(memberId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${data['name']} removed from group'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing member: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openMemberProfile(String userId) async {
    try {
      final CustomerModel? user = await FirebaseFirestoreHelper()
          .getSingleCustomer(customerId: userId);
      if (!mounted) return;
      if (user == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile not available')));
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserProfileScreen(
            user: user,
            isOwnProfile: userId == _currentUserId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to open profile: $e')));
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'today';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return months == 1 ? '1 month ago' : '$months months ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return years == 1 ? '1 year ago' : '$years years ago';
    }
  }
}
