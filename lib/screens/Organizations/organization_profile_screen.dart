import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:orgami/firebase/organization_helper.dart';
import 'package:orgami/firebase/firebase_storage_helper.dart';
import 'package:orgami/screens/Organizations/join_requests_screen.dart';
import 'package:orgami/screens/Organizations/role_permissions_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:orgami/models/customer_model.dart';
import 'package:orgami/screens/MyProfile/user_profile_screen.dart';
import 'package:orgami/controller/customer_controller.dart';
import 'package:orgami/models/event_model.dart';
import 'package:orgami/screens/Events/Widget/single_event_list_view_item.dart';
import 'package:orgami/screens/Events/single_event_screen.dart';

class OrganizationProfileScreen extends StatelessWidget {
  final String organizationId;
  const OrganizationProfileScreen({super.key, required this.organizationId});

  Future<void> _shareOrganization(BuildContext context) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('Organizations')
          .doc(organizationId)
          .get();
      final Map<String, dynamic>? data = doc.data();
      final name = (data?['name'] ?? 'Organization').toString();
      final category = (data?['category'] ?? 'Other').toString();
      final desc = (data?['description'] ?? '').toString();
      final buffer = StringBuffer()
        ..writeln('Check out "$name" on Orgami')
        ..writeln('Category: $category');
      if (desc.trim().isNotEmpty) buffer.writeln(desc.trim());
      buffer
        ..writeln()
        ..writeln(
          'Open the app and search for this organization or use this ID: $organizationId',
        );
      await Share.share(buffer.toString(), subject: name);
    } catch (_) {}
  }

  void _openAdminTools(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.85,
          child: _OrgSettingsTab(orgId: organizationId),
        ),
      ),
    );
  }

  // Build a floating action button similar to the Manage Event button
  Widget _buildManageFab(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    final memberStream = FirebaseFirestore.instance
        .collection('Organizations')
        .doc(organizationId)
        .collection('Members')
        .doc(uid)
        .snapshots();

    const Color primaryBlue = Color(0xFF667EEA);
    const Color primaryPurple = Color(0xFF764BA2);

    return StreamBuilder<DocumentSnapshot>(
      stream: memberStream,
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final role = (data?['role'] ?? '').toString();
        final List<dynamic> perms =
            (data?['permissions'] as List<dynamic>?) ?? const [];
        final bool canManage =
            role == 'Admin' ||
            perms.contains('ManageMembersRoles') ||
            perms.contains('ApproveJoinRequests');

        if (!canManage) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [primaryBlue, primaryPurple],
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: primaryBlue.withOpacity(0.4),
                blurRadius: 15,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: primaryPurple.withOpacity(0.3),
                blurRadius: 25,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: FloatingActionButton.extended(
            onPressed: () => _openAdminTools(context),
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            extendedPadding: const EdgeInsets.symmetric(horizontal: 24),
            icon: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.dashboard_outlined,
                size: 18,
                color: Colors.white,
              ),
            ),
            label: const Text(
              'Manage Organization',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontFamily: 'Roboto',
                fontSize: 16,
                letterSpacing: 0.2,
              ),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          leading: Padding(
            padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                color: Colors.black87,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconButton(
                  tooltip: 'Share',
                  icon: const Icon(CupertinoIcons.share),
                  color: Colors.black87,
                  onPressed: () => _shareOrganization(context),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: _buildManageFab(context),
        body: Column(
          children: [
            _OrgHeader(orgId: organizationId),
            const TabBar(
              tabs: [
                Tab(text: 'Events'),
                Tab(text: 'Members'),
                Tab(text: 'About'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _OrgEventsTab(orgId: organizationId),
                  _OrgMembersTab(orgId: organizationId),
                  _OrgAboutTab(orgId: organizationId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrgHeader extends StatelessWidget {
  final String orgId;
  const _OrgHeader({required this.orgId});

  @override
  Widget build(BuildContext context) {
    final doc = FirebaseFirestore.instance
        .collection('Organizations')
        .doc(orgId);
    return FutureBuilder<DocumentSnapshot>(
      future: doc.get(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final bannerUrl = data?['bannerUrl']?.toString();
        final logoUrl = data?['logoUrl']?.toString();
        final name = data?['name']?.toString() ?? 'Organization';
        final category = data?['category']?.toString() ?? 'Other';
        final bool isLoading =
            snapshot.connectionState == ConnectionState.waiting;
        final bool hasBanner = (bannerUrl != null && bannerUrl.isNotEmpty);

        // Create a modern header made of two parts:
        // 1) A banner that reaches all the way to the very top (under the transparent AppBar)
        // 2) A white details section with dark text sitting directly beneath the banner
        final double topChromeHeight =
            MediaQuery.of(context).padding.top + kToolbarHeight;
        final double bannerHeight = topChromeHeight + 120; // visual weight

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: bannerHeight,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Placeholder/gradient or loading background
                  Container(
                    decoration: BoxDecoration(
                      color: isLoading ? const Color(0x19000000) : null,
                      gradient: (!isLoading && !hasBanner)
                          ? const LinearGradient(
                              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                    ),
                  ),

                  // Banner image layer with smooth fade-in
                  if (hasBanner)
                    Positioned.fill(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Image.network(
                              bannerUrl,
                              fit: BoxFit.cover,
                              frameBuilder: (context, child, frame, wasSync) {
                                if (wasSync) return child;
                                return AnimatedOpacity(
                                  opacity: frame == null ? 0 : 1,
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeInOut,
                                  child: child,
                                );
                              },
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                          Positioned.fill(
                            child: Container(
                              color: Colors.black.withOpacity(0.2),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Details section (white background, dark text)
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: const Color(0xFFE5E7EB),
                    backgroundImage: (logoUrl != null && logoUrl.isNotEmpty)
                        ? NetworkImage(logoUrl)
                        : null,
                    child: (logoUrl == null || logoUrl.isEmpty)
                        ? const Icon(Icons.apartment, color: Color(0xFF667EEA))
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          category,
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  _JoinAction(orgId: orgId),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _JoinAction extends StatefulWidget {
  final String orgId;
  const _JoinAction({required this.orgId});

  @override
  State<_JoinAction> createState() => _JoinActionState();
}

class _JoinActionState extends State<_JoinAction> {
  bool _isMember = false;
  bool _hasPending = false;
  bool _loading = true;
  String _role = 'Member';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _isMember = false;
          _hasPending = false;
          _loading = false;
        });
        return;
      }

      final memberSnap = await firestore
          .collection('Organizations')
          .doc(widget.orgId)
          .collection('Members')
          .doc(user.uid)
          .get();

      final memberData = memberSnap.data();
      final isApproved =
          memberSnap.exists &&
          ((memberData?['status'] ?? 'approved') == 'approved');
      final role = (memberData?['role'] ?? 'Member').toString();

      final joinSnap = await firestore
          .collection('Organizations')
          .doc(widget.orgId)
          .collection('JoinRequests')
          .doc(user.uid)
          .get();

      setState(() {
        _isMember = isApproved;
        _role = role.isEmpty ? 'Member' : role;
        _hasPending =
            !isApproved &&
            joinSnap.exists &&
            ((joinSnap.data()?['status'] ?? 'pending') == 'pending');
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 36,
        width: 36,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Color(0xFF667EEA),
        ),
      );
    }
    if (_isMember) {
      return Chip(label: Text(_role));
    }
    if (_hasPending) {
      return const Chip(label: Text('Requested'));
    }
    return FilledButton(
      onPressed: () async {
        await OrganizationHelper().requestToJoinOrganization(widget.orgId);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Join request sent')));
        await _load();
      },
      child: const Text('Join'),
    );
  }
}

class _OrgEventsTab extends StatelessWidget {
  final String orgId;
  const _OrgEventsTab({required this.orgId});

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('Events')
        .where('organizationId', isEqualTo: orgId);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No events yet'));
        }
        // Filter upcoming and sort client-side by selectedDateTime
        final DateTime threshold = DateTime.now().subtract(
          const Duration(hours: 3),
        );
        final docs =
            snapshot.data!.docs.where((d) {
              final dt = (d['selectedDateTime'] as Timestamp?)?.toDate();
              return dt == null || dt.isAfter(threshold);
            }).toList()..sort((a, b) {
              final ad =
                  (a['selectedDateTime'] as Timestamp?)?.toDate() ??
                  DateTime(2100);
              final bd =
                  (b['selectedDateTime'] as Timestamp?)?.toDate() ??
                  DateTime(2100);
              return ad.compareTo(bd);
            });
        return ListView.builder(
          itemCount: docs.length,
          padding: const EdgeInsets.all(16),
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            data['id'] = data['id'] ?? docs[i].id;
            final model = EventModel.fromJson(data);
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SingleEventListViewItem(
                eventModel: model,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SingleEventScreen(eventModel: model),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _OrgMembersTab extends StatelessWidget {
  final String orgId;
  const _OrgMembersTab({required this.orgId});

  @override
  Widget build(BuildContext context) {
    final membersQuery = FirebaseFirestore.instance
        .collection('Organizations')
        .doc(orgId)
        .collection('Members')
        .orderBy('joinedAt', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: membersQuery.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No members yet'));
        }
        final docs = snapshot.data!.docs;
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 0),
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final String userId = (data['userId'] ?? '').toString();
            final String role = (data['role'] ?? 'Member').toString();

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('Customers')
                  .doc(userId)
                  .get(),
              builder: (context, userSnap) {
                if (userSnap.connectionState == ConnectionState.waiting) {
                  return const _MemberCardSkeleton();
                }

                final Map<String, dynamic>? userData =
                    userSnap.data?.data() as Map<String, dynamic>?;
                if (userData == null) {
                  // In case user record is missing, show a graceful placeholder
                  return const _MemberCard(
                    name: 'Member',
                    username: '',
                    photoUrl: '',
                    role: 'Member',
                  );
                }

                final String displayName = (userData['name'] ?? 'Member')
                    .toString();
                final String username = (userData['username'] ?? '').toString();
                final String photoUrl = (userData['profilePictureUrl'] ?? '')
                    .toString();

                return _MemberCard(
                  name: displayName,
                  username: username,
                  photoUrl: photoUrl,
                  role: role,
                  userId: userId,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _MemberCard extends StatelessWidget {
  final String name;
  final String username;
  final String photoUrl;
  final String role;
  final String? userId;
  const _MemberCard({
    required this.name,
    required this.username,
    required this.photoUrl,
    required this.role,
    this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasPhoto = photoUrl.isNotEmpty;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF64748B).withAlpha((0.1 * 255).round()),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        splashColor: const Color(0x33667EEA),
        highlightColor: const Color(0x11667EEA),
        onTap: userId == null
            ? null
            : () async {
                try {
                  final doc = await FirebaseFirestore.instance
                      .collection('Customers')
                      .doc(userId)
                      .get();
                  final Map<String, dynamic>? d = doc.data();
                  if (d == null) return;
                  // Parse createdAt robustly (mirrors model's factory logic)
                  DateTime parsedCreatedAt = DateTime.now();
                  final rawCreatedAt = d['createdAt'];
                  if (rawCreatedAt is Timestamp) {
                    parsedCreatedAt = rawCreatedAt.toDate();
                  } else if (rawCreatedAt is DateTime) {
                    parsedCreatedAt = rawCreatedAt;
                  } else if (rawCreatedAt is String) {
                    parsedCreatedAt =
                        DateTime.tryParse(rawCreatedAt) ?? DateTime.now();
                  }

                  final user = CustomerModel(
                    uid: (d['uid'] ?? userId).toString(),
                    name: (d['name'] ?? '').toString(),
                    email: (d['email'] ?? '').toString(),
                    username: (d['username'] as String?),
                    profilePictureUrl: (d['profilePictureUrl'] as String?),
                    bio: (d['bio'] as String?),
                    phoneNumber: (d['phoneNumber'] as String?),
                    age: (d['age'] as int?),
                    gender: (d['gender'] as String?),
                    location: (d['location'] as String?),
                    occupation: (d['occupation'] as String?),
                    company: (d['company'] as String?),
                    website: (d['website'] as String?),
                    socialMediaLinks: (d['socialMediaLinks'] as String?),
                    isDiscoverable: (d['isDiscoverable'] as bool?) ?? true,
                    favorites: List<String>.from(d['favorites'] ?? const []),
                    createdAt: parsedCreatedAt,
                  );
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => UserProfileScreen(
                        user: user,
                        isOwnProfile:
                            user.uid == CustomerController.logeInCustomer?.uid,
                      ),
                    ),
                  );
                } catch (_) {}
              },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Hero(
                tag: 'user_avatar_${userId ?? name}',
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(
                      0xFF667EEA,
                    ).withAlpha((0.1 * 255).round()),
                  ),
                  child: hasPhoto
                      ? ClipOval(
                          child: Image.network(
                            photoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                style: const TextStyle(
                                  color: Color(0xFF667EEA),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 20,
                                  fontFamily: 'Roboto',
                                ),
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'U',
                            style: const TextStyle(
                              color: Color(0xFF667EEA),
                              fontWeight: FontWeight.w600,
                              fontSize: 20,
                              fontFamily: 'Roboto',
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                        fontFamily: 'Roboto',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (username.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '@$username',
                        style: const TextStyle(
                          color: Color(0xFF667EEA),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Roboto',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: role == 'Admin'
                      ? const Color(0xFFEEF2FF)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  role,
                  style: TextStyle(
                    color: role == 'Admin'
                        ? const Color(0xFF667EEA)
                        : const Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberCardSkeleton extends StatelessWidget {
  const _MemberCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF64748B).withAlpha((0.1 * 255).round()),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey.shade300,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 14,
                  width: 160,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 12,
                  width: 120,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 60,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrgAboutTab extends StatelessWidget {
  final String orgId;
  const _OrgAboutTab({required this.orgId});

  @override
  Widget build(BuildContext context) {
    final DocumentReference orgDoc = FirebaseFirestore.instance
        .collection('Organizations')
        .doc(orgId);

    final Stream<int> membersCountStream = FirebaseFirestore.instance
        .collection('Organizations')
        .doc(orgId)
        .collection('Members')
        .snapshots()
        .map((s) => s.docs.length);

    final Query upcomingEventsQuery = FirebaseFirestore.instance
        .collection('Events')
        .where('organizationId', isEqualTo: orgId)
        .where(
          'selectedDateTime',
          isGreaterThan: Timestamp.fromDate(DateTime.now()),
        )
        .orderBy('selectedDateTime')
        .limit(3);

    return FutureBuilder<DocumentSnapshot>(
      future: orgDoc.get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: Text('Organization not found'));
        }

        final Map<String, dynamic> data =
            snapshot.data!.data() as Map<String, dynamic>;

        final String name = (data['name'] ?? '').toString();
        final String description = (data['description'] ?? '').toString();
        final String category = (data['category'] ?? 'Other').toString();
        final String website = (data['website'] ?? '').toString();
        final String email = (data['email'] ?? '').toString();
        final String phone = (data['phone'] ?? '').toString();
        final String address = (data['address'] ?? '').toString();
        final String instagram = (data['instagram'] ?? '').toString();
        final String twitter = (data['twitter'] ?? '').toString();
        final String facebook = (data['facebook'] ?? '').toString();
        final String linkedin = (data['linkedin'] ?? '').toString();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // About text card
              _SectionCard(
                title: 'About',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (name.isNotEmpty)
                      Text(name, style: Theme.of(context).textTheme.titleLarge),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        description,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(height: 1.4),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Quick facts chips
              _SectionCard(
                title: 'At a glance',
                child: StreamBuilder<int>(
                  stream: membersCountStream,
                  builder: (context, membersSnap) {
                    final int membersCount = membersSnap.data ?? 0;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoPill(
                          icon: Icons.category,
                          label: 'Category',
                          value: category,
                        ),
                        _InfoPill(
                          icon: Icons.people,
                          label: 'Members',
                          value: membersCount.toString(),
                        ),
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              // Contact and social links
              if ([
                website,
                email,
                phone,
                address,
                instagram,
                twitter,
                facebook,
                linkedin,
              ].any((e) => e.trim().isNotEmpty))
                _SectionCard(
                  title: 'Connect',
                  child: Column(
                    children: [
                      if (website.isNotEmpty)
                        _LinkTile(
                          icon: Icons.language,
                          label: website,
                          onTap: () =>
                              _launchUrl(Uri.parse(_normalizeUrl(website))),
                        ),
                      if (email.isNotEmpty)
                        _LinkTile(
                          icon: Icons.email_outlined,
                          label: email,
                          onTap: () =>
                              _launchUrl(Uri(scheme: 'mailto', path: email)),
                        ),
                      if (phone.isNotEmpty)
                        _LinkTile(
                          icon: Icons.phone,
                          label: phone,
                          onTap: () =>
                              _launchUrl(Uri(scheme: 'tel', path: phone)),
                        ),
                      if (address.isNotEmpty)
                        _LinkTile(
                          icon: Icons.place_outlined,
                          label: address,
                          onTap: () => _launchUrl(
                            Uri.parse(
                              'https://www.google.com/maps/search/?api=1&query=' +
                                  Uri.encodeComponent(address),
                            ),
                          ),
                        ),
                      if (instagram.isNotEmpty)
                        _LinkTile(
                          icon: Icons.camera_alt_outlined,
                          label: 'Instagram',
                          onTap: () =>
                              _launchUrl(Uri.parse(_normalizeUrl(instagram))),
                        ),
                      if (twitter.isNotEmpty)
                        _LinkTile(
                          icon: Icons.alternate_email,
                          label: 'Twitter/X',
                          onTap: () =>
                              _launchUrl(Uri.parse(_normalizeUrl(twitter))),
                        ),
                      if (facebook.isNotEmpty)
                        _LinkTile(
                          icon: Icons.facebook,
                          label: 'Facebook',
                          onTap: () =>
                              _launchUrl(Uri.parse(_normalizeUrl(facebook))),
                        ),
                      if (linkedin.isNotEmpty)
                        _LinkTile(
                          icon: Icons.business,
                          label: 'LinkedIn',
                          onTap: () =>
                              _launchUrl(Uri.parse(_normalizeUrl(linkedin))),
                        ),
                    ],
                  ),
                ),

              const SizedBox(height: 12),

              // Admins preview
              _SectionCard(
                title: 'Admins',
                child: SizedBox(
                  height: 72,
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('Organizations')
                        .doc(orgId)
                        .collection('Members')
                        .where('role', isEqualTo: 'Admin')
                        .limit(10)
                        .snapshots(),
                    builder: (context, snap) {
                      final docs = snap.data?.docs ?? const [];
                      if (docs.isEmpty) {
                        return const Center(
                          child: Text('No admins listed yet'),
                        );
                      }
                      return ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, i) {
                          final Map<String, dynamic> m =
                              docs[i].data() as Map<String, dynamic>;
                          final String userId = (m['userId'] ?? '').toString();
                          return FutureBuilder<DocumentSnapshot>(
                            future: FirebaseFirestore.instance
                                .collection('Customers')
                                .doc(userId)
                                .get(),
                            builder: (context, userSnap) {
                              final Map<String, dynamic>? u =
                                  userSnap.data?.data()
                                      as Map<String, dynamic>?;
                              final String name = (u?['name'] ?? 'Admin')
                                  .toString();
                              final String photo =
                                  (u?['profilePictureUrl'] ?? '').toString();
                              return _AdminChip(name: name, photoUrl: photo);
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Upcoming events preview
              _SectionCard(
                title: 'Upcoming events',
                child: StreamBuilder<QuerySnapshot>(
                  stream: upcomingEventsQuery.snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: LinearProgressIndicator(),
                      );
                    }
                    final events = snap.data?.docs ?? const [];
                    if (events.isEmpty) {
                      return const Text('No upcoming events');
                    }
                    return Column(
                      children: events.map((d) {
                        final Map<String, dynamic> e =
                            d.data() as Map<String, dynamic>;
                        final String title = (e['title'] ?? '').toString();
                        final String location = (e['location'] ?? '')
                            .toString();
                        final Timestamp ts =
                            (e['selectedDateTime'] ?? Timestamp.now())
                                as Timestamp;
                        final DateTime date = ts.toDate();
                        final String when = DateFormat(
                          'EEE, MMM d • h:mm a',
                        ).format(date);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.event,
                            color: Color(0xFF667EEA),
                          ),
                          title: Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            [
                              when,
                              if (location.isNotEmpty) location,
                            ].join(' • '),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _normalizeUrl(String value) {
  final String v = value.trim();
  if (v.isEmpty) return v;
  if (v.startsWith('http://') || v.startsWith('https://')) return v;
  return 'https://$v';
}

Future<void> _launchUrl(Uri uri) async {
  try {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // ignore: avoid_print
      print('Could not launch: $uri');
    }
  } catch (_) {}
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF667EEA)),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _LinkTile({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: const Color(0xFF667EEA)),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: onTap,
    );
  }
}

class _AdminChip extends StatelessWidget {
  final String name;
  final String photoUrl;
  const _AdminChip({required this.name, required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final bool hasPhoto = photoUrl.isNotEmpty;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 22,
          backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
          child: hasPhoto ? null : const Icon(Icons.person),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 80,
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _OrgSettingsTab extends StatelessWidget {
  final String orgId;
  const _OrgSettingsTab({required this.orgId});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('Sign in to manage'));
    }
    final memberDoc = FirebaseFirestore.instance
        .collection('Organizations')
        .doc(orgId)
        .collection('Members')
        .doc(uid)
        .snapshots();

    return StreamBuilder<DocumentSnapshot>(
      stream: memberDoc,
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final role = (data?['role'] ?? '').toString();
        final List<dynamic> perms =
            (data?['permissions'] as List<dynamic>?) ?? const [];
        final bool canManage =
            role == 'Admin' ||
            perms.contains('ManageMembersRoles') ||
            perms.contains('ApproveJoinRequests');

        if (!canManage) {
          return const Center(
            child: Text('You do not have admin access for this organization'),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Admin Tools',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit Organization'),
                subtitle: const Text('Update name, description, and category'),
                onTap: () => _showEditOrganizationSheet(context, orgId),
              ),
              ListTile(
                leading: const Icon(Icons.image),
                title: const Text('Update Logo'),
                subtitle: const Text('Upload or change organization logo'),
                onTap: () =>
                    _pickAndUploadImage(context, orgId, isBanner: false),
              ),
              ListTile(
                leading: const Icon(Icons.wallpaper),
                title: const Text('Update Banner'),
                subtitle: const Text('Upload or change header banner'),
                onTap: () =>
                    _pickAndUploadImage(context, orgId, isBanner: true),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.group_add),
                title: const Text('Join Requests'),
                subtitle: const Text(
                  'Approve or decline organization join requests',
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => JoinRequestsScreen(organizationId: orgId),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.admin_panel_settings),
                title: const Text('Roles & Permissions'),
                subtitle: const Text('Manage member roles and permissions'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        RolePermissionsScreen(organizationId: orgId),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditOrganizationSheet(BuildContext context, String orgId) {
    final nameCtlr = TextEditingController();
    final descCtlr = TextEditingController();
    final categoryCtlr = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: MediaQuery.of(ctx).viewInsets + const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Edit Organization',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtlr,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtlr,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: categoryCtlr,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final updates = <String, dynamic>{};
                    if (nameCtlr.text.trim().isNotEmpty) {
                      updates['name'] = nameCtlr.text.trim();
                      updates['name_lowercase'] = nameCtlr.text
                          .trim()
                          .toLowerCase();
                    }
                    if (descCtlr.text.trim().isNotEmpty) {
                      updates['description'] = descCtlr.text.trim();
                    }
                    if (categoryCtlr.text.trim().isNotEmpty) {
                      updates['category'] = categoryCtlr.text.trim();
                      updates['category_lowercase'] = categoryCtlr.text
                          .trim()
                          .toLowerCase();
                    }
                    if (updates.isNotEmpty) {
                      await FirebaseFirestore.instance
                          .collection('Organizations')
                          .doc(orgId)
                          .set(updates, SetOptions(merge: true));
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadImage(
    BuildContext context,
    String orgId, {
    required bool isBanner,
  }) async {
    try {
      final picked = await FirebaseStorageHelper.pickImageFromGallery();
      if (picked == null) return;
      final url = await FirebaseStorageHelper.uploadOrganizationImage(
        organizationId: orgId,
        imageFile: picked,
        isBanner: isBanner,
      );
      if (url == null) return;
      await FirebaseFirestore.instance
          .collection('Organizations')
          .doc(orgId)
          .set({
            isBanner ? 'bannerUrl' : 'logoUrl': url,
          }, SetOptions(merge: true));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${isBanner ? 'Banner' : 'Logo'} updated')),
        );
      }
    } catch (_) {}
  }
}
