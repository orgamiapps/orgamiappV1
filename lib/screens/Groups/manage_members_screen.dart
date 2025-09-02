import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';


class ManageMembersScreen extends StatefulWidget {
  final String organizationId;

  const ManageMembersScreen({
    super.key,
    required this.organizationId,
  });

  @override
  State<ManageMembersScreen> createState() => _ManageMembersScreenState();
}

class _ManageMembersScreenState extends State<ManageMembersScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'all';
  String _searchQuery = '';
  bool _isCurrentUserOwner = false;
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
    } catch (e) {
      // Handle error
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Members'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(120),
          child: Column(
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All Members', 'all'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Admins', 'admin'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Regular Members', 'member'),
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
                    Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                    const SizedBox(height: 16),
                    const Text('Error loading members', style: TextStyle(fontSize: 18)),
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
              final data = member.data() as Map<String, dynamic>;
              return _buildMemberCard(member.id, data);
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
      selectedColor: const Color(0xFF667EEA).withOpacity(0.2),
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

  List<QueryDocumentSnapshot> _filterMembers(List<QueryDocumentSnapshot> members) {
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
    final email = data['email']?.toString() ?? '';
    final role = data['role']?.toString() ?? 'member';
    final status = data['status']?.toString() ?? 'approved';
    final joinedAt = (data['joinedAt'] as Timestamp?)?.toDate();
    final profilePictureUrl = data['profilePictureUrl']?.toString();

    final isOwner = role == 'owner';
    final isAdmin = role == 'admin' || isOwner;
    final isPending = status == 'pending';
    final isCurrentUser = memberId == _currentUserId;

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
      roleColor = Colors.green;
      roleIcon = Icons.person;
      roleLabel = 'Member';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                // Profile Picture
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFF667EEA).withOpacity(0.1),
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
                                color: Colors.grey.withOpacity(0.2),
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
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          email,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
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
                    color: roleColor.withOpacity(0.1),
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
                if (!isCurrentUser && (_isCurrentUserOwner || (isAdmin && !isOwner)))
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) => _handleMemberAction(value, memberId, data),
                    itemBuilder: (context) => _buildMemberActions(data),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMemberActions(Map<String, dynamic> data) {
    final role = data['role']?.toString() ?? 'member';
    final status = data['status']?.toString() ?? 'approved';
    final isAdmin = role == 'admin' || role == 'owner';
    final isPending = status == 'pending';

    List<PopupMenuEntry<String>> actions = [];

    if (isPending) {
      actions.addAll([
        const PopupMenuItem(
          value: 'approve',
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
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
    } else {
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
                Text(isAdmin ? 'Remove Admin' : 'Make Admin'),
              ],
            ),
          ),
        );
      }

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

    return actions;
  }

  void _handleMemberAction(String action, String memberId, Map<String, dynamic> data) {
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

  Future<void> _promoteMember(String memberId, Map<String, dynamic> data) async {
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
