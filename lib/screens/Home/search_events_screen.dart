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

enum SearchType { events, users }

class SearchEventsScreen extends StatefulWidget {
  const SearchEventsScreen({super.key});

  @override
  State<SearchEventsScreen> createState() => _SearchEventsScreenState();
}

class _SearchEventsScreenState extends State<SearchEventsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  SearchType _currentTab = SearchType.events;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _currentTab = _tabController.index == 0
              ? SearchType.events
              : SearchType.users;
        });
      }
    });
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // Light grey background
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverToBoxAdapter(child: _buildHeader(context)),
              SliverToBoxAdapter(child: _buildSearchBar()),
              SliverPersistentHeader(
                pinned: true,
                delegate: TabBarDelegate(_tabController),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              EventsDefaultList(searchQuery: _searchQuery),
              UsersDefaultList(searchQuery: _searchQuery),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      color: Colors.white,
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                color: Colors.black87,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 20),
          const Text(
            'Search & Explore',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              fontFamily: 'Roboto',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16.0,
            horizontal: 20.0,
          ),
          fillColor: const Color(0xFFF5F7FA),
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15.0),
            borderSide: BorderSide.none,
          ),
          hintText: _currentTab == SearchType.events
              ? 'Find events by name, location, or category'
              : 'Find users by name or username',
          hintStyle: TextStyle(color: Colors.grey[500]),
          prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: Colors.grey[500]),
                  onPressed: () => _searchController.clear(),
                )
              : null,
        ),
        style: const TextStyle(color: Colors.black87, fontFamily: 'Roboto'),
      ),
    );
  }
}

class TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabController tabController;

  TabBarDelegate(this.tabController);

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        height: 50,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(15),
        ),
        child: TabBar(
          controller: tabController,
          indicator: BoxDecoration(
            color: const Color(0xFF667EEA),
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF667EEA).withOpacity(0.4),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.black54,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            fontFamily: 'Roboto',
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
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

  @override
  double get maxExtent => 60.0;

  @override
  double get minExtent => 60.0;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      false;
}

class EventsDefaultList extends StatefulWidget {
  final String searchQuery;
  const EventsDefaultList({super.key, required this.searchQuery});

  @override
  State<EventsDefaultList> createState() => _EventsDefaultListState();
}

class _EventsDefaultListState extends State<EventsDefaultList> {
  List<EventModel> _allEvents = [];
  List<EventModel> _filteredEvents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  @override
  void didUpdateWidget(covariant EventsDefaultList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _filterEvents();
    }
  }

  void _filterEvents() {
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
          );

      QuerySnapshot snapshot = await query.get();

      List<EventModel> events = snapshot.docs
          .map((e) => EventModel.fromJson(e.data() as Map<String, dynamic>))
          .toList();

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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return ListView.builder(
        primary: false,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.all(20),
        itemCount: 3,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Shimmer.fromColors(
              baseColor: Colors.grey[300]!,
              highlightColor: Colors.grey[100]!,
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

    if (_filteredEvents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No Events Found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "We couldn't find any events matching your search.",
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadEvents,
      color: const Color(0xFF667EEA),
      child: ListView.builder(
        primary: false,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.all(20),
        itemCount: _filteredEvents.length,
        itemBuilder: (context, index) {
          return SingleEventListViewItem(
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
          );
        },
      ),
    );
  }
}

class UsersDefaultList extends StatefulWidget {
  final String searchQuery;
  const UsersDefaultList({super.key, required this.searchQuery});

  @override
  State<UsersDefaultList> createState() => _UsersDefaultListState();
}

class _UsersDefaultListState extends State<UsersDefaultList> {
  List<CustomerModel> _users = [];
  bool _isLoading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void didUpdateWidget(covariant UsersDefaultList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != oldWidget.searchQuery) {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), () {
        _loadUsers();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    try {
      final users = await FirebaseFirestoreHelper().searchUsers(
        searchQuery: widget.searchQuery,
        limit: 100,
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF667EEA)),
      );
    }

    if (_users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No Users Found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "We couldn't find anyone matching your search.",
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadUsers,
      color: const Color(0xFF667EEA),
      child: ListView.builder(
        primary: false,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.all(20),
        itemCount: _users.length,
        itemBuilder: (context, index) {
          final user = _users[index];
          return Card(
            elevation: 4,
            shadowColor: Colors.black.withOpacity(0.05),
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(15),
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
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: const Color(0xFF667EEA).withOpacity(0.1),
                      backgroundImage:
                          user.profilePictureUrl != null &&
                              user.profilePictureUrl!.isNotEmpty
                          ? CachedNetworkImageProvider(user.profilePictureUrl!)
                          : null,
                      child:
                          user.profilePictureUrl == null ||
                              user.profilePictureUrl!.isEmpty
                          ? Text(
                              user.name.isNotEmpty
                                  ? user.name[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                color: Color(0xFF667EEA),
                                fontWeight: FontWeight.bold,
                                fontSize: 24,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
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
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.grey,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
