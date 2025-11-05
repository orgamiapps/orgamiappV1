import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:attendus/models/event_model.dart';

import 'package:attendus/screens/Groups/create_announcement_screen.dart';
import 'package:attendus/screens/Groups/create_poll_screen.dart';
import 'package:attendus/screens/Groups/create_photo_post_screen.dart';
import 'package:attendus/screens/Groups/post_comments_modal.dart';
import 'package:attendus/screens/Groups/photo_viewer_screen.dart';
import 'package:attendus/screens/MyProfile/user_profile_screen.dart';
import 'package:attendus/Utils/cached_image.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/screens/Events/single_event_screen.dart';

class EnhancedFeedTab extends StatefulWidget {
  final String organizationId;
  final Function(bool)? onScrollChange;

  const EnhancedFeedTab({
    super.key,
    required this.organizationId,
    this.onScrollChange,
  });

  @override
  State<EnhancedFeedTab> createState() => _EnhancedFeedTabState();
}

class _EnhancedFeedTabState extends State<EnhancedFeedTab> {
  // Core services
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  // Filter state
  String _selectedFilter = 'All';
  final List<String> _filterOptions = [
    'All',
    'Events',
    'Announcements',
    'Polls',
    'Photos',
  ];

  // Local state management for posts
  List<Map<String, dynamic>> _posts = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _error;
  bool _isAdmin = false;

