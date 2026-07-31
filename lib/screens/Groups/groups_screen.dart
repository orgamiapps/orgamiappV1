import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/firebase/organization_helper.dart';
import 'package:attendus/screens/Groups/group_profile_screen_v2.dart';
import 'package:attendus/screens/Groups/create_group_screen.dart';
import 'package:attendus/Utils/cached_image.dart';
import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/widgets/attendus_design_system.dart';
import 'dart:async';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final TextEditingController _searchCtlr = TextEditingController();
  List<Map<String, String>> _myOrgs = [];
  List<Map<String, dynamic>> _discoverOrgs = [];
  String? _selectedCategoryLower;
  bool _isLoadingMyOrgs = true;
  bool _isLoadingDiscover = false;
  bool _isInitialLoad = true;
  Timer? _debounce;
  final List<Map<String, String>> _categoryOptions = const [
    {'label': 'All', 'value': ''},
    {'label': 'Business', 'value': 'business'},
    {'label': 'Club', 'value': 'club'},
    {'label': 'School', 'value': 'school'},
    {'label': 'Sports', 'value': 'sports'},
    {'label': 'Other', 'value': 'other'},
  ];

  Stream<List<Map<String, String>>>? _myOrgsStream;

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _initStreams() async {
    try {
      final helper = OrganizationHelper();
      if (mounted) setState(() => _isLoadingMyOrgs = true);

      // Load user organizations with error handling
      try {
        final my = await helper.getUserOrganizationsLite();
        if (mounted) {
          setState(() {
            _myOrgs = my;
            _isLoadingMyOrgs = false;
          });
        }
      } catch (e) {
        debugPrint('Error loading user organizations: $e');
        if (mounted) {
          setState(() {
            _myOrgs = [];
            _isLoadingMyOrgs = false;
          });
        }
      }

      // Set up stream listener with error handling
      _myOrgsStream ??= helper.streamUserOrganizationsLite();
      _myOrgsStream!.listen(
        (list) {
          if (!mounted) return;
          setState(() {
            _myOrgs = list;
            _isLoadingMyOrgs = false;
          });
        },
        onError: (error) {
          debugPrint('Stream error: $error');
          if (mounted) {
            setState(() => _isLoadingMyOrgs = false);
          }
        },
      );

      // Discover organizations asynchronously without blocking
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _discover();
      });
    } catch (e) {
      debugPrint('Error in _initStreams: $e');
      if (mounted) {
        setState(() {
          _isLoadingMyOrgs = false;
          _isInitialLoad = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isInitialLoad = false);
      }
    }
  }

  Future<void> _discover() async {
    try {
      if (mounted) setState(() => _isLoadingDiscover = true);

      Query query = FirebaseFirestore.instance
          .collection('Organizations')
          .limit(25);
      final q = _searchCtlr.text.trim().toLowerCase();

      if (_selectedCategoryLower != null &&
          _selectedCategoryLower!.isNotEmpty) {
        query = query.where(
          'category_lowercase',
          isEqualTo: _selectedCategoryLower,
        );
      }

      if (q.isNotEmpty) {
        final String end =
            q.substring(0, q.length - 1) +
            String.fromCharCode(q.codeUnitAt(q.length - 1) + 1);
        query = query.orderBy('name_lowercase').startAt([q]).endBefore([end]);
      } else {
        query = query.orderBy('name_lowercase');
      }

      // Add timeout to prevent hanging
      final snap = await query.get().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('Firestore query timeout');
          throw TimeoutException('Query timeout');
        },
      );

      final list = snap.docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        data['id'] = d.id;
        return data;
      }).toList();

      if (mounted) {
        setState(() {
          _discoverOrgs = list;
          _isLoadingDiscover = false;
        });
      }
    } catch (e) {
      debugPrint('Error discovering organizations: $e');
      if (mounted) {
        setState(() {
          _discoverOrgs = [];
          _isLoadingDiscover = false;
        });
      }
    }
  }

  Future<void> _goToCreate() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CreateGroupScreen()));
    _initStreams();
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator during initial load
    if (_isInitialLoad) {
      return const AttendUsLoadingState(label: 'Loading groups');
    }

    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            AttendUsTopBar(
              title: 'Groups',
              subtitle: 'Manage communities and discover organizer spaces.',
              actions: [
                AttendUsButton.primary(
                  label: 'Create group',
                  icon: Icons.add,
                  onPressed: _goToCreate,
                ),
              ],
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AttendUsTokens.pageMaxWidth,
                  ),
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: AttendUsTokens.pagePadding,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSearchAndFilters(),
                              const SizedBox(height: 18),
                              _buildMyGroupsSection(),
                              const SizedBox(height: 18),
                              AttendUsSectionHeader(
                                title: 'Discover Groups',
                                subtitle:
                                    'Find public communities by name or category.',
                                icon: Icons.travel_explore_outlined,
                                actions: [
                                  AttendUsStatusBadge(
                                    label: '${_discoverOrgs.length} shown',
                                    tone: AttendUsStatusTone.neutral,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                            ],
                          ),
                        ),
                      ),
                      _buildDiscoverSliver(),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: null,
    );
  }

  Widget _buildSearchAndFilters() {
    return AttendUsPageSection(
      title: 'Community Directory',
      subtitle: 'Search across your groups and discover new communities.',
      icon: Icons.groups_2_outlined,
      framed: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AttendUsSearchField(
            controller: _searchCtlr,
            hintText: 'Search groups',
            onChanged: (value) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), _discover);
            },
          ),
          const SizedBox(height: 14),
          _buildCategoryChips(),
        ],
      ),
    );
  }

  Widget _buildMyGroupsSection() {
    if (_isLoadingMyOrgs) {
      return const SizedBox(
        height: 132,
        child: AttendUsLoadingState(label: 'Loading your groups'),
      );
    }

    return AttendUsPageSection(
      title: 'My Groups',
      subtitle: 'Groups where you are a member or organizer.',
      icon: Icons.account_tree_outlined,
      framed: true,
      actions: [
        AttendUsStatusBadge(
          label: '${_myOrgs.length}',
          tone: AttendUsStatusTone.info,
        ),
      ],
      child: _myOrgs.isEmpty
          ? _EmptyStateCard(onCreate: _goToCreate)
          : SizedBox(
              height: 112,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _myOrgs.length,
                separatorBuilder: (_, index) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final org = _myOrgs[i];
                  return _pill(
                    org['name'] ?? '',
                    icon: Icons.apartment,
                    imageUrl: org['logoUrl'],
                    onTap: () => _openGroup(org['id']),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildDiscoverSliver() {
    if (_isLoadingDiscover) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: AttendUsLoadingState(label: 'Finding groups'),
        ),
      );
    }

    if (_discoverOrgs.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: AttendUsEmptyState(
            icon: Icons.search_off_outlined,
            title: 'No groups found',
            message: 'Try a different search term or category.',
            action: AttendUsButton.secondary(
              label: 'Clear filters',
              icon: Icons.refresh,
              onPressed: () {
                _searchCtlr.clear();
                setState(() => _selectedCategoryLower = null);
                _discover();
              },
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.crossAxisExtent >= 1040
              ? 3
              : constraints.crossAxisExtent >= 720
              ? 2
              : 1;
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: crossAxisCount == 1 ? 4.4 : 2.4,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate((context, i) {
              final org = _discoverOrgs[i];
              return AttendUsGroupCard(
                name: org['name']?.toString() ?? 'Untitled group',
                description: org['description']?.toString(),
                imageUrl: org['logoUrl']?.toString(),
                statusLabel: org['category']?.toString() ?? 'Other',
                memberCountLabel: org['memberCount'] == null
                    ? null
                    : '${org['memberCount']} members',
                onTap: () => _openGroup(org['id']?.toString()),
              );
            }, childCount: _discoverOrgs.length),
          );
        },
      ),
    );
  }

  void _openGroup(String? orgId) {
    if (orgId == null || orgId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupProfileScreenV2(organizationId: orgId),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _categoryOptions.map((opt) {
          final selected =
              (_selectedCategoryLower ?? '') == (opt['value'] ?? '');
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(opt['label'] ?? ''),
              selected: selected,
              onSelected: (_) {
                setState(() {
                  _selectedCategoryLower = (opt['value'] ?? '').isEmpty
                      ? null
                      : opt['value'];
                });
                _discover();
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _pill(
    String text, {
    IconData? icon,
    String? imageUrl,
    VoidCallback? onTap,
  }) {
    return AttendUsCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (imageUrl != null && imageUrl.isNotEmpty) ...[
            _orgAvatar(imageUrl, size: 20, icon: icon ?? Icons.apartment),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 16),
            const SizedBox(width: 6),
          ],
          Text(text),
        ],
      ),
    );
  }

  Widget _orgAvatar(
    String imageUrl, {
    double size = 24,
    IconData icon = Icons.apartment,
  }) {
    if (imageUrl.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        child: Icon(icon, size: size * 0.6),
      );
    }
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: SafeNetworkImage(
          imageUrl: imageUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: Icon(icon, size: size * 0.6),
          errorWidget: Icon(icon, size: size * 0.6),
        ),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyStateCard({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return AttendUsCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 12),
          const Expanded(child: Text('You have not joined any groups yet.')),
          const SizedBox(width: 12),
          AttendUsButton.secondary(
            label: 'Create',
            icon: Icons.add,
            onPressed: onCreate,
          ),
        ],
      ),
    );
  }
}
