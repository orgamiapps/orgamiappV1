import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:attendus/screens/Events/Widget/single_event_list_view_item.dart';
import 'package:attendus/screens/Events/single_event_screen.dart';
import 'package:attendus/screens/MyProfile/user_profile_screen.dart';
import 'package:attendus/controller/customer_controller.dart';

import 'package:attendus/firebase/engagement_predictor.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/firebase/recommendation_analytics.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/models/event_model.dart';
import 'package:shimmer/shimmer.dart';
import 'package:geolocator/geolocator.dart';
import 'package:attendus/Services/onnx_nlp_service.dart';

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
    _tabController = TabController(length: 3, vsync: this);
    // Keep the search bar hint and UI in sync when swiping between tabs
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
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
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  EventsList(searchQuery: _searchQuery),
                  OrgEventsList(searchQuery: _searchQuery),
                  UsersList(searchQuery: _searchQuery),
                ],
              ),
            ),
          ],
        ),
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
            size: 20,
          ),
        ),
      ),
      title: const Text(
        'Search',
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
    final bool isAiActive =
        _tabController.index == 0 && _searchQuery.isNotEmpty;

    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        MediaQuery.of(context).size.width * 0.05, // 5% of screen width
        8,
        MediaQuery.of(context).size.width * 0.05, // 5% of screen width
        16,
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _searchController.text.isEmpty
                    ? const Color(0xFFE2E8F0)
                    : isAiActive
                    ? const Color(0xFF6366F1)
                    : const Color(0xFF667EEA),
                width: 1.5,
              ),
              boxShadow: isAiActive
                  ? [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                textSelectionTheme: const TextSelectionThemeData(
                  cursorColor: Colors.black,
                  selectionColor: Color(0x33000000),
                  selectionHandleColor: Colors.black,
                ),
              ),
              child: TextField(
                controller: _searchController,
                cursorColor: Colors.black,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 16,
                  ),
                  border: InputBorder.none,
                  hintText: _tabController.index == 2
                      ? 'Find users by name or username...'
                      : _tabController.index == 0
                      ? 'Search events by name, category, date, or near you...'
                      : 'Find events by name, location, or category...',
                  hintStyle: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 15,
                    fontFamily: 'Roboto',
                  ),
                  prefixIcon: Icon(
                    isAiActive ? Icons.auto_awesome_rounded : Icons.search,
                    color: isAiActive
                        ? const Color(0xFF6366F1)
                        : const Color(0xFF64748B),
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
                  color: Colors.black,
                  fontSize: 15,
                  fontFamily: 'Roboto',
                ),
              ),
            ),
          ),
          if (isAiActive)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF6366F1).withValues(alpha: 0.1),
                    const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.4),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Smart Search Active',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6366F1),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.psychology_rounded,
                    size: 14,
                    color: Color(0xFF8B5CF6),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: const Color(0xFF667EEA),
          borderRadius: BorderRadius.circular(25),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
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
          Tab(text: 'Public'),
          Tab(text: 'Private'),
          Tab(text: 'Users'),
        ],
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
  bool _usingAi = false;
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
        _usingAi = false;
        _filteredEvents = List.from(_allEvents);
      } else {
        // Use hybrid AI search for non-empty queries
        _searchWithHybridAi(widget.searchQuery);
      }
    });
  }

  Future<void> _searchWithHybridAi(String query) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _usingAi = true;
    });

    try {
      // HYBRID SEARCH STRATEGY:
      // 1. Instant exact name matching (0ms latency)
      // 2. AI semantic search for complex queries
      // 3. Intelligent result merging with deduplication
      // 4. Smart ranking: exact matches first, then AI results

      final exactMatches = _getExactNameMatches(query);
      final isSimpleQuery = _isSimpleQuery(query);

      // For simple queries with exact matches, show them immediately
      if (exactMatches.isNotEmpty && isSimpleQuery) {
        // Show exact matches first, then enhance with AI in background
        if (!mounted) return;
        setState(() {
          _filteredEvents = exactMatches;
          _isLoading = false;
        });

        // Enhance with AI results in background
        _enhanceWithAiResults(query, exactMatches);
        return;
      }

      // For complex natural language queries, use AI with exact match boost
      final aiResults = await _getAiResults(query);
      final combinedResults = _mergeSearchResults(
        exactMatches,
        aiResults,
        query,
      );

      if (!mounted) return;
      setState(() {
        _filteredEvents = combinedResults.isNotEmpty
            ? combinedResults
            : _fallbackFilter(query);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _filteredEvents = _fallbackFilter(query);
        _isLoading = false;
        _usingAi = false;
      });
    }
  }

  /// Get events that exactly match the query in name/title
  List<EventModel> _getExactNameMatches(String query) {
    final queryLower = query.toLowerCase().trim();
    if (queryLower.length < 2) return [];

    final matches = <EventModel>[];
    final partialMatches = <EventModel>[];

    for (final event in _allEvents) {
      final titleLower = event.title.toLowerCase();
      final descriptionLower = event.description.toLowerCase();

      // Priority 1: Exact title match
      if (titleLower == queryLower) {
        matches.insert(0, event);
        continue;
      }

      // Priority 2: Title starts with query (great for autocomplete)
      if (titleLower.startsWith(queryLower)) {
        matches.add(event);
        continue;
      }

      // Priority 3: Title contains query as whole word
      if (_containsWholeWord(titleLower, queryLower)) {
        matches.add(event);
        continue;
      }

      // Priority 4: Description contains query as whole word
      if (_containsWholeWord(descriptionLower, queryLower)) {
        partialMatches.add(event);
        continue;
      }

      // Priority 5: Partial matches in title
      if (titleLower.contains(queryLower)) {
        partialMatches.add(event);
      }
    }

    // Return exact matches first, then partial matches
    return [...matches, ...partialMatches.take(10)];
  }

  /// Check if text contains query as whole word
  bool _containsWholeWord(String text, String query) {
    return text.contains(' $query ') ||
        text.startsWith('$query ') ||
        text.endsWith(' $query') ||
        text == query;
  }

  /// Determine if query is simple (likely looking for specific event name)
  bool _isSimpleQuery(String query) {
    final words = query.trim().split(RegExp(r'\s+'));

    // Single word or short phrase without natural language indicators
    if (words.length <= 2) return true;

    // Contains natural language patterns = complex AI query
    final naturalLanguagePatterns = [
      'find',
      'search',
      'show',
      'get',
      'looking for',
      'i want',
      'near me',
      'close by',
      'around me',
      'nearby',
      'local',
      'this weekend',
      'tomorrow',
      'today',
      'next week',
      'tonight',
      'within',
      'events',
      'event',
      'happening',
      'going on',
    ];

    final queryLower = query.toLowerCase();
    return !naturalLanguagePatterns.any(
      (pattern) => queryLower.contains(pattern),
    );
  }

  /// Enhance exact matches with AI results in background
  Future<void> _enhanceWithAiResults(
    String query,
    List<EventModel> exactMatches,
  ) async {
    try {
      final aiResults = await _getAiResults(query);
      final enhanced = _mergeSearchResults(exactMatches, aiResults, query);

      // Only update if results are actually better (more results)
      if (mounted && enhanced.length > exactMatches.length) {
        setState(() {
          _filteredEvents = enhanced;
        });
      }
    } catch (e) {
      // Silent fail - exact matches are already shown
    }
  }

  /// Get AI-powered search results
  Future<List<EventModel>> _getAiResults(String query) async {
    try {
      final onnxService = OnnxNlpService.instance;
      await onnxService.initialize();

      double? lat;
      double? lng;

      // Try to get current location for proximity search
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
          ),
        ).timeout(const Duration(seconds: 3));
        lat = position.latitude;
        lng = position.longitude;
      } catch (_) {
        // Location not available, continue without it
      }

      // Parse query with ONNX DistilBERT model
      final intent = await onnxService.parseQuery(query);

      // Try SQLite cache first
      final cachedResults = await onnxService.queryEvents(
        intent: intent,
        userLat: lat,
        userLng: lng,
        limit: 25, // Leave room for exact matches
      );

      if (cachedResults.isNotEmpty) {
        return cachedResults.map((data) => EventModel.fromJson(data)).toList();
      }

      // Fall back to Firestore with AI intent
      final helper = FirebaseFirestoreHelper();
      final aiEvents = await helper.aiSearchEvents(
        query: query,
        latitude: lat,
        longitude: lng,
        limit: 25,
      );

      // Cache results for future searches
      if (aiEvents.isNotEmpty) {
        final eventsData = aiEvents.map((e) => e.toJson()).toList();
        await onnxService.cacheEvents(eventsData);
      }

      return aiEvents;
    } catch (e) {
      return [];
    }
  }

  /// Intelligently merge exact matches and AI results
  List<EventModel> _mergeSearchResults(
    List<EventModel> exactMatches,
    List<EventModel> aiResults,
    String query,
  ) {
    final resultMap = <String, EventModel>{};
    final finalResults = <EventModel>[];

    // Add exact matches first (highest priority)
    for (final event in exactMatches) {
      if (!resultMap.containsKey(event.id)) {
        resultMap[event.id] = event;
        finalResults.add(event);
      }
    }

    // Add AI results that aren't duplicates
    for (final event in aiResults) {
      if (!resultMap.containsKey(event.id)) {
        resultMap[event.id] = event;
        finalResults.add(event);
      }
    }

    // Sort by relevance: exact matches stay at top, AI results by date
    final exactCount = exactMatches.length;
    if (finalResults.length > exactCount) {
      final exactPart = finalResults.take(exactCount).toList();
      final aiPart = finalResults.skip(exactCount).toList();

      // Sort AI results by date (upcoming first)
      aiPart.sort((a, b) => a.selectedDateTime.compareTo(b.selectedDateTime));

      return [...exactPart, ...aiPart].take(50).toList();
    }

    return finalResults.take(50).toList();
  }

  /// Get contextual empty state message
  String _getSmartEmptyMessage(String query) {
    if (_isSimpleQuery(query)) {
      return 'No events found matching "$query". Try a different event name or use natural language like "find concerts near me"';
    } else {
      return 'Smart search analyzed "$query" but found no matching events. Try different keywords or check back later';
    }
  }

  List<EventModel> _fallbackFilter(String q) {
    final searchLower = q.toLowerCase();
    return _allEvents.where((event) {
      return event.title.toLowerCase().contains(searchLower) ||
          event.description.toLowerCase().contains(searchLower) ||
          event.location.toLowerCase().contains(searchLower) ||
          event.categories.any(
            (category) => category.toLowerCase().contains(searchLower),
          );
    }).toList();
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
      // Ensure each event includes its document ID even if the field isn't stored
      List<EventModel> events = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = data['id'] ?? doc.id;
        return EventModel.fromJson(data);
      }).toList();

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
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMoreEvents() async {
    if (_isLoading || !_hasMore || widget.searchQuery.isNotEmpty) return;

    setState(() => _isLoading = true);

    try {
      final lastEvent = _allEvents.last;
      Query query = FirebaseFirestore.instance
          .collection(EventModel.firebaseKey)
          .where('private', isEqualTo: false)
          .where(
            'selectedDateTime',
            isGreaterThan: DateTime.now().subtract(const Duration(hours: 3)),
          )
          .orderBy('selectedDateTime')
          .startAfter([lastEvent.selectedDateTime])
          .limit(_pageSize);

      QuerySnapshot snapshot = await query.get();
      List<EventModel> newEvents = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = data['id'] ?? doc.id;
        return EventModel.fromJson(data);
      }).toList();

      if (mounted) {
        setState(() {
          _allEvents.addAll(newEvents);
          _filteredEvents = List.from(_allEvents);
          _hasMore = newEvents.length == _pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshEvents() async {
    _allEvents.clear();
    _filteredEvents.clear();
    _hasMore = true;
    await _loadEvents();
    _filterEvents();
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
                gradient: _usingAi
                    ? LinearGradient(
                        colors: [
                          const Color(0xFF6366F1).withValues(alpha: 0.15),
                          const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: !_usingAi
                    ? const Color(0xFF667EEA).withValues(alpha: 0.1)
                    : null,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _usingAi ? Icons.psychology_rounded : Icons.search_off_rounded,
                size: 60,
                color: _usingAi
                    ? const Color(0xFF6366F1)
                    : const Color(0xFF667EEA),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.searchQuery.isEmpty
                  ? 'No Events Available'
                  : (_usingAi
                        ? '🤖 Smart Search: No Matching Events'
                        : 'No Events Found'),
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
                  : (_usingAi
                        ? _getSmartEmptyMessage(widget.searchQuery)
                        : 'Try adjusting your search terms'),
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF64748B),
                fontFamily: 'Roboto',
              ),
              textAlign: TextAlign.center,
            ),
            if (_usingAi && widget.searchQuery.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: const [
                    Text(
                      '💡 Smart Search Examples:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '"find a book club near me"\n"concert this weekend"\n"tech workshop tomorrow"',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
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

// Rest of the file remains the same for OrgEventsList and UsersList classes
// [The rest of the original file content would go here...]
class OrgEventsList extends StatefulWidget {
  final String searchQuery;
  const OrgEventsList({super.key, required this.searchQuery});

  @override
  State<OrgEventsList> createState() => _OrgEventsListState();
}

class _OrgEventsListState extends State<OrgEventsList>
    with AutomaticKeepAliveClientMixin {
  List<EventModel> _allEvents = [];
  List<EventModel> _filteredEvents = [];
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadOrgEvents();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant OrgEventsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _filterEvents();
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

  // AI search not used in Org events list

  // Fallback filter removed (no longer referenced)

  Future<void> _loadOrgEvents() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        if (mounted) {
          setState(() {
            _allEvents = [];
            _filteredEvents = [];
            _isLoading = false;
          });
        }
        return;
      }

      // Fetch organization IDs where user is an approved member.
      // Query by stored field userId (new schema)
      final qByField = await FirebaseFirestore.instance
          .collectionGroup('Members')
          .where('userId', isEqualTo: uid)
          .where('status', isEqualTo: 'approved')
          .limit(100)
          .get();

      // Also query by documentId == uid to support legacy docs without userId field
      final qByDocId = await FirebaseFirestore.instance
          .collectionGroup('Members')
          .where(FieldPath.documentId, isEqualTo: uid)
          .limit(100)
          .get();

      // Resolve organization IDs robustly: prefer field, fall back to parent path (legacy docs)
      final Set<String> orgIds = <String>{};
      for (final d in [...qByField.docs, ...qByDocId.docs]) {
        final data = d.data();
        final String? fromField = data['organizationId']?.toString();
        final String? fromPath = d.reference.parent.parent?.id;
        final String? resolved = (fromField != null && fromField.isNotEmpty)
            ? fromField
            : fromPath;
        if (resolved != null && resolved.isNotEmpty) {
          orgIds.add(resolved);
        }
      }

      List<EventModel> events = [];

      // Query events created by these orgs (via organizationId field)
      if (orgIds.isNotEmpty) {
        final List<String> ids = orgIds.toList();
        for (int i = 0; i < ids.length; i += 10) {
          final chunk = ids.sublist(
            i,
            i + 10 > ids.length ? ids.length : i + 10,
          );
          // Avoid composite index requirement by fetching by organization only
          // and then filtering/sorting on the client.
          final qs = await FirebaseFirestore.instance
              .collection(EventModel.firebaseKey)
              .where('organizationId', whereIn: chunk)
              .limit(100)
              .get();
          final chunkEvents = qs.docs.map((doc) {
            final Map<String, dynamic> data = doc.data();
            data['id'] = data['id'] ?? doc.id;
            return EventModel.fromJson(data);
          }).toList();
          events.addAll(chunkEvents);
        }
      }

      // Also include events where the user is the creator/admin
      final createdQs = await FirebaseFirestore.instance
          .collection(EventModel.firebaseKey)
          .where('customerUid', isEqualTo: uid)
          .limit(100)
          .get();
      events.addAll(
        createdQs.docs.map((doc) {
          final Map<String, dynamic> data = doc.data();
          data['id'] = data['id'] ?? doc.id;
          return EventModel.fromJson(data);
        }),
      );

      // Filter to upcoming (with a small grace window) and then sort
      final DateTime threshold = DateTime.now().subtract(
        const Duration(hours: 3),
      );
      events = events
          .where((e) => e.selectedDateTime.isAfter(threshold))
          .toList();

      // De-duplicate by id
      final Map<String, EventModel> idToEvent = {
        for (final e in events) e.id: e,
      };
      final List<EventModel> unique = idToEvent.values.toList();

      unique.sort((a, b) {
        if (a.isFeatured && !b.isFeatured) return -1;
        if (!a.isFeatured && b.isFeatured) return 1;
        return a.selectedDateTime.compareTo(b.selectedDateTime);
      });

      if (mounted) {
        setState(() {
          _allEvents = unique;
          _filteredEvents = List.from(_allEvents);
          _isLoading = false;
        });
        _filterEvents();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refresh() async {
    await _loadOrgEvents();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading && _allEvents.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF667EEA)),
      );
    }

    if (_filteredEvents.isEmpty && !_isLoading) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: const Color(0xFF667EEA),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _filteredEvents.length,
        itemBuilder: (context, index) {
          final event = _filteredEvents[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SingleEventListViewItem(
              eventModel: event,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SingleEventScreen(eventModel: event),
                  ),
                );
              },
            ),
          );
        },
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
          children: const [
            SizedBox(height: 100),
            Icon(Icons.event_busy, size: 60, color: Color(0xFF667EEA)),
            SizedBox(height: 24),
            Text(
              'No Group Events Available',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
                fontFamily: 'Roboto',
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Create or join a group to see its events here',
              style: TextStyle(
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

// Duplicate _EventsListState removed to avoid class redefinition and ensure
// the hybrid AI + exact name matching implementation is the single source of truth.

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
              builder: (context) => UserProfileScreen(
                user: user,
                isOwnProfile:
                    CustomerController.logeInCustomer?.uid == user.uid,
              ),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