  // Refresh controller for pull-to-refresh
  final RefreshController _refreshController = RefreshController(
    initialRefresh: false,
  );

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _refreshController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    await _checkIfAdmin();
    await _loadPosts();
  }

  Future<void> _checkIfAdmin() async {
    if (_currentUser == null) return;

    try {
      final orgDoc = await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .get();

      final createdBy = orgDoc.data()?['createdBy'];
      if (createdBy == _currentUser.uid) {
        setState(() => _isAdmin = true);
        return;
      }

      final memberDoc = await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Members')
          .doc(_currentUser.uid)
          .get();

      if (memberDoc.exists) {
        final role = memberDoc.data()?['role'];
        setState(() => _isAdmin = role == 'admin' || role == 'owner');
      }
    } catch (e) {
      debugPrint('Error checking admin status: $e');
    }
  }

  // Load posts from Firestore (one-time fetch)
  Future<void> _loadPosts({bool isRefresh = false}) async {
    if (isRefresh) {
      setState(() => _isRefreshing = true);
    } else {
      setState(() => _isLoading = true);
    }

    try {
      // Load feed posts
      final feedSnapshot = await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Feed')
          .orderBy('createdAt', descending: true)
          .get();

      // Load events
      final eventsSnapshot = await _db
          .collection('Events')
          .where('organizationId', isEqualTo: widget.organizationId)
          .get();

      final List<Map<String, dynamic>> combinedPosts = [];

      // Process feed posts
      for (var doc in feedSnapshot.docs) {
        final data = doc.data();
        combinedPosts.add({
          'id': doc.id,
          'type': 'feed',
          'feedType': data['type'] ?? 'announcement',
          'data': data,
          'timestamp': data['createdAt'],
          'isPinned': data['isPinned'] ?? false,
        });
      }

      // Process events
      for (var doc in eventsSnapshot.docs) {
        final data = doc.data();
        combinedPosts.add({
          'id': doc.id,
          'type': 'event',
          'data': data,
          'timestamp': data['eventGenerateTime'] ?? data['createdAt'],
          'isPinned': data['isPinned'] ?? false,
        });
      }

      // Sort by pinned first, then by timestamp
      combinedPosts.sort((a, b) {
        if (a['isPinned'] != b['isPinned']) {
          return a['isPinned'] ? -1 : 1;
        }
        final aTime = a['timestamp'];
        final bTime = b['timestamp'];
        if (aTime == null || bTime == null) return 0;
        return bTime.compareTo(aTime);
      });

      if (mounted) {
        setState(() {
          _posts = combinedPosts;
          _isLoading = false;
          _isRefreshing = false;
          _error = null;
        });
      }

      if (isRefresh) {
        _refreshController.refreshCompleted();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
          _isRefreshing = false;
        });
      }

      if (isRefresh) {
        _refreshController.refreshFailed();
      }
    }
  }

  // Refresh posts (pull-to-refresh)
  Future<void> _onRefresh() async {
    await _loadPosts(isRefresh: true);
  }

  Future<void> _toggleLike(String feedId) async {
    if (_currentUser == null) return;

    try {
      final docRef = _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Feed')
          .doc(feedId);

      await _db.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) return;

        final data = snapshot.data()!;
        final likes = List<String>.from(data['likes'] ?? []);

        if (likes.contains(_currentUser.uid)) {
          likes.remove(_currentUser.uid);
        } else {
          likes.add(_currentUser.uid);
        }

        transaction.update(docRef, {'likes': likes});
      });
    } catch (e) {
      debugPrint('Error toggling like: $e');
    }
  }

  Future<void> _toggleEventLike(String eventId) async {
    if (_currentUser == null) return;

    try {
      final docRef = _db.collection('Events').doc(eventId);

      await _db.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) return;

        final data = snapshot.data()!;
        final likes = List<String>.from(data['likes'] ?? []);

        if (likes.contains(_currentUser.uid)) {
          likes.remove(_currentUser.uid);
        } else {
          likes.add(_currentUser.uid);
        }

        transaction.update(docRef, {'likes': likes});
      });
    } catch (e) {
      debugPrint('Error toggling event like: $e');
    }
  }

  Future<void> _votePoll(String feedId, int optionIndex) async {
    if (_currentUser == null) return;

    try {
      final docRef = _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Feed')
          .doc(feedId);

      await _db.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) return;

        final data = snapshot.data()!;
        final options = List<Map<String, dynamic>>.from(data['options']);
        final voters = List<String>.from(data['voters'] ?? []);
        final allowMultiple = data['allowMultipleVotes'] ?? false;

        if (!allowMultiple && voters.contains(_currentUser.uid)) {
          throw Exception('You have already voted in this poll');
        }

        final votes = List<String>.from(options[optionIndex]['votes'] ?? []);
        if (!votes.contains(_currentUser.uid)) {
          votes.add(_currentUser.uid);
          options[optionIndex]['votes'] = votes;
          options[optionIndex]['voteCount'] = votes.length;
        }

        if (!voters.contains(_currentUser.uid)) {
          voters.add(_currentUser.uid);
        }

        transaction.update(docRef, {
          'options': options,
          'voters': voters,
          'totalVotes': voters.length,
        });
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Vote recorded!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void _showCreateOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: Color(0xFF667EEA)),
              title: const Text('Share Photo'),
              subtitle: const Text('Post photos to share with the group'),
              onTap: () async {
                Navigator.pop(context);
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreatePhotoPostScreen(
                      organizationId: widget.organizationId,
                    ),
                  ),
                );
                if (result == true && mounted) {
                  _loadPosts();
                }
              },
            ),
            FutureBuilder<bool>(
              future: Future.value(_isAdmin),
              builder: (context, snapshot) {
                if (snapshot.data == true) {
                  return Column(
                    children: [
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(
                          Icons.announcement,
                          color: Color(0xFF667EEA),
                        ),
                        title: const Text('Post Announcement'),
                        subtitle: const Text(
                          'Share important updates (Admin only)',
                        ),
                        onTap: () async {
                          Navigator.pop(context);
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CreateAnnouncementScreen(
                                organizationId: widget.organizationId,
                              ),
                            ),
                          );
                          if (result == true && mounted) {
                            _loadPosts();
                          }
                        },
                      ),
                      ListTile(
                        leading: const Icon(
                          Icons.poll,
                          color: Color(0xFF667EEA),
                        ),
                        title: const Text('Create Poll'),
                        subtitle: const Text(
                          'Get feedback from members (Admin only)',
                        ),
                        onTap: () async {
                          Navigator.pop(context);
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CreatePollScreen(
                                organizationId: widget.organizationId,
                              ),
                            ),
                          );
                          if (result == true && mounted) {
                            _loadPosts();
                          }
                        },
                      ),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 16,
            width: 150,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 12,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 12,
            width: 200,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && !_isRefreshing) {
      return ListView.builder(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).padding.bottom + 80,
        ),
        itemCount: 3,
        itemBuilder: (context, index) => _buildShimmerCard(),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text(
                'Error loading feed',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _loadPosts(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF667EEA),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Filter posts based on selected filter
    final filteredPosts = _posts.where((post) {
      if (_selectedFilter == 'All') return true;

      if (post['type'] == 'event') {
        return _selectedFilter == 'Events';
      }

      final feedType = post['feedType'];
      if (_selectedFilter == 'Announcements' && feedType == 'announcement')
        return true;
      if (_selectedFilter == 'Polls' && feedType == 'poll') return true;
      if (_selectedFilter == 'Photos' && feedType == 'photo') return true;

      return false;
    }).toList();

    if (filteredPosts.isEmpty) {
      return SmartRefresher(
        controller: _refreshController,
        onRefresh: _onRefresh,
        child: ListView(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).padding.bottom + 80,
          ),
          children: [
            const SizedBox(height: 80),
            Icon(Icons.feed_outlined, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 24),
            Text(
              'No posts yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to share something with the group!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 32),
            if (_currentUser != null)
              Center(
                child: FilledButton.icon(
                  onPressed: () => _showCreateOptions(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Create Post'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF667EEA),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Filter chips
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _filterOptions.length,
            itemBuilder: (context, index) {
              final filter = _filterOptions[index];
              final isSelected = _selectedFilter == filter;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(filter),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() => _selectedFilter = filter);
                  },
                  backgroundColor: Colors.grey.shade100,
                  selectedColor: const Color(0xFF667EEA).withValues(alpha: 0.2),
                  checkmarkColor: const Color(0xFF667EEA),
                  labelStyle: TextStyle(
                    color: isSelected
                        ? const Color(0xFF667EEA)
                        : Colors.grey.shade700,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              );
            },
          ),
        ),

        // Main feed
        Expanded(
          child: SmartRefresher(
            controller: _refreshController,
            onRefresh: _onRefresh,
            child: ListView.builder(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(context).padding.bottom + 80,
              ),
              itemCount: filteredPosts.length,
              itemBuilder: (context, index) {
                final post = filteredPosts[index];
                final postId = post['id'];
                final postData = post['data'];
                final isEvent = post['type'] == 'event';

                if (isEvent) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _EventPostCard(
                      key: ValueKey('event_$postId'),
                      data: postData,
                      docId: postId,
                      organizationId: widget.organizationId,
                      currentUserId: _currentUser?.uid,
                      onLike: () => _toggleEventLike(postId),
                      isAdmin: _isAdmin,
                      checkIfAdmin: () async => _isAdmin,
                    ),
                  );
                }

                final feedType = post['feedType'];

                if (feedType == 'poll') {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _PollCard(
                      key: ValueKey('poll_$postId'),
                      data: postData,
                      docId: postId,
                      organizationId: widget.organizationId,
                      onVote: (optionIndex) => _votePoll(postId, optionIndex),
                      currentUserId: _currentUser?.uid,
                      isAdmin: _isAdmin,
                      checkIfAdmin: () async => _isAdmin,
                      onLike: () => _toggleLike(postId),
                    ),
                  );
                } else if (feedType == 'photo') {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _PhotoPostCard(
                      key: ValueKey('photo_$postId'),
                      data: postData,
                      docId: postId,
                      organizationId: widget.organizationId,
                      currentUserId: _currentUser?.uid,
                      onLike: () => _toggleLike(postId),
                      isAdmin: _isAdmin,
                      checkIfAdmin: () async => _isAdmin,
                    ),
                  );
                } else {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _AnnouncementCard(
                      key: ValueKey('announcement_$postId'),
                      data: postData,
                      docId: postId,
                      organizationId: widget.organizationId,
                      onLike: () => _toggleLike(postId),
                      isAdmin: _isAdmin,
                      checkIfAdmin: () async => _isAdmin,
                      currentUserId: _currentUser?.uid,
                    ),
                  );
                }
              },
            ),
          ),
        ),

        // Floating action button for creating posts
        if (_currentUser != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: FloatingActionButton.extended(
              onPressed: () => _showCreateOptions(context),
              icon: const Icon(Icons.add),
              label: const Text('Create'),
              backgroundColor: const Color(0xFF667EEA),
            ),
          ),
      ],
    );
  }
}

