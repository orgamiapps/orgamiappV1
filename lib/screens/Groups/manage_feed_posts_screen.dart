import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:intl/intl.dart';

class ManageFeedPostsScreen extends StatefulWidget {
  final String organizationId;

  const ManageFeedPostsScreen({super.key, required this.organizationId});

  @override
  State<ManageFeedPostsScreen> createState() => _ManageFeedPostsScreenState();
}

class _ManageFeedPostsScreenState extends State<ManageFeedPostsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String _selectedFilter = 'all';
  final List<String> _deletingPosts = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Feed Posts'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('All Posts', 'all'),
                        const SizedBox(width: 8),
                        _buildFilterChip('Announcements', 'announcement'),
                        const SizedBox(width: 8),
                        _buildFilterChip('Polls', 'poll'),
                        const SizedBox(width: 8),
                        _buildFilterChip('Pinned', 'pinned'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getFeedStream(),
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
                      'Error loading posts',
                      style: TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please try again later',
                      style: TextStyle(color: Colors.grey.shade600),
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
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.feed_outlined,
                      size: 80,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _selectedFilter == 'all'
                          ? 'No posts yet'
                          : 'No ${_selectedFilter} posts',
                      style: TextStyle(
                        fontSize: 20,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Posts will appear here when they are created.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            );
          }

          final posts = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = posts[index];
              final data = post.data() as Map<String, dynamic>;
              return _buildPostCard(post.id, data);
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

  Stream<QuerySnapshot> _getFeedStream() {
    Query query = _db
        .collection('Organizations')
        .doc(widget.organizationId)
        .collection('Feed')
        .orderBy('createdAt', descending: true);

    switch (_selectedFilter) {
      case 'announcement':
        query = query.where('type', isEqualTo: 'announcement');
        break;
      case 'poll':
        query = query.where('type', isEqualTo: 'poll');
        break;
      case 'pinned':
        query = query.where('isPinned', isEqualTo: true);
        break;
    }

    return query.snapshots();
  }

  Widget _buildPostCard(String postId, Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? 'unknown';
    final title = data['title']?.toString() ?? '';
    final content = data['content']?.toString() ?? '';
    final authorName = data['authorName']?.toString() ?? 'Unknown';
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    final isPinned = data['isPinned'] == true;
    final isDeleting = _deletingPosts.contains(postId);

    IconData typeIcon;
    Color typeColor;
    String typeLabel;

    switch (type) {
      case 'announcement':
        typeIcon = Icons.announcement;
        typeColor = Colors.orange;
        typeLabel = 'Announcement';
        break;
      case 'poll':
        typeIcon = Icons.poll;
        typeColor = Colors.blue;
        typeLabel = 'Poll';
        break;
      default:
        typeIcon = Icons.post_add;
        typeColor = Colors.grey;
        typeLabel = 'Post';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with type, pin status, and actions
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(typeIcon, size: 16, color: typeColor),
                      const SizedBox(width: 4),
                      Text(
                        typeLabel,
                        style: TextStyle(
                          color: typeColor,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isPinned) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.push_pin,
                          size: 16,
                          color: Colors.amber.shade700,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Pinned',
                          style: TextStyle(
                            color: Colors.amber.shade700,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) => _handlePostAction(value, postId, data),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'pin',
                      child: Row(
                        children: [
                          Icon(
                            isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                          ),
                          const SizedBox(width: 12),
                          Text(isPinned ? 'Unpin Post' : 'Pin Post'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red),
                          SizedBox(width: 12),
                          Text(
                            'Delete Post',
                            style: TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Title (if exists)
            if (title.isNotEmpty) ...[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Content
            if (content.isNotEmpty) ...[
              Text(
                content,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
            ],

            // Poll options preview (if it's a poll)
            if (type == 'poll' && data['options'] != null) ...[
              _buildPollPreview(data['options'] as List),
              const SizedBox(height: 12),
            ],

            // Footer with author and date
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: const Color(0xFF667EEA).withOpacity(0.1),
                  child: Icon(
                    Icons.person,
                    size: 16,
                    color: const Color(0xFF667EEA),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        authorName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                      if (createdAt != null)
                        Text(
                          DateFormat('MMM d, y • h:mm a').format(createdAt),
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                if (isDeleting) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPollPreview(List options) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Poll Options:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          ...options.take(3).map((option) {
            final text = option['text']?.toString() ?? '';
            final voteCount = (option['voteCount'] as num?)?.toInt() ?? 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.radio_button_unchecked,
                    size: 16,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '$voteCount votes',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            );
          }).toList(),
          if (options.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '... and ${options.length - 3} more options',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _handlePostAction(
    String action,
    String postId,
    Map<String, dynamic> data,
  ) {
    switch (action) {
      case 'pin':
        _togglePinPost(postId, data['isPinned'] != true);
        break;
      case 'delete':
        _showDeleteConfirmation(postId, data);
        break;
    }
  }

  Future<void> _togglePinPost(String postId, bool pin) async {
    try {
      await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Feed')
          .doc(postId)
          .update({'isPinned': pin});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pin ? 'Post pinned successfully' : 'Post unpinned successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error ${pin ? 'pinning' : 'unpinning'} post: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showDeleteConfirmation(String postId, Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? 'post';
    final title = data['title']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${type.capitalize()}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete this ${type}?'),
            if (title.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '"$title"',
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'This action cannot be undone.',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePost(postId);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePost(String postId) async {
    setState(() {
      _deletingPosts.add(postId);
    });

    try {
      await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Feed')
          .doc(postId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Post deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting post: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _deletingPosts.remove(postId);
      });
    }
  }
}

extension StringCapitalization on String {
  String capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}
