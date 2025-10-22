import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/firebase/organization_helper.dart';
import 'package:attendus/screens/Groups/group_profile_screen_v2.dart';
import 'package:attendus/screens/Groups/create_group_screen.dart';
import 'package:attendus/Utils/cached_image.dart';
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
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          title: const Text('Groups'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        titleTextStyle: const TextStyle(
          color: Colors.black87,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        title: const Text('Groups'),
        actions: [
          TextButton.icon(
            onPressed: _goToCreate,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Create'),
            style: TextButton.styleFrom(foregroundColor: Colors.black87),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchCtlr,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search groups',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        _debounce?.cancel();
                        _debounce = Timer(
                          const Duration(milliseconds: 300),
                          _discover,
                        );
                      },
                      onSubmitted: (_) {
                        _debounce?.cancel();
                        _discover();
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'My Groups',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    _isLoadingMyOrgs
                        ? SizedBox(
                            height: 110,
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          )
                        : (_myOrgs.isEmpty
                              ? _EmptyStateCard(onCreate: _goToCreate)
                              : SizedBox(
                                  height: 110,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _myOrgs.length,
                                    separatorBuilder: (_, index) =>
                                        const SizedBox(width: 12),
                                    itemBuilder: (context, i) {
                                      final org = _myOrgs[i];
                                      return GestureDetector(
                                        onTap: () {
                                          final orgId = org['id'];
                                          if (orgId == null || orgId.isEmpty) {
                                            return;
                                          }
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  GroupProfileScreenV2(
                                                    organizationId: orgId,
                                                  ),
                                            ),
                                          );
                                        },
                                        child: _pill(
                                          org['name'] ?? '',
                                          icon: Icons.apartment,
                                          imageUrl: org['logoUrl'],
                                        ),
                                      );
                                    },
                                  ),
                                )),
                    const SizedBox(height: 16),
                    const Text(
                      'Discover',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    _buildCategoryChips(),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              _isLoadingDiscover
                  ? const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    )
                  : SliverList.separated(
                      itemCount: _discoverOrgs.length,
                      separatorBuilder: (_, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final o = _discoverOrgs[i];
                        final String logoUrl = (o['logoUrl'] ?? '').toString();
                        return Container(
                          decoration: _cardDeco(),
                          child: ListTile(
                            leading: _orgAvatar(logoUrl, size: 40, icon: Icons.apartment),
                            title: Text(o['name']?.toString() ?? ''),
                            subtitle: Text(
                              o['category']?.toString() ?? 'Other',
                            ),
                            onTap: () {
                              final String? orgId = o['id']?.toString();
                              if (orgId == null || orgId.isEmpty) return;
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => GroupProfileScreenV2(
                                    organizationId: orgId,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
        ),
      ),
      floatingActionButton: null,
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

  BoxDecoration _cardDeco() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.06),
        blurRadius: 16,
        offset: const Offset(0, 8),
      ),
    ],
  );

  Widget _pill(String text, {IconData? icon, String? imageUrl}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: _cardDeco(),
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

  Widget _orgAvatar(String imageUrl, {double size = 24, IconData icon = Icons.apartment}) {
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF6B7280)),
          const SizedBox(width: 12),
          const Expanded(child: Text('You have not joined any groups yet.')),
          const SizedBox(width: 12),
          FilledButton(onPressed: onCreate, child: const Text('Create')),
        ],
      ),
    );
  }
}