class _PhotoPostCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String docId;
  final String organizationId;
  final String? currentUserId;
  final VoidCallback? onLike;
  final bool isAdmin;
  final Future<bool> Function() checkIfAdmin;

  const _PhotoPostCard({
    super.key,
    required this.data,
    required this.docId,
    required this.organizationId,
    this.currentUserId,
    this.onLike,
    this.isAdmin = false,
    required this.checkIfAdmin,
  });

  @override
  State<_PhotoPostCard> createState() => _PhotoPostCardState();
}

class _PhotoPostCardState extends State<_PhotoPostCard>
    with AutomaticKeepAliveClientMixin {
  late List<String> _localLikes;
  late bool _localIsLiked;
  bool _isUpdating = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _localLikes = List<String>.from(widget.data['likes'] ?? []);
    _localIsLiked =
        widget.currentUserId != null &&
        _localLikes.contains(widget.currentUserId);
  }

  Future<void> _handleLike() async {
    if (widget.currentUserId == null || _isUpdating) return;

    // Optimistic update
    setState(() {
      if (_localIsLiked) {
        _localLikes.remove(widget.currentUserId);
        _localIsLiked = false;
      } else {
        _localLikes.add(widget.currentUserId!);
        _localIsLiked = true;
      }
    });

    // Update Firestore in background
    _isUpdating = true;
    widget.onLike?.call();
    _isUpdating = false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final isPinned = widget.data['isPinned'] ?? false;
    final imageUrls = List<String>.from(widget.data['imageUrls'] ?? []);
    final caption = widget.data['caption'] ?? '';
    final authorName = widget.data['authorName'] ?? 'Unknown';
    final authorId = widget.data['authorId'] as String?;
    final authorRole = widget.data['authorRole'] ?? 'member';
    final createdAt = widget.data['createdAt'] as Timestamp?;
    final commentCount = widget.data['commentCount'] ?? 0;

    return _PostTypeContentWrapper(
      isPinned: isPinned,
      pinnedLabel: 'PINNED PHOTO',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unified header
          _UnifiedPostHeader(
            authorId: authorId,
            authorName: authorName,
            authorRole: authorRole,
            timestamp: createdAt,
            isAdmin: widget.isAdmin,
            isPinned: isPinned,
            docId: widget.docId,
            organizationId: widget.organizationId,
            postType: 'photo',
            checkIfAdmin: widget.checkIfAdmin,
          ),

          // Caption (moved above images for better readability)
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
              child: Text(
                caption,
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
            ),

          // Images
          if (imageUrls.isNotEmpty) ...[
            if (imageUrls.length == 1)
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PhotoViewerScreen(
                        imageUrls: imageUrls,
                        initialIndex: 0,
                        organizationId: widget.organizationId,
                        postId: widget.docId,
                        authorName: authorName,
                        caption: caption,
                        commentCount: commentCount,
                      ),
                    ),
                  );
                },
                child: AspectRatio(
                  aspectRatio: 1,
                  child: SafeNetworkImage(
                    imageUrl: imageUrls[0],
                    fit: BoxFit.cover,
                  ),
                ),
              )
            else if (imageUrls.length == 2)
              Row(
                children: imageUrls.asMap().entries.map((entry) {
                  final index = entry.key;
                  final url = entry.value;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PhotoViewerScreen(
                              imageUrls: imageUrls,
                              initialIndex: index,
                              organizationId: widget.organizationId,
                              postId: widget.docId,
                              authorName: authorName,
                              caption: caption,
                              commentCount: commentCount,
                            ),
                          ),
                        );
                      },
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: SafeNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                itemCount: imageUrls.length > 9 ? 9 : imageUrls.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PhotoViewerScreen(
                            imageUrls: imageUrls,
                            initialIndex: index,
                            organizationId: widget.organizationId,
                            postId: widget.docId,
                            authorName: authorName,
                            caption: caption,
                            commentCount: commentCount,
                          ),
                        ),
                      );
                    },
                    child: index == 8 && imageUrls.length > 9
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              SafeNetworkImage(
                                imageUrl: imageUrls[index],
                                fit: BoxFit.cover,
                              ),
                              Container(
                                color: Colors.black54,
                                child: Center(
                                  child: Text(
                                    '+${imageUrls.length - 9}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : SafeNetworkImage(
                            imageUrl: imageUrls[index],
                            fit: BoxFit.cover,
                          ),
                  );
                },
              ),
          ],

          // Unified footer with like/comment actions
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('Organizations')
                .doc(widget.organizationId)
                .collection('Feed')
                .doc(widget.docId)
                .snapshots(),
            builder: (context, snapshot) {
              final liveCommentCount = snapshot.data?.data() != null
                  ? ((snapshot.data!.data()
                            as Map<String, dynamic>)['commentCount'] ??
                        0)
                  : commentCount;

              return _UnifiedPostFooter(
                likeCount: _localLikes.length,
                isLiked: _localIsLiked,
                onLike: _handleLike,
                commentCount: liveCommentCount,
                onComment: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => PostCommentsModal(
                      postId: widget.docId,
                      postType: 'photo',
                      organizationId: widget.organizationId,
                      initialCommentCount: liveCommentCount,
                    ),
                  );
                },
                timestamp: createdAt,
                showShareButton: true,
              );
            },
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// UNIFIED POST COMPONENTS
// =============================================================================

