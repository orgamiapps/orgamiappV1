import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:attendus/firebase/organization_helper.dart';
import 'package:attendus/screens/Events/premium_event_creation_wrapper.dart';
import 'package:attendus/screens/Groups/create_announcement_screen.dart';
import 'package:attendus/screens/Groups/create_poll_screen.dart';
import 'package:attendus/screens/Groups/create_photo_post_screen.dart';
import 'package:attendus/screens/Groups/enhanced_feed_tab.dart';
import 'package:attendus/screens/Groups/group_admin_settings_screen.dart';
import 'package:attendus/screens/MyProfile/user_profile_screen.dart';
import 'package:attendus/models/customer_model.dart';

class GroupProfileScreenV2 extends StatefulWidget {
  final String organizationId;
  const GroupProfileScreenV2({super.key, required this.organizationId});

  @override
  State<GroupProfileScreenV2> createState() => _GroupProfileScreenV2State();
}

class _GroupProfileScreenV2State extends State<GroupProfileScreenV2>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final OrganizationHelper _helper = OrganizationHelper();
  bool _isMember = false;
  bool _hasRequestedJoin = false;
  bool _checkingMembership = true;
  String _memberRole = '';
  // Reference to the FAB widget key for direct animation control
  final GlobalKey<_AdminFabState> _fabKey = GlobalKey<_AdminFabState>();
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _checkMembershipStatus();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _handleScrollChange(bool isScrollingDown) {
    // Directly call FAB animation without triggering parent rebuild
    _fabKey.currentState?.updateScrollState(isScrollingDown);
  }

  Future<void> _checkMembershipStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _checkingMembership = false);
      return;
    }

    try {
      // Check if user is the creator
      final orgDoc = await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .get();

      final createdBy = orgDoc.data()?['createdBy'];

      if (createdBy == user.uid) {
        setState(() {
          _isMember = true;
          _memberRole = 'Owner';
          _checkingMembership = false;
        });
        return;
      }

      // Check if user is a member
      final memberDoc = await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Members')
          .doc(user.uid)
          .get();

      if (memberDoc.exists) {
        final role = memberDoc.data()?['role'] ?? 'Member';
        setState(() {
          _isMember = true;
          _memberRole = role == 'admin' ? 'Admin' : 'Member';
          _checkingMembership = false;
        });
        return;
      }

      // Check if user has a pending join request
      final requestDoc = await _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('JoinRequests')
          .doc(user.uid)
          .get();

      setState(() {
        _isMember = false;
        _hasRequestedJoin = requestDoc.exists;
        _checkingMembership = false;
      });
    } catch (e) {
      setState(() => _checkingMembership = false);
    }
  }

  Future<void> _requestToJoin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to join this group')),
      );
      return;
    }

    try {
      await _helper.requestToJoinOrganization(widget.organizationId);
      setState(() {
        _hasRequestedJoin = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Join request sent!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _share() async {
    final doc = await _db
        .collection('Organizations')
        .doc(widget.organizationId)
        .get();
    final data = doc.data();
    final name = (data?['name'] ?? '').toString();
    final description = (data?['description'] ?? '').toString();
    await Share.share('Check out $name on Orgami!\n$description');
  }

  Widget _buildDefaultBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF667EEA), // Primary blue
            Color(0xFF764BA2), // Purple accent
            Color(0xFF8B5FBF), // Deeper purple
          ],
          stops: [0.0, 0.7, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Subtle geometric pattern overlay
          Positioned.fill(
            child: CustomPaint(painter: _GeometricPatternPainter()),
          ),
          // Elegant gradient overlay for depth
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.05),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5, 1.0],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          // Subtle light reflection effect
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 100, // Adjusted to be proportional to header height
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final name = (data?['name'] ?? '').toString();
        final category = (data?['category'] ?? 'Group').toString();
        final bannerUrl = data?['bannerUrl']?.toString();
        final logoUrl = data?['logoUrl']?.toString();

        return Scaffold(
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverAppBar(
                pinned: true,
                floating: true,
                snap: false,
                expandedHeight: 260,
                elevation: 0,
                surfaceTintColor: Colors.transparent,
                backgroundColor: const Color(0xFF667EEA),
                leading: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(
                      Icons.ios_share_rounded,
                      color: Colors.white,
                    ),
                    onPressed: _share,
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.pin,
                  background: Stack(
                    children: [
                      // Default banner or custom banner
                      Container(
                        decoration: BoxDecoration(
                          image: bannerUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(bannerUrl),
                                  fit: BoxFit.cover,
                                  colorFilter: ColorFilter.mode(
                                    Colors.black.withValues(alpha: 0.3),
                                    BlendMode.darken,
                                  ),
                                )
                              : null,
                        ),
                        child: bannerUrl == null
                            ? _buildDefaultBanner(context)
                            : null,
                      ),
                      // Gradient overlay for better text visibility
                      Positioned(
                        bottom: 48, // Start from tab bar height
                        left: 0,
                        right: 0,
                        height:
                            140, // Compact gradient coverage while maintaining readability
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.2),
                                Colors.black.withValues(alpha: 0.4),
                              ],
                              stops: const [0.0, 0.6, 1.0],
                            ),
                          ),
                        ),
                      ),
                      // Group info overlay
                      Positioned(
                        bottom: 96, // Added cushion below group profile info
                        left: 0,
                        right: 0,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                radius:
                                    22, // Slightly reduced to avoid clipping
                                backgroundColor: Colors.white,
                                backgroundImage: logoUrl != null
                                    ? NetworkImage(logoUrl)
                                    : null,
                                child: logoUrl == null
                                    ? const Icon(
                                        Icons.apartment,
                                        size: 20, // Proportionally reduced
                                        color: Color(0xFF667EEA),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12), // Reduced from 16
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name.isEmpty ? 'Group' : name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18, // Further reduced
                                        fontWeight: FontWeight.w700,
                                        shadows: [
                                          Shadow(
                                            offset: Offset(0, 1),
                                            blurRadius: 3,
                                            color: Colors.black26,
                                          ),
                                        ],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(
                                      height: 1,
                                    ), // Minimal spacing
                                    Text(
                                      category,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12, // Further reduced
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!_isMember && !_checkingMembership) ...[
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: _hasRequestedJoin
                                      ? null
                                      : _requestToJoin,
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 6,
                                    ),
                                    backgroundColor: _hasRequestedJoin
                                        ? Colors.grey.shade400
                                        : Colors.white,
                                    foregroundColor: _hasRequestedJoin
                                        ? Colors.white
                                        : const Color(0xFF667EEA),
                                    disabledBackgroundColor:
                                        Colors.grey.shade400,
                                    disabledForegroundColor: Colors.white,
                                  ),
                                  child: Text(
                                    _hasRequestedJoin ? 'Requested' : 'Join',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ] else if (_isMember && !_checkingMembership) ...[
                                const SizedBox(width: 8), // Reduced from 12
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8, // Further reduced
                                    vertical: 3, // Further reduced
                                  ),
                                  decoration: BoxDecoration(
                                    gradient:
                                        _memberRole == 'Owner' ||
                                            _memberRole == 'Admin'
                                        ? LinearGradient(
                                            colors: [
                                              Colors.amber.shade400,
                                              Colors.orange.shade400,
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          )
                                        : null,
                                    color:
                                        _memberRole == 'Owner' ||
                                            _memberRole == 'Admin'
                                        ? null
                                        : Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.3,
                                      ),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _memberRole == 'Owner'
                                            ? Icons.star
                                            : _memberRole == 'Admin'
                                            ? Icons.shield
                                            : Icons.check_circle,
                                        size: 12, // Further reduced
                                        color: Colors.white,
                                      ),
                                      const SizedBox(
                                        width: 3,
                                      ), // Reduced spacing
                                      Text(
                                        _memberRole.isEmpty
                                            ? 'Member'
                                            : _memberRole,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11, // Further reduced
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(60),
                  child: Container(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: false,
                        tabAlignment: TabAlignment.fill,
                        labelColor: const Color(0xFF667EEA),
                        unselectedLabelColor: Colors.black54,
                        indicatorColor: const Color(0xFF667EEA),
                        indicatorWeight: 3,
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                        ),
                        labelPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        tabs: const [
                          Tab(text: 'Feed'),
                          Tab(text: 'Members'),
                          Tab(text: 'About'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabController,
              children: [
                EnhancedFeedTab(
                  organizationId: widget.organizationId,
                  onScrollChange: _handleScrollChange,
                ),
                _MembersTab(organizationId: widget.organizationId),
                _AboutTab(organizationId: widget.organizationId),
              ],
            ),
          ),
          floatingActionButton: _AdminFab(
            key: _fabKey,
            organizationId: widget.organizationId,
          ),
        );
      },
    );
  }
}

