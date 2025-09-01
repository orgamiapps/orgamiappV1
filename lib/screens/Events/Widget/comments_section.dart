import 'package:flutter/material.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/comment_model.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/MyProfile/user_profile_screen.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/Utils/logger.dart';

class CommentsSection extends StatefulWidget {
  final EventModel eventModel;

  const CommentsSection({super.key, required this.eventModel});

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  List<CommentModel> comments = [];
  bool isLoading = true;
  final FirebaseFirestoreHelper _firestoreHelper = FirebaseFirestoreHelper();

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    try {
      setState(() {
        isLoading = true;
      });

      Logger.debug('Loading comments for event: ${widget.eventModel.id}');
      var commentsList = await _firestoreHelper.getEventComments(
        eventId: widget.eventModel.id,
      );

      // Filter out comments from blocked users
      final currentUserId = CustomerController.logeInCustomer?.uid;
      if (currentUserId != null && currentUserId.isNotEmpty) {
        try {
          final blocksSnap = await FirebaseFirestore.instance
              .collection('Customers')
              .doc(currentUserId)
              .collection('blocks')
              .get();
          final blocked = blocksSnap.docs.map((d) => d.id).toSet();
          commentsList = commentsList
              .where((c) => !blocked.contains(c.userId))
              .toList();
        } catch (_) {}
      }

      Logger.debug('Loaded ${commentsList.length} comments');
      for (var comment in commentsList) {
        Logger.debug('Comment: ${comment.userName} - ${comment.comment}');
      }

      setState(() {
        comments = commentsList;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      Logger.error('Error loading comments: $e');
    }
  }

  void _showCommentsModal() async {
    // Refresh comments before opening modal
    await _loadComments();

    if (mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => CommentsModal(
          eventModel: widget.eventModel,
          comments: comments,
          onCommentsUpdated: _loadComments,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: GestureDetector(
        onTap: _showCommentsModal,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                spreadRadius: 0,
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.chat_bubble_outline,
                    color: Color(0xFF667EEA),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Comments',
                    style: const TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${comments.length}',
                      style: const TextStyle(
                        color: Color(0xFF667EEA),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const Icon(
                Icons.keyboard_arrow_up,
                color: Color(0xFF667EEA),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CommentsModal extends StatefulWidget {
  final EventModel eventModel;
  final List<CommentModel> comments;
  final VoidCallback onCommentsUpdated;

  const CommentsModal({
    super.key,
    required this.eventModel,
    required this.comments,
    required this.onCommentsUpdated,
  });

  @override
  State<CommentsModal> createState() => _CommentsModalState();
}

class _CommentsModalState extends State<CommentsModal> {
  final TextEditingController _commentController = TextEditingController();
  final FirebaseFirestoreHelper _firestoreHelper = FirebaseFirestoreHelper();
  bool isAddingComment = false;
  List<CommentModel> comments = [];

  @override
  void initState() {
    super.initState();
    comments = List.from(
      widget.comments,
    ); // Create a copy to avoid reference issues
  }

  @override
  void didUpdateWidget(CommentsModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update comments when widget.comments changes
    if (widget.comments != oldWidget.comments) {
      setState(() {
        comments = List.from(widget.comments);
      });
    }
  }

  Future<void> _addComment() async {
    final trimmedComment = _commentController.text.trim();
    if (trimmedComment.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a comment')));
      return;
    }

    try {
      setState(() {
        isAddingComment = true;
      });

      final success = await _firestoreHelper.addComment(
        eventId: widget.eventModel.id.toString().trim(),
        comment: trimmedComment,
        context: context,
      );

      if (success) {
        _commentController.clear();
        // Update the parent widget's comments
        widget.onCommentsUpdated();
        // Also update local comments list
        setState(() {
          // Add optimistic comment to local list
          final newComment = CommentModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            eventId: widget.eventModel.id,
            userId: CustomerController.logeInCustomer?.uid ?? '',
            userName: CustomerController.logeInCustomer?.name ?? 'Anonymous',
            comment: trimmedComment,
            createdAt: DateTime.now(),
            userProfilePictureUrl:
                CustomerController.logeInCustomer?.profilePictureUrl,
          );
          comments.insert(0, newComment); // Add to top
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comment added successfully!')),
        );
      }
    } catch (e) {
      Logger.error('Error adding comment: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding comment: ${e.toString()}')),
      );
    } finally {
      setState(() {
        isAddingComment = false;
      });
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF667EEA).withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.chat_bubble_outline,
                  color: Color(0xFF667EEA),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Comments (${comments.length})',
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Roboto',
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.close,
                    color: Color(0xFF6B7280),
                    size: 24,
                  ),
                ),
              ],
            ),
          ),

          // Add Comment Section (YouTube-style)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                // User Profile Picture
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.grey[300],
                  child:
                      CustomerController.logeInCustomer?.profilePictureUrl !=
                          null
                      ? ClipOval(
                          child: Image.network(
                            CustomerController
                                .logeInCustomer!
                                .profilePictureUrl!,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.person,
                                size: 24,
                                color: Colors.grey,
                              );
                            },
                          ),
                        )
                      : const Icon(Icons.person, size: 24, color: Colors.grey),
                ),
                const SizedBox(width: 12),
                // Comment Input
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: 'Add a comment...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      suffixIcon: isAddingComment
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: Padding(
                                padding: EdgeInsets.all(8.0),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF667EEA),
                                ),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(
                                Icons.send,
                                color: Color(0xFF667EEA),
                              ),
                              onPressed: _addComment,
                            ),
                    ),
                    minLines: 1,
                    maxLines: 3,
                  ),
                ),
              ],
            ),
          ),

          // Comments List
          Expanded(
            child: comments.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No comments yet',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Roboto',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Be the first to comment!',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 14,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: comments.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final comment = comments[index];
                      return _buildCommentItem(comment);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentItem(CommentModel comment) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Avatar
        GestureDetector(
          onTap: () => _showUserProfile(comment.userId),
          child: CircleAvatar(
            radius: 20,
            backgroundColor: Colors.grey[200],
            child:
                comment.userProfilePictureUrl != null &&
                    comment.userProfilePictureUrl!.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      comment.userProfilePictureUrl!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.person,
                          size: 24,
                          color: Colors.grey,
                        );
                      },
                    ),
                  )
                : const Icon(Icons.person, size: 24, color: Colors.grey),
          ),
        ),
        const SizedBox(width: 12),
        // Comment content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _showUserProfile(comment.userId),
                      child: Text(
                        comment.userName,
                        style: const TextStyle(
                          color: Color(0xFF1A1A1A),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatTimestamp(comment.createdAt),
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                      fontFamily: 'Roboto',
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      switch (value) {
                        case 'report':
                          await FirebaseFirestoreHelper().submitUserReport(
                            type: 'comment',
                            contentId: comment.id,
                            targetUserId: comment.userId,
                            reason: 'inappropriate_content',
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Report submitted. Thank you.'),
                            ),
                          );
                          break;
                        case 'block':
                          final blockerId =
                              CustomerController.logeInCustomer!.uid;
                          final blockedId = comment.userId;
                          await FirebaseFirestoreHelper().blockUser(
                            blockerId: blockerId,
                            blockedUserId: blockedId,
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('User blocked')),
                          );
                          break;
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'report', child: Text('Report')),
                      PopupMenuItem(value: 'block', child: Text('Block User')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                comment.comment,
                style: const TextStyle(
                  color: Color(0xFF4B5563),
                  fontSize: 14,
                  fontFamily: 'Roboto',
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return '';
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${timestamp.year}/${timestamp.month.toString().padLeft(2, '0')}/${timestamp.day.toString().padLeft(2, '0')}';
  }

  Future<void> _showUserProfile(String? userId) async {
    if (userId == null || userId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User profile not available')),
      );
      return;
    }

    try {
      final user = await _firestoreHelper.getSingleCustomer(customerId: userId);
      if (user != null) {
        if (!mounted) return;
        Navigator.pop(context); // Close comments modal first
        if (!mounted) return;
        RouterClass.nextScreenNormal(
          context,
          UserProfileScreen(
            user: user,
            isOwnProfile: CustomerController.logeInCustomer?.uid == user.uid,
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('User profile not found')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading user profile: $e')));
    }
  }
}