/// Unified post header component used across all post types
class _UnifiedPostHeader extends StatelessWidget {
  final String? authorId;
  final String authorName;
  final String? authorRole;
  final Timestamp? timestamp;
  final bool isAdmin;
  final bool isPinned;
  final String docId;
  final String organizationId;
  final String postType; // 'photo', 'announcement', 'poll', 'event'
  final Future<bool> Function() checkIfAdmin;

  const _UnifiedPostHeader({
    required this.authorId,
    required this.authorName,
    this.authorRole,
    required this.timestamp,
    required this.isAdmin,
    required this.isPinned,
    required this.docId,
    required this.organizationId,
    required this.postType,
    required this.checkIfAdmin,
  });

  Future<String> _resolveAuthorName() async {
    final raw = authorName.trim();
    if (raw.isNotEmpty && raw.toLowerCase() != 'unknown') return raw;
    if (authorId != null && authorId!.isNotEmpty) {
      final user = await FirebaseFirestoreHelper().getSingleCustomer(
        customerId: authorId!,
      );
      if (user != null) {
        final resolved = user.name.trim().isNotEmpty
            ? user.name
            : (user.username ?? '').trim();
        if (resolved.isNotEmpty) return resolved;
      }
    }
    return 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: FutureBuilder<String>(
              future: _resolveAuthorName(),
              builder: (context, snapshot) {
                final displayName = (snapshot.data ?? authorName).trim();
                return Row(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        if (authorId == null) return;
                        try {
                          final user = await FirebaseFirestoreHelper()
                              .getSingleCustomer(customerId: authorId!);
                          if (user == null) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('User not found')),
                              );
                            }
                            return;
                          }
                          if (context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => UserProfileScreen(
                                  user: user,
                                  isOwnProfile:
                                      CustomerController.logeInCustomer?.uid ==
                                      user.uid,
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error loading profile: $e'),
                              ),
                            );
                          }
                        }
                      },
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFF667EEA),
                        child: Text(
                          displayName.isNotEmpty
                              ? displayName[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  displayName.isNotEmpty
                                      ? displayName
                                      : 'Unknown',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (authorRole == 'admin' ||
                                  authorRole == 'owner') ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF667EEA,
                                    ).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    authorRole!.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF667EEA),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (isAdmin)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
              onSelected: (value) async {
                if (value == 'pin' || value == 'unpin') {
                  final isAdminCheck = await checkIfAdmin();
                  if (!isAdminCheck) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Only admins can pin/unpin content'),
                        ),
                      );
                    }
                    return;
                  }

                  try {
                    final db = FirebaseFirestore.instance;
                    int nextOrder = 0;
                    if (value == 'pin') {
                      final collection = postType == 'event'
                          ? db.collection('Events')
                          : db
                                .collection('Organizations')
                                .doc(organizationId)
                                .collection('Feed');

                      final snap = await collection
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

                    final docRef = postType == 'event'
                        ? db.collection('Events').doc(docId)
                        : db
                              .collection('Organizations')
                              .doc(organizationId)
                              .collection('Feed')
                              .doc(docId);

                    await docRef.update({
                      'isPinned': value == 'pin',
                      'pinnedOrder': nextOrder,
                    });

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            value == 'pin'
                                ? '${postType.capitalize()} pinned'
                                : '${postType.capitalize()} unpinned',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: isPinned ? 'unpin' : 'pin',
                  child: Row(
                    children: [
                      Icon(
                        isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(isPinned ? 'Unpin' : 'Pin'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Unified post footer component with like/comment/share actions and animations
class _UnifiedPostFooter extends StatefulWidget {
  final int likeCount;
  final bool isLiked;
  final VoidCallback? onLike;
  final int commentCount;
  final VoidCallback? onComment;
  final Timestamp? timestamp;
  final bool showShareButton;

  const _UnifiedPostFooter({
    required this.likeCount,
    required this.isLiked,
    this.onLike,
    required this.commentCount,
    this.onComment,
    this.timestamp,
    this.showShareButton = false,
  });

  @override
  State<_UnifiedPostFooter> createState() => _UnifiedPostFooterState();
}

class _UnifiedPostFooterState extends State<_UnifiedPostFooter>
    with SingleTickerProviderStateMixin {
  late AnimationController _likeAnimController;
  late Animation<double> _likeScaleAnimation;

  @override
  void initState() {
    super.initState();
    _likeAnimController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _likeScaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _likeAnimController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _likeAnimController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_UnifiedPostFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Trigger animation when like state changes
    if (widget.isLiked != oldWidget.isLiked && widget.isLiked) {
      _likeAnimController.forward().then((_) {
        _likeAnimController.reverse();
      });
    }
  }

  String _formatDate(DateTime dateTime) {
    return DateFormat.yMMMd().format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: widget.onLike,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      AnimatedBuilder(
                        animation: _likeScaleAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _likeScaleAnimation.value,
                            child: Icon(
                              widget.isLiked
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: widget.isLiked
                                  ? Colors.red
                                  : Colors.grey.shade600,
                              size: 20,
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.likeCount.toString(),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              InkWell(
                onTap: widget.onComment,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.comment_outlined,
                        color: Colors.grey.shade600,
                        size: 20,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.commentCount.toString(),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.showShareButton) ...[
                const Spacer(),
                IconButton(
                  onPressed: () {
                    // TODO: Implement share functionality
                  },
                  icon: Icon(
                    Icons.share_outlined,
                    color: Colors.grey.shade600,
                    size: 20,
                  ),
                ),
              ],
            ],
          ),
          if (widget.timestamp != null) ...[
            const SizedBox(height: 4),
            Text(
              _formatDate(widget.timestamp!.toDate()),
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

/// Wrapper component for consistent post card styling
class _PostTypeContentWrapper extends StatelessWidget {
  final Widget child;
  final bool isPinned;
  final String? pinnedLabel;

  const _PostTypeContentWrapper({
    required this.child,
    required this.isPinned,
    this.pinnedLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isPinned
              ? Border.all(color: const Color(0xFF667EEA), width: 2)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isPinned)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFF667EEA),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.push_pin, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      pinnedLabel ?? 'PINNED',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

// Helper extension for string capitalization
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}

// Announcement Card - Refactored with optimistic UI updates
class _AnnouncementCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String docId;
  final String organizationId;
  final VoidCallback? onLike;
  final bool isAdmin;
  final Future<bool> Function() checkIfAdmin;
  final String? currentUserId;

  const _AnnouncementCard({
    super.key,
    required this.data,
    required this.docId,
    required this.organizationId,
    this.onLike,
    this.isAdmin = false,
    required this.checkIfAdmin,
    this.currentUserId,
  });

  @override
  State<_AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends State<_AnnouncementCard>
    with AutomaticKeepAliveClientMixin {
  late List<String> _localLikes;
  late bool _localIsLiked;
  bool _isUpdating = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _localLikes = List<String>.from(widget.data['likes'] ?? []);
    _localIsLiked =
        widget.currentUserId != null &&
        _localLikes.contains(widget.currentUserId);
  }

  Future<void> _handleLike() async {
    if (widget.currentUserId == null || _isUpdating) return;

    // Optimistic update
    setState(() {
      if (_localIsLiked) {
        _localLikes.remove(widget.currentUserId);
        _localIsLiked = false;
      } else {
        _localLikes.add(widget.currentUserId!);
        _localIsLiked = true;
      }
    });

    // Update Firestore in background
    _isUpdating = true;
    widget.onLike?.call();
    _isUpdating = false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final isPinned = widget.data['isPinned'] ?? false;
    final title = widget.data['title'] ?? '';
    final content = widget.data['content'] ?? '';
    final authorName = widget.data['authorName'] ?? 'Unknown';
    final authorId = widget.data['authorId'] as String?;
    final authorRole = widget.data['authorRole'] ?? 'member';
    final createdAt = widget.data['createdAt'] as Timestamp?;
    final commentCount = widget.data['commentCount'] ?? 0;

    return _PostTypeContentWrapper(
      isPinned: isPinned,
      pinnedLabel: 'PINNED ANNOUNCEMENT',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unified header
          _UnifiedPostHeader(
            authorId: authorId,
            authorName: authorName,
            authorRole: authorRole,
            timestamp: createdAt,
            isAdmin: widget.isAdmin,
            isPinned: isPinned,
            docId: widget.docId,
            organizationId: widget.organizationId,
            postType: 'announcement',
            checkIfAdmin: widget.checkIfAdmin,
          ),

          // Announcement content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Announcement icon and title
                Row(
                  children: [
                    Icon(
                      Icons.announcement,
                      color: const Color(0xFF667EEA),
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Content
                Text(
                  content,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
              ],
            ),
          ),

          // Unified footer with like/comment actions
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('Organizations')
                .doc(widget.organizationId)
                .collection('Feed')
                .doc(widget.docId)
                .snapshots(),
            builder: (context, snapshot) {
              final liveCommentCount = snapshot.data?.data() != null
                  ? ((snapshot.data!.data()
                            as Map<String, dynamic>)['commentCount'] ??
                        0)
                  : commentCount;

              return _UnifiedPostFooter(
                likeCount: _localLikes.length,
                isLiked: _localIsLiked,
                onLike: _handleLike,
                commentCount: liveCommentCount,
                onComment: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => PostCommentsModal(
                      postId: widget.docId,
                      postType: 'photo',
                      organizationId: widget.organizationId,
                      initialCommentCount: liveCommentCount,
                    ),
                  );
                },
                timestamp: createdAt,
                showShareButton: false,
              );
            },
          ),
        ],
      ),
    );
  }
}

// Event Post Card - New widget with optimistic UI updates
class _EventPostCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String docId;
  final String organizationId;
  final String? currentUserId;
  final VoidCallback? onLike;
  final bool isAdmin;
  final Future<bool> Function() checkIfAdmin;

  const _EventPostCard({
    super.key,
    required this.data,
    required this.docId,
    required this.organizationId,
    this.currentUserId,
    this.onLike,
    this.isAdmin = false,
    required this.checkIfAdmin,
  });

  @override
  State<_EventPostCard> createState() => _EventPostCardState();
}

class _EventPostCardState extends State<_EventPostCard>
    with AutomaticKeepAliveClientMixin {
  late List<String> _localLikes;
  late bool _localIsLiked;
  bool _isUpdating = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _localLikes = List<String>.from(widget.data['likes'] ?? []);
    _localIsLiked =
        widget.currentUserId != null &&
        _localLikes.contains(widget.currentUserId);
  }

  Future<void> _handleLike() async {
    if (widget.currentUserId == null || _isUpdating) return;

    // Optimistic update
    setState(() {
      if (_localIsLiked) {
        _localLikes.remove(widget.currentUserId);
        _localIsLiked = false;
      } else {
        _localLikes.add(widget.currentUserId!);
        _localIsLiked = true;
      }
    });

    // Update Firestore in background
    _isUpdating = true;
    widget.onLike?.call();
    _isUpdating = false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final isPinned = widget.data['isPinned'] ?? false;
    final title =
        widget.data['title'] ?? widget.data['eventTitle'] ?? 'Untitled Event';
    final description =
        widget.data['description'] ?? widget.data['eventDescription'] ?? '';
    final imageUrl = widget.data['imageUrl'] ?? '';
    final location = widget.data['location'] ?? '';
    final authorName =
        widget.data['authorName'] ??
        widget.data['customerName'] ??
        widget.data['groupName'] ??
        'Unknown';
    final authorId =
        widget.data['authorId'] ?? widget.data['customerUid'] ?? '';
    final authorRole = widget.data['authorRole'] ?? 'member';
    final createdAt =
        widget.data['createdAt'] ?? widget.data['eventGenerateTime'];
    final eventDateTime = widget.data['selectedDateTime'] as Timestamp?;
    final eventEndTime = widget.data['eventEndTime'] as Timestamp?;
    final commentCount = widget.data['commentCount'] ?? 0;

    return _PostTypeContentWrapper(
      isPinned: isPinned,
      pinnedLabel: 'PINNED EVENT',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unified header
          _UnifiedPostHeader(
            authorId: authorId,
            authorName: authorName,
            authorRole: authorRole,
            timestamp: createdAt is Timestamp ? createdAt : null,
            isAdmin: widget.isAdmin,
            isPinned: isPinned,
            docId: widget.docId,
            organizationId: widget.organizationId,
            postType: 'event',
            checkIfAdmin: widget.checkIfAdmin,
          ),

          // Event image (if available)
          if (imageUrl.isNotEmpty)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: SafeNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover),
            ),

          // Event content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Event badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.event,
                            color: const Color(0xFF667EEA),
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'EVENT',
                            style: const TextStyle(
                              color: Color(0xFF667EEA),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Event title
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),

                // Date & time
                if (eventDateTime != null)
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        color: const Color(0xFF667EEA),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          DateFormat.yMMMMd().format(eventDateTime.toDate()),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),

                // Time range
                if (eventDateTime != null && eventEndTime != null)
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        color: const Color(0xFF667EEA),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${DateFormat.jm().format(eventDateTime.toDate())} – ${DateFormat.jm().format(eventEndTime.toDate())}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),

                // Location
                if (location.isNotEmpty)
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        color: const Color(0xFF667EEA),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          location,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),

                // Description preview
                if (description.isNotEmpty)
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                      height: 1.5,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 16),

                // View Details button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      // Build event model for navigation
                      final eventModel = EventModel.fromJson({
                        ...widget.data,
                        'id': widget.docId,
                        'groupName': authorName,
                        'customerUid': authorId,
                      });
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              SingleEventScreen(eventModel: eventModel),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF667EEA),
                      side: const BorderSide(color: Color(0xFF667EEA)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'View Event Details',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Unified footer with like/comment actions
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('Events')
                .doc(widget.docId)
                .snapshots(),
            builder: (context, snapshot) {
              final liveData = snapshot.data?.data() as Map<String, dynamic>?;
              final liveCommentCount =
                  liveData?['commentCount'] ?? commentCount;

              return _UnifiedPostFooter(
                likeCount: _localLikes.length,
                isLiked: _localIsLiked,
                onLike: _handleLike,
                commentCount: liveCommentCount,
                onComment: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => PostCommentsModal(
                      postId: widget.docId,
                      postType: 'event',
                      organizationId: widget.organizationId,
                      initialCommentCount: liveCommentCount,
                    ),
                  );
                },
                timestamp: createdAt is Timestamp ? createdAt : null,
                showShareButton: false,
              );
            },
          ),
        ],
      ),
    );
  }
}

