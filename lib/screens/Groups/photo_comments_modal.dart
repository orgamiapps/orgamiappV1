import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/screens/MyProfile/user_profile_screen.dart';

/// Instagram-style comments modal for photo posts in group feed
class PhotoCommentsModal extends StatefulWidget {
  final String organizationId;
  final String postId;
  final int initialCommentCount;

  const PhotoCommentsModal({
    super.key,
    required this.organizationId,
    required this.postId,
    required this.initialCommentCount,
  });

  @override
  State<PhotoCommentsModal> createState() => _PhotoCommentsModalState();
}

class _PhotoCommentsModalState extends State<PhotoCommentsModal> {
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFirestoreHelper _firestoreHelper = FirebaseFirestoreHelper();
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  
  bool _isSubmitting = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _currentUser == null) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final currentUserData = CustomerController.logeInCustomer;
      final userName = currentUserData?.name ?? 
                       currentUserData?.username ?? 
                       'Anonymous';
      final userPhotoUrl = currentUserData?.profilePictureUrl;

      await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Feed')
          .doc(widget.postId)
          .collection('Comments')
          .add({
        'userId': _currentUser.uid,
        'userName': userName,
        'userPhotoUrl': userPhotoUrl,
        'comment': text,
        'createdAt': FieldValue.serverTimestamp(),
        'likes': [],
      });

      // Update comment count on the post
      await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Feed')
          .doc(widget.postId)
          .update({
        'commentCount': FieldValue.increment(1),
      });

      _commentController.clear();
      _focusNode.unfocus();

      if (mounted) {
        // Scroll to bottom to show new comment
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add comment: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _deleteComment(String commentId) async {
    try {
      await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Feed')
          .doc(widget.postId)
          .collection('Comments')
          .doc(commentId)
          .delete();

      // Update comment count
      await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Feed')
          .doc(widget.postId)
          .update({
        'commentCount': FieldValue.increment(-1),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Comment deleted'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete comment: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleLike(String commentId, List<String> currentLikes) async {
    if (_currentUser == null) return;

    final isLiked = currentLikes.contains(_currentUser.uid);
    final updatedLikes = List<String>.from(currentLikes);

    if (isLiked) {
      updatedLikes.remove(_currentUser.uid);
    } else {
      updatedLikes.add(_currentUser.uid);
    }

    try {
      await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Feed')
          .doc(widget.postId)
          .collection('Comments')
          .doc(commentId)
          .update({'likes': updatedLikes});
    } catch (e) {
      debugPrint('Error toggling like: $e');
    }
  }

  Future<void> _navigateToProfile(String userId) async {
    try {
      final user = await _firestoreHelper.getSingleCustomer(customerId: userId);
      if (user != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserProfileScreen(
              user: user,
              isOwnProfile: _currentUser?.uid == user.uid,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey.shade200,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                StreamBuilder<QuerySnapshot>(
                  stream: _db
                      .collection('Organizations')
                      .doc(widget.organizationId)
                      .collection('Feed')
                      .doc(widget.postId)
                      .collection('Comments')
                      .snapshots(),
                  builder: (context, snapshot) {
                    final count = snapshot.data?.docs.length ?? 
                                  widget.initialCommentCount;
                    return Text(
                      'Comments ($count)',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 22),
                  onPressed: () => Navigator.pop(context),
                  color: Colors.grey.shade700,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          // Comments list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db
                  .collection('Organizations')
                  .doc(widget.organizationId)
                  .collection('Feed')
                  .doc(widget.postId)
                  .collection('Comments')
                  .orderBy('createdAt', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF667EEA),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No comments yet',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Be the first to comment!',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final comments = snapshot.data!.docs;

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final comment = comments[index];
                    final data = comment.data() as Map<String, dynamic>;
                    final userId = data['userId'] as String?;
                    final userName = data['userName'] as String? ?? 'Anonymous';
                    final userPhotoUrl = data['userPhotoUrl'] as String?;
                    final commentText = data['comment'] as String? ?? '';
                    final createdAt = data['createdAt'] as Timestamp?;
                    final likes = List<String>.from(data['likes'] ?? []);
                    final isLiked = _currentUser != null && 
                                   likes.contains(_currentUser.uid);
                    final isOwn = userId == _currentUser?.uid;

                    return _CommentItem(
                      userId: userId,
                      userName: userName,
                      userPhotoUrl: userPhotoUrl,
                      commentText: commentText,
                      createdAt: createdAt,
                      likes: likes,
                      isLiked: isLiked,
                      isOwn: isOwn,
                      onProfileTap: () {
                        if (userId != null) {
                          _navigateToProfile(userId);
                        }
                      },
                      onLikeTap: () => _toggleLike(comment.id, likes),
                      onDelete: () => _deleteComment(comment.id),
                    );
                  },
                );
              },
            ),
          ),

          // Comment input
          Container(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottomPadding),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(
                  color: Colors.grey.shade200,
                  width: 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  // User avatar
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFF667EEA),
                    backgroundImage: CustomerController
                                .logeInCustomer?.profilePictureUrl != null
                        ? NetworkImage(
                            CustomerController
                                .logeInCustomer!.profilePictureUrl!,
                          )
                        : null,
                    child: CustomerController
                                .logeInCustomer?.profilePictureUrl == null
                        ? Text(
                            (CustomerController.logeInCustomer?.name ?? 'U')
                                .substring(0, 1)
                                .toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  // Text field
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 100),
                      child: TextField(
                        controller: _commentController,
                        focusNode: _focusNode,
                        enabled: !_isSubmitting,
                        decoration: InputDecoration(
                          hintText: 'Add a comment...',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                              color: Colors.grey.shade300,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                              color: Colors.grey.shade300,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: const BorderSide(
                              color: Color(0xFF667EEA),
                              width: 1.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 14),
                        maxLines: null,
                        textInputAction: TextInputAction.newline,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Send button
                  _isSubmitting
                      ? const SizedBox(
                          width: 36,
                          height: 36,
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF667EEA),
                              ),
                            ),
                          ),
                        )
                      : IconButton(
                          onPressed: _addComment,
                          icon: const Icon(Icons.send),
                          color: const Color(0xFF667EEA),
                          iconSize: 22,
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentItem extends StatelessWidget {
  final String? userId;
  final String userName;
  final String? userPhotoUrl;
  final String commentText;
  final Timestamp? createdAt;
  final List<String> likes;
  final bool isLiked;
  final bool isOwn;
  final VoidCallback onProfileTap;
  final VoidCallback onLikeTap;
  final VoidCallback onDelete;

  const _CommentItem({
    required this.userId,
    required this.userName,
    required this.userPhotoUrl,
    required this.commentText,
    required this.createdAt,
    required this.likes,
    required this.isLiked,
    required this.isOwn,
    required this.onProfileTap,
    required this.onLikeTap,
    required this.onDelete,
  });

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      return '${dateTime.month}/${dateTime.day}/${dateTime.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'now';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          GestureDetector(
            onTap: onProfileTap,
            child: CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF667EEA),
              backgroundImage: userPhotoUrl != null && userPhotoUrl!.isNotEmpty
                  ? NetworkImage(userPhotoUrl!)
                  : null,
              child: userPhotoUrl == null || userPhotoUrl!.isEmpty
                  ? Text(
                      userName.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          // Comment content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: userName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                            const TextSpan(text: ' '),
                            TextSpan(
                              text: commentText,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Like button
                    GestureDetector(
                      onTap: onLikeTap,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(
                          isLiked ? Icons.favorite : Icons.favorite_border,
                          size: 16,
                          color: isLiked ? Colors.red : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (createdAt != null)
                      Text(
                        _getTimeAgo(createdAt!.toDate()),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    if (likes.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Text(
                        '${likes.length} ${likes.length == 1 ? 'like' : 'likes'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (isOwn) ...[
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete Comment'),
                              content: const Text(
                                'Are you sure you want to delete this comment?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    onDelete();
                                  },
                                  child: const Text(
                                    'Delete',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        child: Text(
                          'Delete',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
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
      ),
    );
  }
}

