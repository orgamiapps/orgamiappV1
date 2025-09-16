import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/Events/single_event_screen.dart';
import 'package:attendus/screens/Groups/group_profile_screen_v2.dart';

enum _ModerationSource { feed, event }

class _ModerationItem {
  final String id;
  final String type;
  final bool isPinned;
  final bool isHidden;
  final Timestamp? createdAt;
  final _ModerationSource source;
  final Map<String, dynamic> data;

  const _ModerationItem({
    required this.id,
    required this.type,
    required this.isPinned,
    required this.isHidden,
    required this.createdAt,
    required this.source,
    required this.data,
  });
}

class ManageFeedPostsScreen extends StatefulWidget {
  final String organizationId;

  const ManageFeedPostsScreen({super.key, required this.organizationId});

  @override
  State<ManageFeedPostsScreen> createState() => _ManageFeedPostsScreenState();
}

class _ManageFeedPostsScreenState extends State<ManageFeedPostsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String _selectedFilter = 'all';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final List<String> _deletingPosts = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Manage Feed Posts',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.black),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(108),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search posts, polls, photos, events...',
                    prefixIcon: const Icon(Icons.search, color: Colors.black54),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip('All', 'all'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Announcements', 'announcement'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Polls', 'poll'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Photos', 'photo'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Events', 'event'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Pinned', 'pinned'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Hidden', 'hidden'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getFeedStream(),
        builder: (context, feedSnapshot) {
          final watchEvents =
              _selectedFilter == 'all' ||
              _selectedFilter == 'event' ||
              _selectedFilter == 'pinned' ||
              _selectedFilter == 'hidden';
          return StreamBuilder<QuerySnapshot>(
            stream: watchEvents ? _getEventsStream() : null,
            builder: (context, eventsSnapshot) {
              final snapshot = feedSnapshot; // alias for old code below
              if (snapshot.hasError ||
                  (watchEvents && (eventsSnapshot.hasError))) {
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
                          'Error loading content',
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

              if (snapshot.connectionState == ConnectionState.waiting ||
                  (watchEvents &&
                      (eventsSnapshot.connectionState ==
                          ConnectionState.waiting))) {
                return const Center(child: CircularProgressIndicator());
              }

              final List<QueryDocumentSnapshot> feedDocs =
                  snapshot.data?.docs.toList() ?? [];
              final List<QueryDocumentSnapshot> eventDocs = watchEvents
                  ? (eventsSnapshot.data?.docs.toList() ?? [])
                  : <QueryDocumentSnapshot>[];

              final List<_ModerationItem> items = [];

              for (final doc in feedDocs) {
                final data = doc.data() as Map<String, dynamic>;
                final type = (data['type'] ?? 'announcement').toString();
                final isHidden = data['isHidden'] == true;
                final isPinned = data['isPinned'] == true;

                if (_selectedFilter == 'announcement' &&
                    type != 'announcement') {
                  continue;
                }
                if (_selectedFilter == 'poll' && type != 'poll') continue;
                if (_selectedFilter == 'photo' && type != 'photo') continue;
                if (_selectedFilter == 'pinned' && !isPinned) continue;
                if (_selectedFilter == 'hidden' && !isHidden) continue;
                if (_selectedFilter == 'event') continue; // handled below

                // Search filter
                if (_searchQuery.trim().isNotEmpty) {
                  final q = _searchQuery.trim().toLowerCase();
                  final text =
                      (data['title'] ??
                              data['content'] ??
                              data['caption'] ??
                              data['question'] ??
                              '')
                          .toString()
                          .toLowerCase();
                  if (!text.contains(q)) continue;
                }

                items.add(
                  _ModerationItem(
                    id: doc.id,
                    type: type,
                    isPinned: isPinned,
                    isHidden: isHidden,
                    createdAt: data['createdAt'] as Timestamp?,
                    source: _ModerationSource.feed,
                    data: data,
                  ),
                );
              }

              for (final doc in eventDocs) {
                final data = doc.data() as Map<String, dynamic>;
                final isPinned = data['isPinned'] == true;
                final isHidden = data['isHidden'] == true;

                if (_selectedFilter == 'pinned' && !isPinned) continue;
                if (_selectedFilter == 'hidden' && !isHidden) continue;
                if (_selectedFilter != 'all' &&
                    _selectedFilter != 'event' &&
                    _selectedFilter != 'pinned' &&
                    _selectedFilter != 'hidden') {
                  // other filters are feed-only
                  continue;
                }

                if (_searchQuery.trim().isNotEmpty) {
                  final q = _searchQuery.trim().toLowerCase();
                  final text = (data['title'] ?? data['description'] ?? '')
                      .toString()
                      .toLowerCase();
                  if (!text.contains(q)) continue;
                }

                items.add(
                  _ModerationItem(
                    id: doc.id,
                    type: 'event',
                    isPinned: isPinned,
                    isHidden: isHidden,
                    createdAt:
                        (data['selectedDateTime'] ?? data['eventGenerateTime'])
                            as Timestamp?,
                    source: _ModerationSource.event,
                    data: data,
                  ),
                );
              }

              if (items.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 80,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No matching content',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Try a different filter or search query',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Sort: pinned first by order, then by date desc
              items.sort((a, b) {
                if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
                if (a.isPinned && b.isPinned) {
                  final ap = (a.data['pinnedOrder'] ?? 0) as int;
                  final bp = (b.data['pinnedOrder'] ?? 0) as int;
                  if (ap != bp) return ap.compareTo(bp);
                }
                final at = a.createdAt?.toDate();
                final bt = b.createdAt?.toDate();
                if (at == null || bt == null) return 0;
                return bt.compareTo(at);
              });

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  if (item.source == _ModerationSource.feed) {
                    return _buildPostCard(item.id, item.data);
                  } else {
                    return _buildEventCard(item.id, item.data);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openEvent(String eventId, Map<String, dynamic> data) async {
    try {
      final model = EventModel.fromJson({
        ...data,
        'id': eventId,
        'organizationId': data['organizationId'] ?? widget.organizationId,
      });
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SingleEventScreen(eventModel: model)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to open event: $e')));
    }
  }

  void _openFeedItem(String postId, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            GroupProfileScreenV2(organizationId: widget.organizationId),
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
      case 'photo':
        query = query.where('type', isEqualTo: 'photo');
        break;
      case 'pinned':
        query = query.where('isPinned', isEqualTo: true);
        break;
      case 'hidden':
        query = query.where('isHidden', isEqualTo: true);
        break;
    }

    return query.snapshots();
  }

  Stream<QuerySnapshot> _getEventsStream() {
    Query query = _db
        .collection('Events')
        .where('organizationId', isEqualTo: widget.organizationId)
        .orderBy('selectedDateTime', descending: true);

    if (_selectedFilter == 'pinned') {
      query = query.where('isPinned', isEqualTo: true);
    }
    if (_selectedFilter == 'hidden') {
      query = query.where('isHidden', isEqualTo: true);
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
    final isHidden = data['isHidden'] == true;
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
      case 'photo':
        typeIcon = Icons.photo;
        typeColor = Colors.purple;
        typeLabel = 'Photo';
        break;
      default:
        typeIcon = Icons.post_add;
        typeColor = Colors.grey;
        typeLabel = 'Post';
    }

    return InkWell(
      onTap: () => _openFeedItem(postId, data),
      borderRadius: BorderRadius.circular(12),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with type, pin/hidden status, and actions
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.1),
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
                        color: Colors.amber.withValues(alpha: 0.1),
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
                  if (isHidden) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.visibility_off,
                            size: 16,
                            color: Colors.grey,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Hidden',
                            style: TextStyle(
                              color: Colors.grey,
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
                    onSelected: (value) =>
                        _handlePostAction(value, postId, data),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'pin',
                        child: Row(
                          children: [
                            Icon(
                              isPinned
                                  ? Icons.push_pin_outlined
                                  : Icons.push_pin,
                            ),
                            const SizedBox(width: 12),
                            Text(isPinned ? 'Unpin Post' : 'Pin Post'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'hide',
                        child: Row(
                          children: [
                            Icon(
                              isHidden
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            const SizedBox(width: 12),
                            Text(isHidden ? 'Unhide' : 'Hide'),
                          ],
                        ),
                      ),
                      if (type == 'poll')
                        PopupMenuItem(
                          value: 'close_poll',
                          child: Row(
                            children: const [
                              Icon(Icons.stop_circle_outlined),
                              SizedBox(width: 12),
                              Text('Close Poll'),
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
              if (type == 'photo' && data['caption'] != null) ...[
                Text(
                  data['caption'].toString(),
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
                    backgroundColor: const Color(
                      0xFF667EEA,
                    ).withValues(alpha: 0.1),
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
      case 'hide':
        _toggleHidePost(postId, data['isHidden'] == true ? false : true);
        break;
      case 'close_poll':
        _closePoll(postId);
        break;
      case 'delete':
        _showDeleteConfirmation(postId, data);
        break;
    }
  }

  Future<void> _togglePinPost(String postId, bool pin) async {
    try {
      int nextOrder = 0;
      if (pin) {
        final snap = await _db
            .collection('Organizations')
            .doc(widget.organizationId)
            .collection('Feed')
            .where('isPinned', isEqualTo: true)
            .get();
        int maxOrder = 0;
        for (final d in snap.docs) {
          final data = (d.data() as Map<String, dynamic>?);
          final int po = (data?['pinnedOrder'] ?? 0) as int;
          if (po > maxOrder) maxOrder = po;
        }
        nextOrder = maxOrder + 1;
      }

      await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Feed')
          .doc(postId)
          .update({'isPinned': pin, 'pinnedOrder': nextOrder});

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

  Future<void> _toggleHidePost(String postId, bool hide) async {
    try {
      await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Feed')
          .doc(postId)
          .update({'isHidden': hide});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(hide ? 'Post hidden' : 'Post unhidden')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating visibility: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _closePoll(String postId) async {
    try {
      await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Feed')
          .doc(postId)
          .update({'isClosed': true});

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Poll closed')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error closing poll: $e')));
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

  // Event moderation card and helpers
  Widget _buildEventCard(String eventId, Map<String, dynamic> data) {
    final title = data['title']?.toString() ?? 'Untitled Event';
    final description = data['description']?.toString() ?? '';
    final date = (data['selectedDateTime'] as Timestamp?)?.toDate();
    final isPinned = data['isPinned'] == true;
    final isHidden = data['isHidden'] == true;
    final status = data['status']?.toString() ?? '';

    return InkWell(
      onTap: () => _openEvent(eventId, data),
      borderRadius: BorderRadius.circular(12),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event, size: 16, color: Colors.teal),
                        SizedBox(width: 4),
                        Text(
                          'Event',
                          style: TextStyle(
                            color: Colors.teal,
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
                        color: Colors.amber.withValues(alpha: 0.1),
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
                  if (isHidden) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.visibility_off,
                            size: 16,
                            color: Colors.grey,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Hidden',
                            style: TextStyle(
                              color: Colors.grey,
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
                    onSelected: (value) async {
                      switch (value) {
                        case 'pin':
                          await _togglePinEvent(eventId, !isPinned);
                          break;
                        case 'hide':
                          await _toggleHideEvent(eventId, !isHidden);
                          break;
                        case 'cancel':
                          await _toggleCancelEvent(
                            eventId,
                            status == 'cancelled' ? 'scheduled' : 'cancelled',
                          );
                          break;
                        case 'delete':
                          _showDeleteEventConfirmation(eventId, title);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'pin',
                        child: Row(
                          children: [
                            Icon(
                              isPinned
                                  ? Icons.push_pin_outlined
                                  : Icons.push_pin,
                            ),
                            const SizedBox(width: 12),
                            Text(isPinned ? 'Unpin Event' : 'Pin Event'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'hide',
                        child: Row(
                          children: [
                            Icon(
                              isHidden
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            const SizedBox(width: 12),
                            Text(isHidden ? 'Unhide' : 'Hide'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'cancel',
                        child: Row(
                          children: [
                            Icon(
                              status == 'cancelled'
                                  ? Icons.replay
                                  : Icons.cancel,
                              color: status == 'cancelled'
                                  ? null
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              status == 'cancelled'
                                  ? 'Reopen Event'
                                  : 'Cancel Event',
                            ),
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
                              'Delete Event',
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
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (date != null) ...[
                const SizedBox(height: 6),
                Text(
                  DateFormat('MMM d, y • h:mm a').format(date),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
              if (description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  description,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _togglePinEvent(String eventId, bool pin) async {
    try {
      int nextOrder = 0;
      if (pin) {
        final snap = await _db
            .collection('Events')
            .where('organizationId', isEqualTo: widget.organizationId)
            .where('isPinned', isEqualTo: true)
            .get();
        int maxOrder = 0;
        for (final d in snap.docs) {
          final data = (d.data() as Map<String, dynamic>?);
          final int po = (data?['pinnedOrder'] ?? 0) as int;
          if (po > maxOrder) maxOrder = po;
        }
        nextOrder = maxOrder + 1;
      }
      await _db.collection('Events').doc(eventId).update({
        'isPinned': pin,
        'pinnedOrder': nextOrder,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(pin ? 'Event pinned' : 'Event unpinned')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error pinning event: $e')));
      }
    }
  }

  Future<void> _toggleHideEvent(String eventId, bool hide) async {
    try {
      await _db.collection('Events').doc(eventId).update({'isHidden': hide});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(hide ? 'Event hidden' : 'Event unhidden')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating event visibility: $e')),
        );
      }
    }
  }

  Future<void> _toggleCancelEvent(String eventId, String status) async {
    try {
      await _db.collection('Events').doc(eventId).update({'status': status});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'cancelled' ? 'Event cancelled' : 'Event reopened',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating event: $e')));
      }
    }
  }

  void _showDeleteEventConfirmation(String eventId, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Event'),
        content: Text(
          'Are you sure you want to delete "$title"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _db.collection('Events').doc(eventId).delete();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Event deleted'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error deleting event: $e')),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

extension StringCapitalization on String {
  String capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}
