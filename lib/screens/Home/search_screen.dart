import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:orgami/screens/Events/Widget/single_event_list_view_item.dart';
import 'package:orgami/screens/MyProfile/user_profile_screen.dart';
import 'package:orgami/utils/colors.dart';
import 'package:orgami/firebase/engagement_predictor.dart';
import 'package:orgami/firebase/firebase_firestore_helper.dart';
import 'package:orgami/firebase/recommendation_analytics.dart';
import 'package:orgami/models/customer_model.dart';
import 'package:orgami/models/event_model.dart';
import 'package:shimmer/shimmer.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                EventsList(searchQuery: _searchQuery),
                UsersList(searchQuery: _searchQuery),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.arrow_back_ios_new,
            color: Color(0xFF1E293B),
            size: 18,
          ),
        ),
      ),
      title: const Text(
        'Search & Discover',
        style: TextStyle(
          color: Color(0xFF1E293B),
          fontSize: 20,
          fontWeight: FontWeight.w700,
          fontFamily: 'Roboto',
        ),
      ),
      centerTitle: false,
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _searchController.text.isEmpty
                ? const Color(0xFFE2E8F0)
                : const Color(0xFF667EEA),
            width: 1.5,
          ),
        ),
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              vertical: 16,
              horizontal: 16,
            ),
            border: InputBorder.none,
            hintText: _tabController.index == 0
                ? 'Find events by name, location, or category...'
                : 'Find users by name or username...',
            hintStyle: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 15,
              fontFamily: 'Roboto',
            ),
            prefixIcon: const Icon(
              Icons.search,
              color: Color(0xFF64748B),
              size: 22,
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(
                      Icons.clear,
                      color: Color(0xFF64748B),
                      size: 20,
                    ),
                    onPressed: () => _searchController.clear(),
                  )
                : null,
          ),
          style: const TextStyle(
            color: Color(0xFF1E293B),
            fontSize: 15,
            fontFamily: 'Roboto',
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
        ),
        child: TabBar(
          controller: _tabController,
          onTap: (index) {
            // Update search hint when tab changes
            setState(() {});
          },
          indicator: BoxDecoration(
            color: const Color(0xFF667EEA),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF667EEA).withAlpha((0.3 * 255).round()),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorPadding: const EdgeInsets.all(4),
          dividerColor: Colors.transparent,
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFF64748B),
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            fontFamily: 'Roboto',
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 15,
            fontFamily: 'Roboto',
          ),
          tabs: const [
            Tab(text: 'Events'),
            Tab(text: 'Users'),
          ],
        ),
      ),
    );
  }
}

class EventsList extends StatefulWidget {
  final String searchQuery;
  const EventsList({super.key, required this.searchQuery});

  @override
  State<EventsList> createState() => _EventsListState();
}

