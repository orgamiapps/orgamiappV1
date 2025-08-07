import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:orgami/models/event_model.dart';
import 'package:orgami/models/customer_model.dart';
import 'package:orgami/Screens/Events/single_event_screen.dart';
import 'package:orgami/Screens/MyProfile/user_profile_screen.dart';
import 'package:orgami/Utils/colors.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:orgami/firebase/firebase_firestore_helper.dart';
import 'package:orgami/Screens/Events/Widget/single_event_list_view_item.dart';
import 'package:orgami/firebase/engagement_predictor.dart';
import 'package:orgami/firebase/recommendation_analytics.dart';
import 'dart:async';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _currentTab = _tabController.index == 0
            ? SearchType.events
            : SearchType.users;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openSearch() {
    if (_currentTab == SearchType.events) {
      showSearch(context: context, delegate: EventSearchDelegate());
    } else {
      showSearch(context: context, delegate: UserSearchDelegate());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(child: _buildSearchBar()),
              SliverPersistentHeader(
                pinned: true,
                delegate: TabBarDelegate(_tabController),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: const [EventsDefaultList(), UsersDefaultList()],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Text(
              'Search',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                fontFamily: 'Roboto',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: GestureDetector(
        onTap: _openSearch,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: Colors.grey[600], size: 20),
              const SizedBox(width: 8),
              Text(
                _currentTab == SearchType.events
                    ? 'Search events...'
                    : 'Search users...',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 16,
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
        ),
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
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: TabBar(
          controller: tabController,
          indicator: BoxDecoration(
            color: const Color(0xFF667EEA),
            borderRadius: BorderRadius.circular(12),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey[600],
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            fontFamily: 'Roboto',
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.normal,
            fontSize: 14,
            fontFamily: 'Roboto',
          ),
          tabs: const [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event, size: 18),
                  SizedBox(width: 8),
                  Text('Events'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people, size: 18),
                  SizedBox(width: 8),
                  Text('Users'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  double get maxExtent => 48.0;

  @override
  double get minExtent => 48.0;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      false;
}

class EventsDefaultList extends StatefulWidget {
  const EventsDefaultList({super.key});

  @override
  State<EventsDefaultList> createState() => _EventsDefaultListState();
}

class _EventsDefaultListState extends State<EventsDefaultList> {
  List<EventModel> _events = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
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

      setState(() {
        _events = events;
        _isLoading = false;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading events: $e');
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        itemCount: 3,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Shimmer.fromColors(
              baseColor: const Color(0xFFE1E5E9),
              highlightColor: Colors.white,
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

    if (_events.isEmpty) {
      return const Center(child: Text('No events available'));
    }

    return RefreshIndicator(
      onRefresh: _loadEvents,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        itemCount: _events.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SingleEventListViewItem(
              eventModel: _events[index],
              onTap: () {
                EngagementPredictor.trackInteraction(
                  _events[index].id,
                  'view',
                ).catchError((e) {
                  if (kDebugMode) {
                    debugPrint('Error tracking engagement: $e');
                  }
                });
                RecommendationAnalytics.trackRecommendationInteraction(
                  eventId: _events[index].id,
                  interactionType: 'view',
                  position: index + 1,
                ).catchError((e) {
                  if (kDebugMode) {
                    debugPrint('Error tracking recommendation interaction: $e');
                  }
                });
              },
            ),
          );
        },
      ),
    );
  }
}

class UsersDefaultList extends StatefulWidget {
  const UsersDefaultList({super.key});

  @override
  State<UsersDefaultList> createState() => _UsersDefaultListState();
}

class _UsersDefaultListState extends State<UsersDefaultList> {
  List<CustomerModel> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await FirebaseFirestoreHelper().searchUsers(
        searchQuery: '',
        limit: 100,
      );

      setState(() {
        _users = users;
        _isLoading = false;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading users: $e');
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_users.isEmpty) {
      return const Center(child: Text('No users available'));
    }

    return RefreshIndicator(
      onRefresh: _loadUsers,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        itemCount: _users.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserProfileScreen(user: _users[index]),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 25,
                      backgroundColor: AppThemeColor.lightGrayColor,
                      backgroundImage: _users[index].profilePictureUrl != null
                          ? CachedNetworkImageProvider(
                              _users[index].profilePictureUrl!,
                            )
                          : null,
                      child: _users[index].profilePictureUrl == null
                          ? Text(
                              _users[index].name.isNotEmpty
                                  ? _users[index].name[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                color: AppThemeColor.darkBlueColor,
                                fontWeight: FontWeight.bold,
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
                            _users[index].name,
                            style: const TextStyle(
                              color: AppThemeColor.darkBlueColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Roboto',
                            ),
                          ),
                          if (_users[index].occupation != null &&
                              _users[index].occupation!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              _users[index].occupation!,
                              style: const TextStyle(
                                color: AppThemeColor.lightGrayColor,
                                fontSize: 14,
                                fontFamily: 'Roboto',
                              ),
                            ),
                          ],
                          if (_users[index].username != null &&
                              _users[index].username!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              '@${_users[index].username}',
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
                    const Icon(
                      Icons.arrow_forward_ios,
                      color: AppThemeColor.lightGrayColor,
                      size: 16,
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

class EventSearchDelegate extends SearchDelegate {
  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(
      icon: const Icon(Icons.clear),
      onPressed: () {
        query = '';
      },
    ),
  ];

  @override
  Widget buildResults(BuildContext context) {
    return FutureBuilder<List<EventModel>>(
      future: _searchEvents(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final events = snapshot.data ?? [];
        if (events.isEmpty) {
          return const Center(child: Text('No results found'));
        }
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          itemCount: events.length,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SingleEventListViewItem(
                eventModel: events[index],
                onTap: () {
                  EngagementPredictor.trackInteraction(
                    events[index].id,
                    'view',
                  ).catchError((e) {
                    if (kDebugMode) {
                      debugPrint('Error tracking engagement: $e');
                    }
                  });
                  RecommendationAnalytics.trackRecommendationInteraction(
                    eventId: events[index].id,
                    interactionType: 'view',
                    position: index + 1,
                  ).catchError((e) {
                    if (kDebugMode) {
                      debugPrint(
                        'Error tracking recommendation interaction: $e',
                      );
                    }
                  });
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          SingleEventScreen(eventModel: events[index]),
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

  @override
  Widget buildSuggestions(BuildContext context) {
    return buildResults(context);
  }

  Future<List<EventModel>> _searchEvents(String query) async {
    if (query.isEmpty) {
      return [];
    }

    try {
      Query firestoreQuery = FirebaseFirestore.instance
          .collection(EventModel.firebaseKey)
          .where('private', isEqualTo: false)
          .where(
            'selectedDateTime',
            isGreaterThan: DateTime.now().subtract(const Duration(hours: 3)),
          );

      QuerySnapshot snapshot = await firestoreQuery.get();

      List<EventModel> events = snapshot.docs
          .map((e) => EventModel.fromJson(e.data() as Map<String, dynamic>))
          .toList();

      // Filter events based on search query
      events = events.where((event) {
        final searchLower = query.toLowerCase();
        return event.title.toLowerCase().contains(searchLower) ||
            event.description.toLowerCase().contains(searchLower) ||
            event.location.toLowerCase().contains(searchLower) ||
            event.categories.any(
              (category) => category.toLowerCase().contains(searchLower),
            );
      }).toList();

      // Sort events (featured first, then by date)
      events.sort((a, b) {
        if (a.isFeatured && !b.isFeatured) return -1;
        if (!a.isFeatured && b.isFeatured) return 1;
        return a.selectedDateTime.compareTo(b.selectedDateTime);
      });

      return events;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error searching events: $e');
      }
      return [];
    }
  }
}

class UserSearchDelegate extends SearchDelegate {
  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(
      icon: const Icon(Icons.clear),
      onPressed: () {
        query = '';
      },
    ),
  ];

  @override
  Widget buildResults(BuildContext context) {
    return FutureBuilder<List<CustomerModel>>(
      future: _searchUsers(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final users = snapshot.data ?? [];
        if (users.isEmpty) {
          return const Center(child: Text('No results found'));
        }
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          itemCount: users.length,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserProfileScreen(user: users[index]),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 25,
                        backgroundColor: AppThemeColor.lightGrayColor,
                        backgroundImage: users[index].profilePictureUrl != null
                            ? CachedNetworkImageProvider(
                                users[index].profilePictureUrl!,
                              )
                            : null,
                        child: users[index].profilePictureUrl == null
                            ? Text(
                                users[index].name.isNotEmpty
                                    ? users[index].name[0].toUpperCase()
                                    : 'U',
                                style: const TextStyle(
                                  color: AppThemeColor.darkBlueColor,
                                  fontWeight: FontWeight.bold,
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
                              users[index].name,
                              style: const TextStyle(
                                color: AppThemeColor.darkBlueColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Roboto',
                              ),
                            ),
                            if (users[index].occupation != null &&
                                users[index].occupation!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                users[index].occupation!,
                                style: const TextStyle(
                                  color: AppThemeColor.lightGrayColor,
                                  fontSize: 14,
                                  fontFamily: 'Roboto',
                                ),
                              ),
                            ],
                            if (users[index].username != null &&
                                users[index].username!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '@${users[index].username}',
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
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: AppThemeColor.lightGrayColor,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return buildResults(context);
  }

  Future<List<CustomerModel>> _searchUsers(String query) async {
    if (query.isEmpty) {
      return [];
    }

    try {
      final users = await FirebaseFirestoreHelper().searchUsers(
        searchQuery: query,
        limit: 50,
      );

      return users;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error searching users: $e');
      }
      return [];
    }
  }
}