class _FeedTab extends StatefulWidget {
  final String organizationId;
  const _FeedTab({required this.organizationId});

  @override
  State<_FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<_FeedTab> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final User? _currentUser = FirebaseAuth.instance.currentUser;

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

        // Check if user already voted
        if (!allowMultiple && voters.contains(_currentUser.uid)) {
          throw Exception('You have already voted in this poll');
        }

        // Add vote
        final votes = List<String>.from(options[optionIndex]['votes'] ?? []);
        if (!votes.contains(_currentUser.uid)) {
          votes.add(_currentUser.uid);
          options[optionIndex]['votes'] = votes;
          options[optionIndex]['voteCount'] = votes.length;
        }

        // Add to voters list
        if (!voters.contains(_currentUser.uid)) {
          voters.add(_currentUser.uid);
        }

        // Update document
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
        ).showSnackBar(SnackBar(content: Text('Error voting: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Feed')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        // Handle errors
        if (snapshot.hasError) {
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
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    snapshot.error.toString().contains('index')
                        ? 'Setting up feed...'
                        : 'Please try again later',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                  ),
                  if (snapshot.error.toString().contains('index'))
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {});
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF667EEA),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }

        // Loading state with shimmer effect
        if (snapshot.connectionState == ConnectionState.waiting) {
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: 3,
            itemBuilder: (context, index) => _buildShimmerCard(),
          );
        }

        // Empty state
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
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

        // Sort docs to put pinned items first
        final docs = snapshot.data!.docs;
        docs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aPinned = aData['isPinned'] ?? false;
          final bPinned = bData['isPinned'] ?? false;

          if (aPinned && !bPinned) return -1;
          if (!aPinned && bPinned) return 1;

          // Then sort by creation time
          final aTime = aData['createdAt'] as Timestamp?;
          final bTime = bData['createdAt'] as Timestamp?;
          if (aTime == null || bTime == null) return 0;
          return bTime.compareTo(aTime);
        });

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
            await Future.delayed(const Duration(seconds: 1));
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final type = data['type'] ?? 'announcement';

              if (type == 'poll') {
                return _PollCard(
                  data: data,
                  docId: doc.id,
                  organizationId: widget.organizationId,
                  onVote: (optionIndex) => _votePoll(doc.id, optionIndex),
                  currentUserId: _currentUser?.uid,
                );
              } else {
                return _AnnouncementCard(
                  data: data,
                  docId: doc.id,
                  organizationId: widget.organizationId,
                );
              }
            },
          ),
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
            color: Colors.black.withValues(alpha: 0.05),
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
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final bottomInset = MediaQuery.of(context).padding.bottom;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(top: 20, bottom: 20 + bottomInset + 24),
            child: SingleChildScrollView(
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
                  // Photo sharing available to all members
                  ListTile(
                    leading: const Icon(
                      Icons.photo_camera,
                      color: Color(0xFF667EEA),
                    ),
                    title: const Text('Share Photo'),
                    subtitle: const Text('Post photos to share with the group'),
                    onTap: () async {
                      Navigator.pop(context);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CreatePhotoPostScreen(
                            organizationId: widget.organizationId,
                          ),
                        ),
                      );
                      // Reopen modal after returning
                      if (context.mounted) {
                        _showCreateOptions(context);
                      }
                    },
                  ),
                  // Admin options are handled in the FAB modal
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AnnouncementCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String docId;
  final String organizationId;

  const _AnnouncementCard({
    required this.data,
    required this.docId,
    required this.organizationId,
  });

  @override
  State<_AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends State<_AnnouncementCard> {
  bool _isAdmin = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
  }

  Future<void> _checkAdminStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Check if user is admin or creator
      final orgDoc = await FirebaseFirestore.instance
          .collection('Organizations')
          .doc(widget.organizationId)
          .get();

      final createdBy = orgDoc.data()?['createdBy'];

      // Check if user is creator
      if (createdBy == user.uid) {
        setState(() {
          _isAdmin = true;
          _isLoading = false;
        });
        return;
      }

      // Check if user is admin in Members collection
      final memberDoc = await FirebaseFirestore.instance
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Members')
          .doc(user.uid)
          .get();

      if (memberDoc.exists) {
        final role = memberDoc.data()?['role'];
        setState(() {
          _isAdmin = role == 'admin' || role == 'owner';
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _handleAdminAction(String action) {
    switch (action) {
      case 'pin':
        _togglePin();
        break;
      case 'delete':
        _showDeleteDialog();
        break;
    }
  }

  Future<void> _togglePin() async {
    try {
      final isPinned = widget.data['isPinned'] ?? false;
      await FirebaseFirestore.instance
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Feed')
          .doc(widget.docId)
          .update({'isPinned': !isPinned});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isPinned ? 'Announcement unpinned' : 'Announcement pinned',
            ),
            backgroundColor: const Color(0xFF667EEA),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Announcement'),
        content: const Text(
          'Are you sure you want to delete this announcement? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePost();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePost() async {
    try {
      await FirebaseFirestore.instance
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Feed')
          .doc(widget.docId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Announcement deleted'),
            backgroundColor: Color(0xFF667EEA),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting announcement: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Just now';
        }
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPinned = widget.data['isPinned'] ?? false;
    final createdAt = widget.data['createdAt'] as Timestamp?;
    final dateStr = _formatDate(createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPinned)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.push_pin_rounded, size: 18, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    'PINNED ANNOUNCEMENT',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.campaign_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.data['title'] ?? 'Announcement',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1A1A),
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.person_outline,
                                size: 14,
                                color: Colors.grey.shade500,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.data['authorName'] ?? 'Admin',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (dateStr.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '• $dateStr',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_isAdmin && !_isLoading) ...[
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 20),
                        onSelected: (value) => _handleAdminAction(value),
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
                                Text(isPinned ? 'Unpin' : 'Pin'),
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
                                  'Delete',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  widget.data['content'] ?? '',
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF3A3A3A),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PollCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String docId;
  final String organizationId;
  final Function(int) onVote;
  final String? currentUserId;

  const _PollCard({
    required this.data,
    required this.docId,
    required this.organizationId,
    required this.onVote,
    this.currentUserId,
  });

  @override
  State<_PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<_PollCard> {
  bool _isAdmin = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
  }

  Future<void> _checkAdminStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Check if user is admin or creator
      final orgDoc = await FirebaseFirestore.instance
          .collection('Organizations')
          .doc(widget.organizationId)
          .get();

      final createdBy = orgDoc.data()?['createdBy'];

      // Check if user is creator
      if (createdBy == user.uid) {
        setState(() {
          _isAdmin = true;
          _isLoading = false;
        });
        return;
      }

      // Check if user is admin in Members collection
      final memberDoc = await FirebaseFirestore.instance
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Members')
          .doc(user.uid)
          .get();

      if (memberDoc.exists) {
        final role = memberDoc.data()?['role'];
        setState(() {
          _isAdmin = role == 'admin' || role == 'owner';
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  bool get hasVoted {
    final voters = List<String>.from(widget.data['voters'] ?? []);
    return widget.currentUserId != null &&
        voters.contains(widget.currentUserId);
  }

  void _handleAdminAction(String action) {
    switch (action) {
      case 'delete':
        _showDeleteDialog();
        break;
    }
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Poll'),
        content: const Text(
          'Are you sure you want to delete this poll? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePoll();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePoll() async {
    try {
      await FirebaseFirestore.instance
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Feed')
          .doc(widget.docId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Poll deleted'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting poll: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = List<Map<String, dynamic>>.from(
      widget.data['options'] ?? [],
    );
    final totalVotes = widget.data['totalVotes'] ?? 0;
    final createdAt = widget.data['createdAt'] as Timestamp?;
    final dateStr = createdAt != null
        ? '${createdAt.toDate().day}/${createdAt.toDate().month}/${createdAt.toDate().year}'
        : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: Color(0xFF764BA2),
                  child: Icon(Icons.poll, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Poll',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF764BA2),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'by ${widget.data['authorName'] ?? 'Admin'} • $dateStr',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (totalVotes > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$totalVotes ${totalVotes == 1 ? 'vote' : 'votes'}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                if (_isAdmin && !_isLoading) ...[
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (value) => _handleAdminAction(value),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red),
                            SizedBox(width: 12),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Text(
              widget.data['question'] ?? 'Poll Question',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            ...options.asMap().entries.map((entry) {
              final index = entry.key;
              final option = entry.value;
              final votes = List<String>.from(option['votes'] ?? []);
              final voteCount = votes.length;
              final percentage = totalVotes > 0
                  ? (voteCount / totalVotes * 100)
                  : 0.0;
              final userVoted =
                  widget.currentUserId != null &&
                  votes.contains(widget.currentUserId);

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: hasVoted ? null : () => widget.onVote(index),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: userVoted
                            ? const Color(0xFF667EEA)
                            : Colors.grey.shade300,
                        width: userVoted ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Stack(
                      children: [
                        if (hasVoted)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(11),
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(
                                      0xFF667EEA,
                                    ).withValues(alpha: 0.1),
                                    const Color(
                                      0xFF667EEA,
                                    ).withValues(alpha: 0.05),
                                  ],
                                  stops: [percentage / 100, percentage / 100],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              if (userVoted)
                                const Icon(
                                  Icons.check_circle,
                                  size: 20,
                                  color: Color(0xFF667EEA),
                                )
                              else if (!hasVoted)
                                Icon(
                                  Icons.radio_button_unchecked,
                                  size: 20,
                                  color: Colors.grey.shade400,
                                ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  option['text'] ?? '',
                                  style: TextStyle(
                                    fontWeight: userVoted
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (hasVoted)
                                Text(
                                  '${percentage.toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _MembersTab extends StatefulWidget {
  final String organizationId;
  const _MembersTab({required this.organizationId});

  @override
  State<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<_MembersTab> {
  final Map<String, Map<String, dynamic>> _userCache = {};

  Future<Map<String, dynamic>?> _getUserData(String userId) async {
    if (_userCache.containsKey(userId)) {
      return _userCache[userId];
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('Customers')
          .doc(userId)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data()!;
        _userCache[userId] = userData;
        return userData;
      }
    } catch (e) {
      // If user data not found, create a fallback
      final fallbackData = {
        'name': 'Unknown User',
        'email': '',
        'profileImageUrl': null,
      };
      _userCache[userId] = fallbackData;
      return fallbackData;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final membersQuery = FirebaseFirestore.instance
        .collection('Organizations')
        .doc(widget.organizationId)
        .collection('Members');

    return StreamBuilder<QuerySnapshot>(
      stream: membersQuery.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const _EmptyState(
            icon: Icons.people_outline,
            title: 'No Members Yet',
            subtitle: 'Invite people to grow your community.',
          );
        }

        // Sort members: owner/admin first, then by joinedAt (most recent first)
        final sortedDocs = List.from(docs);
        sortedDocs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aRole = (aData['role'] ?? 'Member').toString().toLowerCase();
          final bRole = (bData['role'] ?? 'Member').toString().toLowerCase();

          // Owner comes first
          if (aRole == 'owner' && bRole != 'owner') return -1;
          if (bRole == 'owner' && aRole != 'owner') return 1;

          // Admin comes second
          if (aRole == 'admin' && bRole != 'admin' && bRole != 'owner') {
            return -1;
          }
          if (bRole == 'admin' && aRole != 'admin' && aRole != 'owner') {
            return 1;
          }

          // Sort by joinedAt (most recent first)
          final aJoined = aData['joinedAt'] as Timestamp?;
          final bJoined = bData['joinedAt'] as Timestamp?;
          if (aJoined == null || bJoined == null) return 0;
          return bJoined.compareTo(aJoined);
        });

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sortedDocs.length,
          itemBuilder: (context, i) {
            final memberData = sortedDocs[i].data() as Map<String, dynamic>;
            final userId = memberData['userId'] ?? sortedDocs[i].id;
            final role = (memberData['role'] ?? 'Member').toString();
            final joinedAt = memberData['joinedAt'] as Timestamp?;

            return FutureBuilder<Map<String, dynamic>?>(
              future: _getUserData(userId),
              builder: (context, userSnapshot) {
                final userData = userSnapshot.data;
                final userName =
                    userData?['name'] ??
                    userData?['displayName'] ??
                    'Loading...';
                final profileImageUrl = userData?['profileImageUrl'];

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFF667EEA),
                      backgroundImage: profileImageUrl != null
                          ? NetworkImage(profileImageUrl)
                          : null,
                      child: profileImageUrl == null
                          ? Text(
                              userName.isNotEmpty
                                  ? userName[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : null,
                    ),
                    title: Text(
                      userName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    subtitle: joinedAt != null
                        ? Text(
                            'Joined ${_formatJoinDate(joinedAt)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          )
                        : null,
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        gradient: role == 'admin' || role == 'owner'
                            ? LinearGradient(
                                colors: [
                                  Colors.amber.shade400,
                                  Colors.orange.shade400,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: role == 'admin' || role == 'owner'
                            ? null
                            : const Color(0xFF667EEA).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            role == 'owner'
                                ? Icons.star
                                : role == 'admin'
                                ? Icons.shield
                                : Icons.person,
                            size: 14,
                            color: role == 'admin' || role == 'owner'
                                ? Colors.white
                                : const Color(0xFF667EEA),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            role == 'admin'
                                ? 'Admin'
                                : role == 'owner'
                                ? 'Owner'
                                : 'Member',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: role == 'admin' || role == 'owner'
                                  ? Colors.white
                                  : const Color(0xFF667EEA),
                            ),
                          ),
                        ],
                      ),
                    ),
                    onTap: userSnapshot.hasData && userData != null
                        ? () {
                            _navigateToUserProfile(context, userId, userData);
                          }
                        : null,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _navigateToUserProfile(
    BuildContext context,
    String userId,
    Map<String, dynamic> userData,
  ) {
    try {
      // Create CustomerModel from userData
      final customerModel = CustomerModel(
        uid: userId,
        name: userData['name'] ?? userData['displayName'] ?? 'Unknown User',
        email: userData['email'] ?? '',
        username: userData['username'],
        profilePictureUrl:
            userData['profileImageUrl'] ?? userData['profilePictureUrl'],
        bannerUrl: userData['bannerUrl'],
        bio: userData['bio'] ?? '',
        phoneNumber: userData['phoneNumber'],
        age: userData['age'],
        gender: userData['gender'],
        location: userData['location'],
        occupation: userData['occupation'],
        company: userData['company'],
        website: userData['website'],
        socialMediaLinks: userData['socialMediaLinks'],
        isDiscoverable: userData['isDiscoverable'] ?? true,
        favorites: List<String>.from(userData['favorites'] ?? []),
        createdAt:
            (userData['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              UserProfileScreen(user: customerModel, isOwnProfile: false),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to view profile: $e')));
    }
  }

  String _formatJoinDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'today';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else if (difference.inDays < 30) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months month${months > 1 ? 's' : ''} ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return '$years year${years > 1 ? 's' : ''} ago';
    }
  }
}

class _AboutTab extends StatelessWidget {
  final String organizationId;
  const _AboutTab({required this.organizationId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        FirebaseFirestore.instance
            .collection('Organizations')
            .doc(organizationId)
            .get(),
        FirebaseFirestore.instance
            .collection('Organizations')
            .doc(organizationId)
            .collection('Members')
            .where('status', isEqualTo: 'approved')
            .get(),
        FirebaseFirestore.instance
            .collection('Events')
            .where('organizationId', isEqualTo: organizationId)
            .get(),
        _getAttendanceDataForOrganization(organizationId),
        _getUpcomingEvents(organizationId),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(
                color: Color(0xFF667EEA),
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(
            child: Text(
              'Unable to load group information',
              style: TextStyle(fontSize: 16),
            ),
          );
        }

        final orgSnapshot = snapshot.data![0] as DocumentSnapshot;
        final membersSnapshot = snapshot.data![1] as QuerySnapshot;
        final eventsSnapshot = snapshot.data![2] as QuerySnapshot;
        final totalAttendees = snapshot.data![3] as int;
        final upcomingEvents = snapshot.data![4] as List<Map<String, dynamic>>;

        final data = orgSnapshot.data() as Map<String, dynamic>?;
        final description = (data?['description'] ?? '').toString();
        final category = (data?['category'] ?? 'Group').toString();
        final website = (data?['website'] ?? '').toString();
        final locationAddress = (data?['locationAddress'] ?? '').toString();
        final createdAt = (data?['createdAt'] as Timestamp?)?.toDate();
        final createdBy = (data?['createdBy'] ?? '').toString();
        final defaultEventVisibility =
            (data?['defaultEventVisibility'] ?? 'public').toString();

        final memberCount = membersSnapshot.docs.length;
        final eventCount = eventsSnapshot.docs.length;
        final activeEvents = eventsSnapshot.docs.where((doc) {
          final eventData = doc.data() as Map<String, dynamic>;
          final endDateTime = (eventData['endDateTime'] as Timestamp?)
              ?.toDate();
          return endDateTime?.isAfter(DateTime.now()) ?? false;
        }).length;

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // Hero Stats Card - Eye-catching overview
            _buildHeroStatsCard(
              context,
              memberCount,
              eventCount,
              activeEvents,
              totalAttendees,
            ),

            const SizedBox(height: 24),

            // Description Section
            if (description.isNotEmpty) ...[
              _buildDescriptionCard(context, description, category),
              const SizedBox(height: 20),
            ],

            // Key Information Grid
            _buildKeyInfoGrid(
              context,
              category,
              defaultEventVisibility,
              createdAt,
              locationAddress,
            ),

            const SizedBox(height: 20),

            // Upcoming Events Section
            if (upcomingEvents.isNotEmpty) ...[
              _buildUpcomingEventsSection(context, upcomingEvents),
              const SizedBox(height: 20),
            ],

            // Quick Actions Section
            _buildQuickActionsSection(
              context,
              website,
              locationAddress,
              organizationId,
            ),

            const SizedBox(height: 20),

            // Admin Information Section
            _buildAdminSection(context, createdBy),

            const SizedBox(height: 32),
          ],
        );
      },
    );
  }

  Future<int> _getAttendanceDataForOrganization(String organizationId) async {
    try {
      // First get all events for this organization
      final eventsSnapshot = await FirebaseFirestore.instance
          .collection('Events')
          .where('organizationId', isEqualTo: organizationId)
          .get();

      if (eventsSnapshot.docs.isEmpty) {
        return 0;
      }

      // Get all event IDs
      final eventIds = eventsSnapshot.docs.map((doc) => doc.id).toList();

      // Get all attendance records for these events
      final Set<String> uniqueAttendees = {};

      // Process events in batches to avoid Firestore limits
      const batchSize = 10;
      for (int i = 0; i < eventIds.length; i += batchSize) {
        final batch = eventIds.skip(i).take(batchSize).toList();

        final attendanceSnapshot = await FirebaseFirestore.instance
            .collection('Attendance')
            .where('eventId', whereIn: batch)
            .get();

        // Add unique customer UIDs (excluding anonymous and without_login users)
        for (var doc in attendanceSnapshot.docs) {
          final data = doc.data();
          final customerUid = data['customerUid']?.toString();
          final isAnonymous = data['isAnonymous'] ?? false;

          if (customerUid != null &&
              customerUid != 'without_login' &&
              !isAnonymous &&
              customerUid.isNotEmpty) {
            uniqueAttendees.add(customerUid);
          }
        }
      }

      return uniqueAttendees.length;
    } catch (e) {
      debugPrint('Error getting attendance data: $e');
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> _getUpcomingEvents(
    String organizationId,
  ) async {
    try {
      final now = DateTime.now();
      final eventsSnapshot = await FirebaseFirestore.instance
          .collection('Events')
          .where('organizationId', isEqualTo: organizationId)
          .where('startDateTime', isGreaterThan: Timestamp.fromDate(now))
          .orderBy('startDateTime')
          .limit(3)
          .get();

      return eventsSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? '',
          'startDateTime': data['startDateTime'] as Timestamp?,
          'imageUrl': data['imageUrl'] ?? data['eventImageUrl'],
        };
      }).toList();
    } catch (e) {
      debugPrint('Error getting upcoming events: $e');
      return [];
    }
  }

  // New refined UI components

  Widget _buildHeroStatsCard(
    BuildContext context,
    int memberCount,
    int eventCount,
    int activeEvents,
    int totalAttendees,
  ) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667EEA).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.insights,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Group Insights',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildHeroStatItem(
                    'Members',
                    memberCount.toString(),
                    Icons.people,
                  ),
                ),
                Container(
                  width: 1,
                  height: 50,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                Expanded(
                  child: _buildHeroStatItem(
                    'Events',
                    eventCount.toString(),
                    Icons.event,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildHeroStatItem(
                    'Active',
                    activeEvents.toString(),
                    Icons.event_available,
                  ),
                ),
                Container(
                  width: 1,
                  height: 50,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                Expanded(
                  child: _buildHeroStatItem(
                    'Attendees',
                    totalAttendees.toString(),
                    Icons.people_alt,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 28),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildDescriptionCard(
    BuildContext context,
    String description,
    String category,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getCategoryIcon(category),
                        size: 16,
                        color: const Color(0xFF667EEA),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        category,
                        style: TextStyle(
                          color: const Color(0xFF667EEA),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'About this group',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _ExpandableText(
              text: description,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.6,
                color: theme.textTheme.bodyMedium?.color?.withValues(
                  alpha: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyInfoGrid(
    BuildContext context,
    String category,
    String visibility,
    DateTime? createdAt,
    String locationAddress,
  ) {
    final theme = Theme.of(context);

    final items = <Widget>[
      _buildInfoGridItem(
        context,
        'Event Privacy',
        visibility == 'public' ? 'Public Events' : 'Private Events',
        visibility == 'public'
            ? Icons.public
            : Icons.lock_outline,
        const Color(0xFF667EEA),
        subtitle: visibility == 'public'
            ? 'Open to everyone'
            : 'Members only',
      ),
      if (createdAt != null)
        _buildInfoGridItem(
          context,
          'Established',
          _formatDate(createdAt),
          Icons.calendar_today_outlined,
          const Color(0xFF764BA2),
          subtitle: _getTimeAgo(createdAt).replaceFirst('Created ', ''),
        ),
      if (locationAddress.isNotEmpty)
        _buildInfoGridItem(
          context,
          'Location',
          _getShortLocation(locationAddress),
          Icons.location_on_outlined,
          const Color(0xFF4CAF50),
          subtitle: 'Tap to view on map',
          onTap: () async {
            final encodedAddress = Uri.encodeComponent(locationAddress);
            final uri = Uri.parse(
              'https://maps.google.com/?q=$encodedAddress',
            );
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Key Information',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: item,
        )),
      ],
    );
  }

  Widget _buildInfoGridItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color, {
    String? subtitle,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[850] : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withValues(
                            alpha: 0.6,
                          ),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: theme.textTheme.bodySmall?.color?.withValues(
                      alpha: 0.4,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUpcomingEventsSection(
    BuildContext context,
    List<Map<String, dynamic>> events,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Row(
            children: [
              Icon(
                Icons.event_available,
                size: 20,
                color: const Color(0xFF667EEA),
              ),
              const SizedBox(width: 8),
              Text(
                'Upcoming Events',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        ...events.take(3).map((event) {
          final startDateTime = event['startDateTime'] as Timestamp?;
          final date = startDateTime?.toDate();

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[850] : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: date != null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              date.day.toString(),
                              style: const TextStyle(
                                color: Color(0xFF667EEA),
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _getMonthAbbr(date.month),
                              style: TextStyle(
                                color: const Color(0xFF667EEA).withValues(
                                  alpha: 0.7,
                                ),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      : const Icon(
                          Icons.event,
                          color: Color(0xFF667EEA),
                          size: 28,
                        ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event['name'] ?? 'Unnamed Event',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (date != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _formatEventDateTime(date),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.textTheme.bodySmall?.color
                                  ?.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: theme.textTheme.bodySmall?.color?.withValues(
                      alpha: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildQuickActionsSection(
    BuildContext context,
    String website,
    String locationAddress,
    String organizationId,
  ) {
    final theme = Theme.of(context);

    final actions = <Widget>[];

    if (website.isNotEmpty) {
      actions.add(
        _buildQuickActionButton(
          context,
          'Visit Website',
          Icons.language,
          const Color(0xFF667EEA),
          () async {
            final uri = Uri.tryParse(website);
            if (uri != null && await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
        ),
      );
    }

    if (locationAddress.isNotEmpty) {
      actions.add(
        _buildQuickActionButton(
          context,
          'View on Map',
          Icons.map_outlined,
          const Color(0xFF4CAF50),
          () async {
            final encodedAddress = Uri.encodeComponent(locationAddress);
            final uri = Uri.parse(
              'https://maps.google.com/?q=$encodedAddress',
            );
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
        ),
      );
    }

    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Quick Actions',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: actions,
        ),
      ],
    );
  }

  Widget _buildQuickActionButton(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdminSection(BuildContext context, String createdBy) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Row(
            children: [
              Icon(
                Icons.admin_panel_settings_outlined,
                size: 20,
                color: const Color(0xFF667EEA),
              ),
              const SizedBox(width: 8),
              Text(
                'Group Admin',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('Customers')
              .doc(createdBy)
              .get(),
          builder: (context, snapshot) {
            final adminData = snapshot.hasData && snapshot.data!.exists
                ? snapshot.data!.data() as Map<String, dynamic>
                : null;

            final adminName = adminData?['name'] ?? 'Group Admin';
            final adminProfileUrl = adminData?['profileImageUrl'] ??
                adminData?['profilePictureUrl'];

            return Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                        ),
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF667EEA).withValues(
                              alpha: 0.3,
                            ),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: adminProfileUrl != null
                          ? ClipOval(
                              child: Image.network(
                                adminProfileUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(
                                    Icons.person,
                                    color: Colors.white,
                                    size: 28,
                                  );
                                },
                              ),
                            )
                          : const Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 28,
                            ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            adminName,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF667EEA).withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.workspace_premium,
                                  size: 14,
                                  color: const Color(0xFF667EEA),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Owner',
                                  style: TextStyle(
                                    color: const Color(0xFF667EEA),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // Helper methods

  IconData _getCategoryIcon(String category) {
    final categoryLower = category.toLowerCase();
    if (categoryLower.contains('sport')) return Icons.sports_soccer;
    if (categoryLower.contains('music')) return Icons.music_note;
    if (categoryLower.contains('art')) return Icons.palette;
    if (categoryLower.contains('tech')) return Icons.computer;
    if (categoryLower.contains('food')) return Icons.restaurant;
    if (categoryLower.contains('education')) return Icons.school;
    if (categoryLower.contains('business')) return Icons.business_center;
    if (categoryLower.contains('social')) return Icons.people;
    return Icons.category;
  }

  String _getShortLocation(String address) {
    final parts = address.split(',');
    if (parts.length > 2) {
      return '${parts[0].trim()}, ${parts[1].trim()}';
    }
    return parts.isNotEmpty ? parts[0].trim() : address;
  }

  String _getMonthAbbr(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }

  String _formatEventDateTime(DateTime date) {
    final now = DateTime.now();
    final difference = date.difference(now);

    if (difference.inDays == 0) {
      return 'Today at ${_formatTime(date)}';
    } else if (difference.inDays == 1) {
      return 'Tomorrow at ${_formatTime(date)}';
    } else if (difference.inDays < 7) {
      return '${_getDayName(date.weekday)} at ${_formatTime(date)}';
    } else {
      return '${_getMonthAbbr(date.month)} ${date.day} at ${_formatTime(date)}';
    }
  }

  String _formatTime(DateTime date) {
    final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _getDayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _getTimeAgo(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays < 1) {
      return 'Created today';
    } else if (difference.inDays == 1) {
      return 'Created yesterday';
    } else if (difference.inDays < 30) {
      return 'Created ${difference.inDays} days ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return 'Created $months month${months > 1 ? 's' : ''} ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return 'Created $years year${years > 1 ? 's' : ''} ago';
    }
  }
}

class _ExpandableText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const _ExpandableText({required this.text, this.style});

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          style: widget.style,
          maxLines: _isExpanded ? null : 3,
          overflow: _isExpanded ? null : TextOverflow.ellipsis,
        ),
        if (widget.text.length > 100)
          GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _isExpanded ? 'Show less' : 'Show more',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF667EEA),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AdminFab extends StatefulWidget {
  final String organizationId;
  const _AdminFab({super.key, required this.organizationId});

  @override
  State<_AdminFab> createState() => _AdminFabState();
}

class _AdminFabState extends State<_AdminFab> with TickerProviderStateMixin {
  bool _isAdmin = false;
  bool _isMember = false;
  bool _isLoading = true;
  bool _isScrollingDown = false; // Track internal scroll state

  // Animation controllers
  late AnimationController _fabOpacityController;
  late Animation<double> _fabOpacityAnimation;

  @override
  void initState() {
    super.initState();
    _checkMembershipStatus();

    // Initialize FAB opacity animation
    _fabOpacityController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: 1.0,
    );
    _fabOpacityAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _fabOpacityController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _fabOpacityController.dispose();
    super.dispose();
  }

  // Method to update scroll state and trigger animation directly
  void updateScrollState(bool isScrollingDown) {
    if (_isScrollingDown != isScrollingDown && mounted) {
      _isScrollingDown = isScrollingDown;

      try {
        if (_isScrollingDown) {
          _fabOpacityController.reverse(); // Fade out
        } else {
          _fabOpacityController.forward(); // Fade in
        }
      } catch (e) {
        // Silently handle any animation controller errors
        debugPrint('FAB animation error: $e');
      }
    }
  }

  Future<void> _checkMembershipStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Check if user is admin or creator
      final orgDoc = await FirebaseFirestore.instance
          .collection('Organizations')
          .doc(widget.organizationId)
          .get();

      final createdBy = orgDoc.data()?['createdBy'];

      // Check if user is creator
      if (createdBy == user.uid) {
        setState(() {
          _isAdmin = true;
          _isMember = true;
          _isLoading = false;
        });
        return;
      }

      // Check if user is a member
      final memberDoc = await FirebaseFirestore.instance
          .collection('Organizations')
          .doc(widget.organizationId)
          .collection('Members')
          .doc(user.uid)
          .get();

      if (memberDoc.exists) {
        final role = memberDoc.data()?['role'];
        setState(() {
          _isAdmin = role == 'admin' || role == 'owner';
          _isMember = true;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _showCreateOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final bottomInset = MediaQuery.of(context).padding.bottom;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(top: 20, bottom: 20 + bottomInset + 24),
            child: SingleChildScrollView(
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
                  // Photo sharing available to all members
                  ListTile(
                    leading: const Icon(
                      Icons.photo_camera,
                      color: Color(0xFF667EEA),
                    ),
                    title: const Text('Share Photo'),
                    subtitle: const Text('Post photos to share with the group'),
                    onTap: () async {
                      Navigator.pop(context);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CreatePhotoPostScreen(
                            organizationId: widget.organizationId,
                          ),
                        ),
                      );
                      // Reopen modal after returning
                      if (context.mounted) {
                        _showCreateOptions(context);
                      }
                    },
                  ),
                  // Admin-only options
                  if (_isAdmin) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.event,
                        color: Color(0xFF667EEA),
                      ),
                      title: const Text('Create Event'),
                      subtitle: const Text(
                        'Schedule a new event for this group',
                      ),
                      onTap: () async {
                        Navigator.pop(context);
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PremiumEventCreationWrapper(
                              preselectedOrganizationId: widget.organizationId,
                              forceOrganizationEvent: true,
                            ),
                          ),
                        );
                        // Reopen modal after returning
                        if (context.mounted) {
                          _showCreateOptions(context);
                        }
                      },
                    ),
                    ListTile(
                      leading: const Icon(
                        Icons.announcement,
                        color: Color(0xFF667EEA),
                      ),
                      title: const Text('Post Announcement'),
                      subtitle: const Text(
                        'Share important updates with members',
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
                        if (result == true && context.mounted) {
                          // Feed will auto-refresh via stream
                        }
                        // Reopen modal after returning
                        if (context.mounted) {
                          _showCreateOptions(context);
                        }
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.poll, color: Color(0xFF667EEA)),
                      title: const Text('Create Poll'),
                      subtitle: const Text('Get feedback from group members'),
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
                        if (result == true && context.mounted) {
                          // Feed will auto-refresh via stream
                        }
                        // Reopen modal after returning
                        if (context.mounted) {
                          _showCreateOptions(context);
                        }
                      },
                    ),
                    const Divider(height: 32),
                    ListTile(
                      leading: const Icon(
                        Icons.admin_panel_settings,
                        color: Color(0xFF667EEA),
                      ),
                      title: const Text('Admin Settings'),
                      subtitle: const Text('Manage group settings and content'),
                      onTap: () async {
                        Navigator.pop(context);
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GroupAdminSettingsScreen(
                              organizationId: widget.organizationId,
                            ),
                          ),
                        );
                        // Reopen modal after returning
                        if (context.mounted) {
                          _showCreateOptions(context);
                        }
                      },
                    ),
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox.shrink();
    }

    if (!_isMember) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _fabOpacityAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _fabOpacityAnimation.value,
          child: FloatingActionButton.extended(
            onPressed: () => _showCreateOptions(context),
            backgroundColor: const Color(0xFF667EEA),
            icon: Icon(_isAdmin ? Icons.admin_panel_settings : Icons.add),
            label: Text(_isAdmin ? 'Manage Group' : 'Create Post'),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: const Color(0xFF667EEA)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom painter for elegant geometric pattern
class _GeometricPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final path = Path();

    // Create subtle geometric lines inspired by Apple's design language
    const spacing = 80.0;
    const offset = 40.0;

    // Diagonal lines creating a subtle diamond pattern
    for (double i = -spacing; i < size.width + spacing; i += spacing) {
      // Top-left to bottom-right diagonals
      path.moveTo(i, 0);
      path.lineTo(i + size.height, size.height);

      // Top-right to bottom-left diagonals
      path.moveTo(i + offset, 0);
      path.lineTo(i + offset - size.height, size.height);
    }

    // Add some subtle curved elements for elegance
    final curvePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Subtle curved arcs in corners
    final arcPath = Path();

    // Top-left arc
    arcPath.addArc(
      Rect.fromCircle(center: const Offset(-50, -50), radius: 120),
      0,
      1.57, // 90 degrees in radians
    );

    // Bottom-right arc
    arcPath.addArc(
      Rect.fromCircle(
        center: Offset(size.width + 50, size.height + 50),
        radius: 120,
      ),
      3.14, // 180 degrees
      1.57, // 90 degrees
    );

    canvas.drawPath(path, paint);
    canvas.drawPath(arcPath, curvePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
