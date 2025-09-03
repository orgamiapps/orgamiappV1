import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/Events/single_event_screen.dart';
import 'package:attendus/screens/Groups/create_announcement_screen.dart';
import 'package:attendus/screens/Groups/create_poll_screen.dart';
import 'package:attendus/screens/Groups/create_photo_post_screen.dart';
import 'package:attendus/screens/MyProfile/user_profile_screen.dart';
import 'package:attendus/Utils/cached_image.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/screens/Groups/widgets/event_card.dart';

class EnhancedFeedTab extends StatefulWidget {
  final String organizationId;
  const EnhancedFeedTab({super.key, required this.organizationId});

  @override
  State<EnhancedFeedTab> createState() => _EnhancedFeedTabState();
}

class _EnhancedFeedTabState extends State<EnhancedFeedTab> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  String _selectedFilter = 'All';
  final List<String> _filterOptions = [
    'All',
    'Announcements',
    'Polls',
    'Photos',
    'Events',
  ];

  Future<bool> _checkIfAdmin() async {
    if (_currentUser == null) return false;

    try {
      final orgDoc = await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .get();

      final createdBy = orgDoc.data()?['createdBy'];
      if (createdBy == _currentUser.uid) return true;

      final memberDoc = await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Members')
          .doc(_currentUser.uid)
          .get();

      if (memberDoc.exists) {
        final role = memberDoc.data()?['role'];
        return role == 'admin' || role == 'owner';
      }
    } catch (e) {
      debugPrint('Error checking admin status: $e');
    }
    return false;
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

  @override
  Widget build(BuildContext context) {
    final feedStream = _db
        .collection('Organizations')
        .doc(widget.organizationId)
        .collection('Feed')
        .orderBy('createdAt', descending: true)
        .snapshots();

    final eventsStream = _db
        .collection('Events')
        .where('organizationId', isEqualTo: widget.organizationId)
        .orderBy('selectedDateTime', descending: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: feedStream,
      builder: (context, feedSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: eventsStream,
          builder: (context, eventsSnapshot) {
            if (feedSnapshot.connectionState == ConnectionState.waiting ||
                eventsSnapshot.connectionState == ConnectionState.waiting) {
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: 3,
                itemBuilder: (context, index) => _buildShimmerCard(),
              );
            }

            if (feedSnapshot.hasError || eventsSnapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Colors.red.shade300,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading feed',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => setState(() {}),
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

            final feedDocs = feedSnapshot.data?.docs ?? [];
            final eventDocs = eventsSnapshot.data?.docs ?? [];

            if (feedDocs.isEmpty && eventDocs.isEmpty) {
              return RefreshIndicator(
                onRefresh: () async {
                  setState(() {});
                  await Future.delayed(const Duration(seconds: 1));
                },
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const SizedBox(height: 80),
                    Icon(
                      Icons.feed_outlined,
                      size: 80,
                      color: Colors.grey.shade300,
                    ),
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
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                      ),
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

            final List<dynamic> combinedItems = [];

            // Add feed items (announcements, polls, photos)
            for (var doc in feedDocs) {
              final data = doc.data() as Map<String, dynamic>;
              final type = data['type'] ?? 'announcement';

              // Apply filter
              if (_selectedFilter != 'All') {
                if (_selectedFilter == 'Announcements' &&
                    type != 'announcement')
                  continue;
                if (_selectedFilter == 'Polls' && type != 'poll') continue;
                if (_selectedFilter == 'Photos' && type != 'photo') continue;
                if (_selectedFilter == 'Events')
                  continue; // Skip feed items if Events filter
              }

              combinedItems.add({
                'type': 'feed',
                'doc': doc,
                'timestamp': data['createdAt'],
                'isPinned': data['isPinned'] ?? false,
              });
            }

            // Add events as regular feed items
            for (var doc in eventDocs) {
              final data = doc.data() as Map<String, dynamic>;

              // Apply filter
              if (_selectedFilter != 'All' && _selectedFilter != 'Events')
                continue;

              combinedItems.add({
                'type': 'event',
                'doc': doc,
                'timestamp':
                    data['selectedDateTime'] ?? data['eventGenerateTime'],
                'isPinned': data['isPinned'] ?? false,
              });
            }

            // Sort all items: pinned items first, then by timestamp (most recent first)
            combinedItems.sort((a, b) {
              final aPinned = a['isPinned'] as bool;
              final bPinned = b['isPinned'] as bool;

              // If one is pinned and the other isn't, pinned comes first
              if (aPinned != bPinned) {
                return aPinned ? -1 : 1;
              }

              // If both have same pinned status, sort by timestamp
              final aTime = a['timestamp'] as Timestamp?;
              final bTime = b['timestamp'] as Timestamp?;

              if (aTime == null || bTime == null) return 0;
              return bTime.compareTo(aTime);
            });

            return RefreshIndicator(
              onRefresh: () async {
                setState(() {});
                await Future.delayed(const Duration(seconds: 1));
              },
              child: Column(
                children: [
                  // Filter button
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _filterOptions.map((filter) {
                                final isSelected = _selectedFilter == filter;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: FilterChip(
                                    label: Text(filter),
                                    selected: isSelected,
                                    onSelected: (selected) {
                                      setState(() {
                                        _selectedFilter = filter;
                                      });
                                    },
                                    backgroundColor: Colors.grey.shade100,
                                    selectedColor: const Color(0xFF667EEA),
                                    labelStyle: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.black87,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                    checkmarkColor: Colors.white,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: FutureBuilder<bool>(
                      future: _checkIfAdmin(),
                      builder: (context, adminSnapshot) {
                        final isAdmin = adminSnapshot.data ?? false;

                        return ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: combinedItems.length,
                          itemBuilder: (context, index) {
                            final item = combinedItems[index];

                            if (item['type'] == 'event') {
                              // Display event as a card
                              final doc = item['doc'] as DocumentSnapshot;
                              final data = doc.data() as Map<String, dynamic>;
                              return EventCard(
                                data: data,
                                docId: doc.id,
                                organizationId: widget.organizationId,
                                isAdmin: isAdmin,
                              );
                            } else if (item['type'] == 'feed') {
                              final doc = item['doc'] as DocumentSnapshot;
                              final data = doc.data() as Map<String, dynamic>;
                              final feedType = data['type'] ?? 'announcement';

                              if (feedType == 'poll') {
                                return _PollCard(
                                  data: data,
                                  docId: doc.id,
                                  organizationId: widget.organizationId,
                                  onVote: (optionIndex) =>
                                      _votePoll(doc.id, optionIndex),
                                  currentUserId: _currentUser?.uid,
                                  isAdmin: isAdmin,
                                  checkIfAdmin: _checkIfAdmin,
                                );
                              } else if (feedType == 'photo') {
                                return _PhotoPostCard(
                                  data: data,
                                  docId: doc.id,
                                  organizationId: widget.organizationId,
                                  currentUserId: _currentUser?.uid,
                                  onLike: () => _toggleLike(doc.id),
                                  isAdmin: isAdmin,
                                  checkIfAdmin: _checkIfAdmin,
                                );
                              } else {
                                return _AnnouncementCard(
                                  data: data,
                                  docId: doc.id,
                                  organizationId: widget.organizationId,
                                  onLike: () => _toggleLike(doc.id),
                                  isAdmin: isAdmin,
                                  checkIfAdmin: _checkIfAdmin,
                                );
                              }
                            }
                            return const SizedBox.shrink();
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
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
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 120,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 80,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
                  setState(() {});
                }
              },
            ),
            FutureBuilder<bool>(
              future: _checkIfAdmin(),
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
                            setState(() {});
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
                            setState(() {});
                          }
                        },
                      ),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// Upcoming Events Card Widget
class _UpcomingEventsCard extends StatelessWidget {
  final List<DocumentSnapshot> events;
  final String organizationId;

  const _UpcomingEventsCard({
    required this.events,
    required this.organizationId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF667EEA), const Color(0xFF764BA2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event, color: Colors.white),
                const SizedBox(width: 8),
                const Text(
                  'Upcoming Events',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${events.length} events',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: events.length,
                itemBuilder: (context, index) {
                  final eventData =
                      events[index].data() as Map<String, dynamic>;
                  final event = EventModel.fromJson({
                    ...eventData,
                    'id': events[index].id,
                  });

                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SingleEventScreen(eventModel: event),
                        ),
                      );
                    },
                    child: Container(
                      width: 200,
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                size: 14,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                DateFormat.MMMd().format(
                                  event.selectedDateTime,
                                ),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.access_time,
                                size: 14,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                DateFormat.jm().format(event.selectedDateTime),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Photo Post Card Widget
class _PhotoPostCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final String organizationId;
  final String? currentUserId;
  final VoidCallback? onLike;
  final bool isAdmin;
  final Future<bool> Function() checkIfAdmin;

  const _PhotoPostCard({
    required this.data,
    required this.docId,
    required this.organizationId,
    this.currentUserId,
    this.onLike,
    this.isAdmin = false,
    required this.checkIfAdmin,
  });

  @override
  Widget build(BuildContext context) {
    final isPinned = data['isPinned'] ?? false;
    final imageUrls = List<String>.from(data['imageUrls'] ?? []);
    final likes = List<String>.from(data['likes'] ?? []);
    final isLiked = currentUserId != null && likes.contains(currentUserId);
    final caption = data['caption'] ?? '';
    final authorName = data['authorName'] ?? 'Unknown';
    final authorRole = data['authorRole'] ?? 'member';
    final createdAt = data['createdAt'] as Timestamp?;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isPinned
            ? Border.all(color: const Color(0xFF667EEA), width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF667EEA),
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.push_pin, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'PINNED PHOTO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          // Author header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () async {
                    final authorId = data['authorId'];
                    if (authorId == null) return;
                    try {
                      final user = await FirebaseFirestoreHelper()
                          .getSingleCustomer(customerId: authorId);
                      if (user == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('User not found')),
                        );
                        return;
                      }
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
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error loading profile: $e')),
                      );
                    }
                  },
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF667EEA),
                    child: Text(
                      authorName[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white),
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
                          Text(
                            authorName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
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
                                color: const Color(0xFF667EEA).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                authorRole.toUpperCase(),
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
                      if (createdAt != null)
                        Text(
                          _getTimeAgo(createdAt.toDate()),
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                if (isAdmin)
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
                    onSelected: (value) async {
                      if (value == 'pin' || value == 'unpin') {
                        // Double-check admin status before allowing pin operation
                        final isAdminCheck = await checkIfAdmin();
                        if (!isAdminCheck) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Only admins can pin/unpin content',
                                ),
                              ),
                            );
                          }
                          return;
                        }

                        try {
                          await FirebaseFirestore.instance
                              .collection('Organizations')
                              .doc(organizationId)
                              .collection('Feed')
                              .doc(docId)
                              .update({'isPinned': value == 'pin'});

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  value == 'pin'
                                      ? 'Photo pinned'
                                      : 'Photo unpinned',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
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
                              isPinned
                                  ? Icons.push_pin_outlined
                                  : Icons.push_pin,
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
          ),

          // Images
          if (imageUrls.isNotEmpty) ...[
            if (imageUrls.length == 1)
              AspectRatio(
                aspectRatio: 1,
                child: SafeNetworkImage(
                  imageUrl: imageUrls[0],
                  fit: BoxFit.cover,
                ),
              )
            else if (imageUrls.length == 2)
              Row(
                children: imageUrls
                    .map(
                      (url) => Expanded(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: SafeNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    )
                    .toList(),
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
                  if (index == 8 && imageUrls.length > 9) {
                    return Stack(
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
                    );
                  }
                  return SafeNetworkImage(
                    imageUrl: imageUrls[index],
                    fit: BoxFit.cover,
                  );
                },
              ),
          ],

          // Caption and actions
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (caption.isNotEmpty) ...[
                  Text(caption, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    InkWell(
                      onTap: onLike,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            Icon(
                              isLiked ? Icons.favorite : Icons.favorite_border,
                              color: isLiked
                                  ? Colors.red
                                  : Colors.grey.shade600,
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              likes.length.toString(),
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
                      onTap: () {
                        // TODO: Implement comments
                      },
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
                              '0',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () {
                        // TODO: Implement share
                      },
                      icon: Icon(
                        Icons.share_outlined,
                        color: Colors.grey.shade600,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      return DateFormat.yMMMd().format(dateTime);
    } else if (difference.inDays > 0) {
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

// Enhanced Announcement Card
class _AnnouncementCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final String organizationId;
  final VoidCallback? onLike;
  final bool isAdmin;
  final Future<bool> Function() checkIfAdmin;

  const _AnnouncementCard({
    required this.data,
    required this.docId,
    required this.organizationId,
    this.onLike,
    this.isAdmin = false,
    required this.checkIfAdmin,
  });

  @override
  Widget build(BuildContext context) {
    final isPinned = data['isPinned'] ?? false;
    final title = data['title'] ?? '';
    final content = data['content'] ?? '';
    final authorName = data['authorName'] ?? 'Unknown';
    final createdAt = data['createdAt'] as Timestamp?;
    final likes = List<String>.from(data['likes'] ?? []);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isPinned
            ? Border.all(color: const Color(0xFF667EEA), width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF667EEA),
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.push_pin, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'PINNED ANNOUNCEMENT',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.announcement,
                      color: const Color(0xFF667EEA),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isAdmin)
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert,
                          color: Colors.grey.shade600,
                        ),
                        onSelected: (value) async {
                          if (value == 'pin' || value == 'unpin') {
                            // Double-check admin status before allowing pin operation
                            final isAdminCheck = await checkIfAdmin();
                            if (!isAdminCheck) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Only admins can pin/unpin content',
                                    ),
                                  ),
                                );
                              }
                              return;
                            }

                            try {
                              await FirebaseFirestore.instance
                                  .collection('Organizations')
                                  .doc(organizationId)
                                  .collection('Feed')
                                  .doc(docId)
                                  .update({'isPinned': value == 'pin'});

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      value == 'pin'
                                          ? 'Announcement pinned'
                                          : 'Announcement unpinned',
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e')),
                                );
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
                                  isPinned
                                      ? Icons.push_pin_outlined
                                      : Icons.push_pin,
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
                const SizedBox(height: 12),
                Text(
                  content,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: const Color(0xFF667EEA).withOpacity(0.1),
                      child: Text(
                        authorName.isNotEmpty
                            ? authorName[0].toUpperCase()
                            : 'A',
                        style: const TextStyle(
                          color: Color(0xFF667EEA),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      authorName.isNotEmpty ? authorName : 'Anonymous',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('•', style: TextStyle(color: Colors.grey.shade400)),
                    const SizedBox(width: 8),
                    if (createdAt != null)
                      Text(
                        _getTimeAgo(createdAt.toDate()),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    const Spacer(),
                    InkWell(
                      onTap: onLike,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            Icon(
                              likes.isNotEmpty
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: likes.isNotEmpty
                                  ? Colors.red
                                  : Colors.grey.shade600,
                              size: 18,
                            ),
                            if (likes.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              Text(
                                likes.length.toString(),
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      return DateFormat.yMMMd().format(dateTime);
    } else if (difference.inDays > 0) {
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

// Poll Card (keeping existing implementation)
class _PollCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final String organizationId;
  final Function(int) onVote;
  final String? currentUserId;
  final bool isAdmin;
  final Future<bool> Function() checkIfAdmin;

  const _PollCard({
    required this.data,
    required this.docId,
    required this.organizationId,
    required this.onVote,
    this.currentUserId,
    this.isAdmin = false,
    required this.checkIfAdmin,
  });

  @override
  Widget build(BuildContext context) {
    final isPinned = data['isPinned'] ?? false;
    final question = data['question'] ?? '';
    final options = List<Map<String, dynamic>>.from(data['options'] ?? []);
    final voters = List<String>.from(data['voters'] ?? []);
    final totalVotes = data['totalVotes'] ?? 0;
    final hasVoted = currentUserId != null && voters.contains(currentUserId);
    final authorName = data['authorName'] ?? 'Unknown';
    final createdAt = data['createdAt'] as Timestamp?;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isPinned
            ? Border.all(color: const Color(0xFF667EEA), width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF667EEA),
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.push_pin, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'PINNED POLL',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.poll, color: Color(0xFF667EEA)),
                    const SizedBox(width: 8),
                    const Text(
                      'POLL',
                      style: TextStyle(
                        color: Color(0xFF667EEA),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (createdAt != null)
                      Text(
                        _getTimeAgo(createdAt.toDate()),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    if (isAdmin)
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert,
                          color: Colors.grey.shade600,
                        ),
                        onSelected: (value) async {
                          if (value == 'pin' || value == 'unpin') {
                            // Double-check admin status before allowing pin operation
                            final isAdminCheck = await checkIfAdmin();
                            if (!isAdminCheck) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Only admins can pin/unpin content',
                                    ),
                                  ),
                                );
                              }
                              return;
                            }

                            try {
                              await FirebaseFirestore.instance
                                  .collection('Organizations')
                                  .doc(organizationId)
                                  .collection('Feed')
                                  .doc(docId)
                                  .update({'isPinned': value == 'pin'});

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      value == 'pin'
                                          ? 'Poll pinned'
                                          : 'Poll unpinned',
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e')),
                                );
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
                                  isPinned
                                      ? Icons.push_pin_outlined
                                      : Icons.push_pin,
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
                const SizedBox(height: 12),
                Text(
                  question,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
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
                      onTap: hasVoted ? null : () => onVote(index),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: hasVoted && votes.contains(currentUserId)
                                ? const Color(0xFF667EEA)
                                : Colors.grey.shade300,
                            width: hasVoted && votes.contains(currentUserId)
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
                                    ).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: percentage / 100,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF667EEA,
                                        ).withOpacity(0.2),
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
                }).toList(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      '$totalVotes ${totalVotes == 1 ? 'vote' : 'votes'}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('•', style: TextStyle(color: Colors.grey.shade400)),
                    const SizedBox(width: 8),
                    Text(
                      'by $authorName',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      return DateFormat.yMMMd().format(dateTime);
    } else if (difference.inDays > 0) {
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