// Poll Card - Refactored with optimistic UI updates
class _PollCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String docId;
  final String organizationId;
  final Function(int) onVote;
  final String? currentUserId;
  final bool isAdmin;
  final Future<bool> Function() checkIfAdmin;
  final VoidCallback? onLike;

  const _PollCard({
    super.key,
    required this.data,
    required this.docId,
    required this.organizationId,
    required this.onVote,
    this.currentUserId,
    this.isAdmin = false,
    required this.checkIfAdmin,
    this.onLike,
  });

  @override
  State<_PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<_PollCard>
    with AutomaticKeepAliveClientMixin {
  late List<String> _localLikes;
  late bool _localIsLiked;
  bool _isUpdating = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _localLikes = List<String>.from(widget.data['likes'] ?? []);
    _localIsLiked =
        widget.currentUserId != null &&
        _localLikes.contains(widget.currentUserId);
  }

  Future<void> _handleLike() async {
    if (widget.currentUserId == null || _isUpdating) return;

    // Optimistic update
    setState(() {
      if (_localIsLiked) {
        _localLikes.remove(widget.currentUserId);
        _localIsLiked = false;
      } else {
        _localLikes.add(widget.currentUserId!);
        _localIsLiked = true;
      }
    });

    // Update Firestore in background
    _isUpdating = true;
    widget.onLike?.call();
    _isUpdating = false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final isPinned = widget.data['isPinned'] ?? false;
    final question = widget.data['question'] ?? '';
    final options = List<Map<String, dynamic>>.from(
      widget.data['options'] ?? [],
    );
    final voters = List<String>.from(widget.data['voters'] ?? []);
    final totalVotes = widget.data['totalVotes'] ?? 0;
    final hasVoted =
        widget.currentUserId != null && voters.contains(widget.currentUserId);
    final authorName = widget.data['authorName'] ?? 'Unknown';
    final authorId = widget.data['authorId'] as String?;
    final authorRole = widget.data['authorRole'] ?? 'member';
    final createdAt = widget.data['createdAt'] as Timestamp?;
    final commentCount = widget.data['commentCount'] ?? 0;

    return _PostTypeContentWrapper(
      isPinned: isPinned,
      pinnedLabel: 'PINNED POLL',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unified header
          _UnifiedPostHeader(
            authorId: authorId,
            authorName: authorName,
            authorRole: authorRole,
            timestamp: createdAt,
            isAdmin: widget.isAdmin,
            isPinned: isPinned,
            docId: widget.docId,
            organizationId: widget.organizationId,
            postType: 'poll',
            checkIfAdmin: widget.checkIfAdmin,
          ),

          // Poll content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Poll badge and question
                Row(
                  children: [
                    const Icon(Icons.poll, color: Color(0xFF667EEA), size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'POLL',
                      style: TextStyle(
                        color: Color(0xFF667EEA),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  question,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                // Poll options
                ...options.asMap().entries.map((entry) {
                  final index = entry.key;
                  final option = entry.value;
                  final votes = List<String>.from(option['votes'] ?? []);
                  final percentage = totalVotes > 0
                      ? (votes.length / totalVotes * 100).round()
                      : 0;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: hasVoted ? null : () => widget.onVote(index),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color:
                                hasVoted && votes.contains(widget.currentUserId)
                                ? const Color(0xFF667EEA)
                                : Colors.grey.shade300,
                            width:
                                hasVoted && votes.contains(widget.currentUserId)
                                ? 2
                                : 1,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Stack(
                          children: [
                            if (hasVoted)
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF667EEA,
                                    ).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: percentage / 100,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF667EEA,
                                        ).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(11),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      option['text'] ?? '',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                  if (hasVoted) ...[
                                    Text(
                                      '$percentage%',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '(${votes.length})',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                // Vote count summary
                Text(
                  '$totalVotes ${totalVotes == 1 ? 'vote' : 'votes'}',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Unified footer with like/comment actions
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('Organizations')
                .doc(widget.organizationId)
                .collection('Feed')
                .doc(widget.docId)
                .snapshots(),
            builder: (context, snapshot) {
              final liveCommentCount = snapshot.data?.data() != null
                  ? ((snapshot.data!.data()
                            as Map<String, dynamic>)['commentCount'] ??
                        0)
                  : commentCount;

              return _UnifiedPostFooter(
                likeCount: _localLikes.length,
                isLiked: _localIsLiked,
                onLike: _handleLike,
                commentCount: liveCommentCount,
                onComment: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => PostCommentsModal(
                      postId: widget.docId,
                      postType: 'photo',
                      organizationId: widget.organizationId,
                      initialCommentCount: liveCommentCount,
                    ),
                  );
                },
                timestamp: createdAt,
                showShareButton: false,
              );
            },
          ),
        ],
      ),
    );
  }
}