class _EventsListState extends State<EventsList>
    with AutomaticKeepAliveClientMixin {
  List<EventModel> _allEvents = [];
  List<EventModel> _filteredEvents = [];
  bool _isLoading = false;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();
  static const int _pageSize = 10;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadEvents();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant EventsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _filterEvents();
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      _loadMoreEvents();
    }
  }

  void _filterEvents() {
    if (!mounted) return;
    setState(() {
      if (widget.searchQuery.isEmpty) {
        _filteredEvents = List.from(_allEvents);
      } else {
        final searchLower = widget.searchQuery.toLowerCase();
        _filteredEvents = _allEvents.where((event) {
          return event.title.toLowerCase().contains(searchLower) ||
              event.description.toLowerCase().contains(searchLower) ||
              event.location.toLowerCase().contains(searchLower) ||
              event.categories.any(
                (category) => category.toLowerCase().contains(searchLower),
              );
        }).toList();
      }
    });
  }

  Future<void> _loadEvents() async {
    if (_isLoading) return;

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      Query query = FirebaseFirestore.instance
          .collection(EventModel.firebaseKey)
          .where('private', isEqualTo: false)
          .where(
            'selectedDateTime',
            isGreaterThan: DateTime.now().subtract(const Duration(hours: 3)),
          )
          .orderBy('selectedDateTime')
          .limit(_pageSize);

      QuerySnapshot snapshot = await query.get();
      List<EventModel> events = snapshot.docs
          .map((e) => EventModel.fromJson(e.data() as Map<String, dynamic>))
          .toList();

      // Sort events with featured first
      events.sort((a, b) {
        if (a.isFeatured && !b.isFeatured) return -1;
        if (!a.isFeatured && b.isFeatured) return 1;
        return a.selectedDateTime.compareTo(b.selectedDateTime);
      });

      if (mounted) {
        setState(() {
          _allEvents = events;
          _filteredEvents = List.from(_allEvents);
          _isLoading = false;
          _hasMore = events.length == _pageSize;
        });
        _filterEvents();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading events: $e');
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreEvents() async {
    if (_isLoading || !_hasMore || widget.searchQuery.isNotEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      Query query = FirebaseFirestore.instance
          .collection(EventModel.firebaseKey)
          .where('private', isEqualTo: false)
          .where(
            'selectedDateTime',
            isGreaterThan: DateTime.now().subtract(const Duration(hours: 3)),
          )
          .orderBy('selectedDateTime')
          .limit(_pageSize)
          .startAfter([_allEvents.last.selectedDateTime]);

      QuerySnapshot snapshot = await query.get();
      List<EventModel> newEvents = snapshot.docs
          .map((e) => EventModel.fromJson(e.data() as Map<String, dynamic>))
          .toList();

      if (mounted) {
        setState(() {
          _allEvents.addAll(newEvents);
          _filteredEvents = List.from(_allEvents);
          _isLoading = false;
          _hasMore = newEvents.length == _pageSize;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading more events: $e');
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshEvents() async {
    _hasMore = true;
    await _loadEvents();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading && _allEvents.isEmpty) {
      return _buildLoadingState();
    }

    if (_filteredEvents.isEmpty && !_isLoading) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _refreshEvents,
      color: const Color(0xFF667EEA),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount:
            _filteredEvents.length +
            (_hasMore && widget.searchQuery.isEmpty ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _filteredEvents.length) {
            return _buildLoadingItem();
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SingleEventListViewItem(
              eventModel: _filteredEvents[index],
              onTap: () {
                EngagementPredictor.trackInteraction(
                  _filteredEvents[index].id,
                  'view',
                ).catchError((e) {
                  if (kDebugMode) {
                    print('Error tracking engagement: $e');
                  }
                });
                RecommendationAnalytics.trackRecommendationInteraction(
                  eventId: _filteredEvents[index].id,
                  interactionType: 'view',
                  position: index + 1,
                ).catchError((e) {
                  if (kDebugMode) {
                    print('Error tracking recommendation interaction: $e');
                  }
                });
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: 3,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Shimmer.fromColors(
            baseColor: const Color(0xFFE2E8F0),
            highlightColor: const Color(0xFFF8FAFC),
            child: Container(
              height: 280,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 100),
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withAlpha((0.1 * 255).round()),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 60,
                color: Color(0xFF667EEA),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.searchQuery.isEmpty
                  ? 'No Events Available'
                  : 'No Events Found',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.searchQuery.isEmpty
                  ? 'Check back later for exciting events!'
                  : 'Try adjusting your search terms',
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF64748B),
                fontFamily: 'Roboto',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingItem() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          child: const CircularProgressIndicator(color: Color(0xFF667EEA)),
        ),
      ),
    );
  }
}

class UsersList extends StatefulWidget {
  final String searchQuery;
  const UsersList({super.key, required this.searchQuery});

  @override
  State<UsersList> createState() => _UsersListState();
}

class _UsersListState extends State<UsersList>
    with AutomaticKeepAliveClientMixin {
  List<CustomerModel> _users = [];
  bool _isLoading = false;
  Timer? _debounce;
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant UsersList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != oldWidget.searchQuery) {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), () {
        _loadUsers();
      });
    }
  }

  Future<void> _loadUsers() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final users = await FirebaseFirestoreHelper().searchUsers(
        searchQuery: widget.searchQuery,
        limit: 50,
      );

      if (mounted) {
        setState(() {
          _users = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading users: $e');
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshUsers() async {
    await _loadUsers();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading && _users.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF667EEA)),
      );
    }

    if (_users.isEmpty && !_isLoading) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _refreshUsers,
      color: const Color(0xFF667EEA),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _users.length,
        itemBuilder: (context, index) {
          final user = _users[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildUserCard(user),
          );
        },
      ),
    );
  }

  Widget _buildUserCard(CustomerModel user) {
    return Container(
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => UserProfileScreen(user: user),
            ),
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
                    color: const Color(
                      0xFF667EEA,
                    ).withAlpha((0.1 * 255).round()),
                  ),
                  child:
                      user.profilePictureUrl != null &&
                          user.profilePictureUrl!.isNotEmpty
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: user.profilePictureUrl!,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF667EEA),
                              ),
                            ),
                            errorWidget: (context, url, error) => Center(
                              child: Text(
                                user.name.isNotEmpty
                                    ? user.name[0].toUpperCase()
                                    : 'U',
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
                            user.name.isNotEmpty
                                ? user.name[0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              color: Color(0xFF667EEA),
                              fontWeight: FontWeight.w600,
                              fontSize: 20,
                              fontFamily: 'Roboto',
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
                        user.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                          fontFamily: 'Roboto',
                        ),
                      ),
                      if (user.username != null &&
                          user.username!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '@${user.username}',
                          style: const TextStyle(
                            color: Color(0xFF667EEA),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios,
                    color: Color(0xFF64748B),
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 100),
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withAlpha((0.1 * 255).round()),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.people_outline,
                size: 60,
                color: Color(0xFF667EEA),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.searchQuery.isEmpty ? 'Start Searching' : 'No Users Found',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.searchQuery.isEmpty
                  ? 'Type in the search bar to find users'
                  : 'Try searching with different keywords',
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF64748B),
                fontFamily: 'Roboto',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
