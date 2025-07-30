import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:orgami/Controller/CustomerController.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Models/CommentModel.dart';
import 'package:orgami/Models/EventModel.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:orgami/Utils/dimensions.dart';

class CommentsSection extends StatefulWidget {
  final EventModel eventModel;

  const CommentsSection({
    super.key,
    required this.eventModel,
  });

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  List<CommentModel> comments = [];
  bool isLoading = true;
  final TextEditingController _commentController = TextEditingController();
  final FirebaseFirestoreHelper _firestoreHelper = FirebaseFirestoreHelper();
  bool isAddingComment = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      setState(() {
        isLoading = true;
      });

      print('Loading comments for event: ${widget.eventModel.id}');
      final commentsList = await _firestoreHelper.getEventComments(
        eventId: widget.eventModel.id,
      );

      print('Loaded ${commentsList.length} comments');
      for (var comment in commentsList) {
        print('Comment: ${comment.userName} - ${comment.comment}');
      }

      setState(() {
        comments = commentsList;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      print('Error loading comments: $e');
    }
  }

  Future<void> _addComment() async {
    final trimmedComment = _commentController.text.trim();
    if (trimmedComment.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a comment')),
      );
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
        await _loadComments(); // Reload comments
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comment added successfully!')),
        );
      }
      // On failure, error is already shown by addComment
    } catch (e) {
      print('Error adding comment: $e');
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
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Comments Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Comments (${comments.length})',
                  style: const TextStyle(
                    color: AppThemeColor.pureBlackColor,
                    fontSize: Dimensions.fontSizeLarge,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                GestureDetector(
                  onTap: _loadComments,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppThemeColor.darkGreenColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.refresh,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Add Comment Section
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // User Profile Picture
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.grey[300],
                  child: CustomerController.logeInCustomer?.profilePictureUrl !=
                          null
                      ? ClipOval(
                          child: Image.network(
                            CustomerController
                                .logeInCustomer!.profilePictureUrl!,
                            width: 36,
                            height: 36,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.person,
                                size: 20,
                                color: Colors.grey,
                              );
                            },
                          ),
                        )
                      : const Icon(
                          Icons.person,
                          size: 20,
                          color: Colors.grey,
                        ),
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
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _addComment(),
                  ),
                ),

                const SizedBox(width: 8),

                // Send Button
                GestureDetector(
                  onTap: isAddingComment ? null : _addComment,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isAddingComment
                          ? Colors.grey
                          : AppThemeColor.darkGreenColor,
                      shape: BoxShape.circle,
                    ),
                    child: isAddingComment
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.send,
                            color: Colors.white,
                            size: 20,
                          ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Comments List
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(
                      color: AppThemeColor.darkGreenColor,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Loading comments...',
                      style: TextStyle(
                        color: AppThemeColor.dullFontColor,
                        fontSize: Dimensions.fontSizeSmall,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (comments.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Column(
                  children: [
                    const Text(
                      'No comments yet. Be the first to comment!',
                      style: TextStyle(
                        color: AppThemeColor.dullFontColor,
                        fontSize: Dimensions.fontSizeDefault,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Event ID: ${widget.eventModel.id}',
                      style: const TextStyle(
                        color: AppThemeColor.dullFontColor,
                        fontSize: Dimensions.fontSizeSmall,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: comments.length,
              itemBuilder: (context, index) {
                final comment = comments[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // User Profile Picture
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.grey[300],
                        child: comment.userProfilePictureUrl != null
                            ? ClipOval(
                                child: Image.network(
                                  comment.userProfilePictureUrl!,
                                  width: 36,
                                  height: 36,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(
                                      Icons.person,
                                      size: 20,
                                      color: Colors.grey,
                                    );
                                  },
                                ),
                              )
                            : const Icon(
                                Icons.person,
                                size: 20,
                                color: Colors.grey,
                              ),
                      ),

                      const SizedBox(width: 12),

                      // Comment Content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  comment.userName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: Dimensions.fontSizeDefault,
                                    color: AppThemeColor.pureBlackColor,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatDateTime(comment.createdAt),
                                  style: const TextStyle(
                                    color: AppThemeColor.dullFontColor,
                                    fontSize: Dimensions.fontSizeSmall,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              comment.comment,
                              style: const TextStyle(
                                fontSize: Dimensions.fontSizeDefault,
                                color: AppThemeColor.pureBlackColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
