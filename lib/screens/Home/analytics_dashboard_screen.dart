import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:attendus/firebase/ai_analytics_helper.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/Events/event_analytics_screen.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/dimensions.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:attendus/widgets/app_scaffold_wrapper.dart';
import 'package:attendus/Utils/app_app_bar_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AnalyticsDashboardScreen extends StatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  State<AnalyticsDashboardScreen> createState() =>
      _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState extends State<AnalyticsDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedDateFilter = 'all'; // 'all', 'week', 'month', 'year'
  List<EventModel> _userEvents = [];
  AIInsights? _globalAIInsights;
  bool _isLoadingAI = false;

  // Cache for instant display
  Map<String, dynamic>? _cachedAnalytics;
  bool _hasCachedData = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 &&
          _globalAIInsights == null &&
          !_isLoadingAI) {
        // Lazily compute AI insights only when AI tab is first opened
        _loadGlobalAIInsights();
      }
      if (_tabController.index == 3) {
        // Lazy load events list when Events tab is opened
        _loadUserEventsIfNeeded();
      }
    });
    _loadCachedAnalytics();
  }

  // Load cached analytics for instant display
  Future<void> _loadCachedAnalytics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        final cacheKey = 'user_analytics_${currentUser.uid}';
        final cachedJson = prefs.getString(cacheKey);
        if (cachedJson != null) {
          final cached = json.decode(cachedJson);
          // Check if cache is not too old (5 minutes)
          final cacheTime = DateTime.parse(
            cached['cacheTime'] ?? DateTime.now().toIso8601String(),
          );
          final now = DateTime.now();
          if (now.difference(cacheTime).inMinutes < 5) {
            setState(() {
              _cachedAnalytics = Map<String, dynamic>.from(cached['data']);
              _hasCachedData = true;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading cached analytics: $e');
    }
  }

  // Cache analytics data for instant display on next load
  Future<void> _cacheAnalytics(Map<String, dynamic> analytics) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        final cacheKey = 'user_analytics_${currentUser.uid}';
        final cacheData = {
          'data': analytics,
          'cacheTime': DateTime.now().toIso8601String(),
        };
        await prefs.setString(cacheKey, json.encode(cacheData));
      }
    } catch (e) {
      debugPrint('Error caching analytics: $e');
    }
  }

  // Lazy load events list when needed
  Future<void> _loadUserEventsIfNeeded() async {
    if (_userEvents.isNotEmpty) return;

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final eventsQuery = await FirebaseFirestore.instance
          .collection('Events')
          .where('customerUid', isEqualTo: currentUser.uid)
          .get();

      final events = eventsQuery.docs.map((doc) {
        return EventModel.fromJson(doc);
      }).toList();

      setState(() {
        _userEvents = events;
      });
    } catch (e) {
      debugPrint('Error loading user events: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadGlobalAIInsights() async {
    if (_userEvents.isEmpty) {
      await _loadUserEventsIfNeeded();
    }

    setState(() {
      _isLoadingAI = true;
    });

    try {
      final aiHelper = AIAnalyticsHelper();
      final insights = await aiHelper.generateGlobalAIInsights(_userEvents);

      setState(() {
        _globalAIInsights = insights;
        _isLoadingAI = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingAI = false;
      });
      debugPrint('Error loading global AI insights: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return AppScaffoldWrapper(
        selectedBottomNavIndex: 5,
        backgroundColor: AppThemeColor.backGroundColor,
        body: SafeArea(
          child: Center(
            child: Text(
              'Please log in to view analytics',
              style: TextStyle(
                fontSize: Dimensions.fontSizeLarge,
                color: AppThemeColor.darkBlueColor,
              ),
            ),
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('user_analytics')
          .doc(currentUser.uid)
          .snapshots(),
      builder: (context, snapshot) {
        // Show cached data immediately if available
        if (!snapshot.hasData && _hasCachedData && _cachedAnalytics != null) {
          return _buildDashboard(_cachedAnalytics!, isFromCache: true);
        }

        // Show loading skeleton on first load with no cache
        if (!snapshot.hasData && !_hasCachedData) {
          return _buildLoadingSkeleton();
        }

        // Handle errors
        if (snapshot.hasError) {
          return _buildErrorView(snapshot.error.toString());
        }

        // No data yet - show empty state
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return _buildEmptyState();
        }

        // Parse analytics data from Firestore
        final analyticsData = snapshot.data!.data() as Map<String, dynamic>;

        // Cache the new data
        _cacheAnalytics(analyticsData);

        // Build dashboard with real-time data
        return _buildDashboard(analyticsData, isFromCache: false);
      },
    );
  }

  Widget _buildLoadingSkeleton() {
    return AppScaffoldWrapper(
      selectedBottomNavIndex: 5,
      backgroundColor: AppThemeColor.backGroundColor,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: AppAppBarView.modernHeader(
                context: context,
                title: 'Analytics Dashboard',
                subtitle: 'Comprehensive insights across all your events',
                showBackButton: true,
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(Dimensions.paddingSizeDefault),
                child: Column(
                  children: [
                    // Shimmer skeleton for metrics
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      crossAxisSpacing: Dimensions.spaceSizedDefault,
                      mainAxisSpacing: Dimensions.spaceSizedDefault,
                      childAspectRatio: 1.2,
                      children: List.generate(
                        4,
                        (index) => Container(
                          decoration: BoxDecoration(
                            color: AppThemeColor.lightBlueColor,
                            borderRadius: BorderRadius.circular(
                              Dimensions.radiusLarge,
                            ),
                          ),
                          child: Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppThemeColor.darkBlueColor.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(String error) {
    return AppScaffoldWrapper(
      selectedBottomNavIndex: 5,
      backgroundColor: AppThemeColor.backGroundColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 80, color: Colors.red),
                const SizedBox(height: Dimensions.spaceSizedLarge),
                Text(
                  'Error Loading Analytics',
                  style: TextStyle(
                    fontSize: Dimensions.fontSizeOverLarge,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColor.darkBlueColor,
                  ),
                ),
                const SizedBox(height: Dimensions.spaceSizeSmall),
                Text(
                  error,
                  style: TextStyle(
                    fontSize: Dimensions.fontSizeLarge,
                    color: AppThemeColor.dullFontColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return AppScaffoldWrapper(
      selectedBottomNavIndex: 5,
      backgroundColor: AppThemeColor.backGroundColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(
                    Dimensions.paddingSizeLarge * 2,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppThemeColor.lightBlueColor,
                        AppThemeColor.lightBlueColor.withValues(alpha: 0.7),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(
                      Dimensions.radiusExtraLarge,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppThemeColor.darkBlueColor.withValues(
                          alpha: 0.1,
                        ),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.analytics_outlined,
                    size: 80,
                    color: AppThemeColor.darkBlueColor,
                  ),
                ),
                const SizedBox(height: Dimensions.spaceSizedLarge * 2),
                Text(
                  'No Events Found',
                  style: TextStyle(
                    fontSize: Dimensions.fontSizeOverLarge,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColor.darkBlueColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Dimensions.spaceSizeSmall),
                Text(
                  'Create your first event to start gathering\nanalytics and insights',
                  style: TextStyle(
                    fontSize: Dimensions.fontSizeLarge,
                    color: AppThemeColor.dullFontColor,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Dimensions.spaceSizedLarge * 2),
                ElevatedButton.icon(
                  onPressed: () {
                    // Navigate to create event screen
                    Navigator.pushNamed(context, '/create-event');
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Create Event'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppThemeColor.darkBlueColor,
                    foregroundColor: AppThemeColor.pureWhiteColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: Dimensions.paddingSizeLarge,
                      vertical: Dimensions.paddingSizeDefault,
                    ),
                    textStyle: TextStyle(
                      fontSize: Dimensions.fontSizeLarge,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusLarge,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard(
    Map<String, dynamic> analytics, {
    bool isFromCache = false,
  }) {
    return AppScaffoldWrapper(
      selectedBottomNavIndex: 5,
      backgroundColor: AppThemeColor.backGroundColor,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppAppBarView.modernHeader(
                          context: context,
                          title: 'Analytics Dashboard',
                          subtitle:
                              'Comprehensive insights across all your events',
                          showBackButton: true,
                          trailing: IconButton(
                            icon: const Icon(Icons.download_rounded),
                            onPressed: () => _exportAnalytics(analytics),
                            tooltip: 'Export Analytics',
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Cache indicator (only shown briefly)
                  if (isFromCache)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Dimensions.paddingSizeDefault,
                        vertical: Dimensions.paddingSizeSmall,
                      ),
                      margin: const EdgeInsets.symmetric(
                        horizontal: Dimensions.paddingSizeDefault,
                      ),
                      decoration: BoxDecoration(
                        color: AppThemeColor.lightBlueColor,
                        borderRadius: BorderRadius.circular(
                          Dimensions.radiusDefault,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cached,
                            size: 16,
                            color: AppThemeColor.darkBlueColor,
                          ),
                          const SizedBox(width: Dimensions.spaceSizeSmall),
                          Text(
                            'Refreshing...',
                            style: TextStyle(
                              fontSize: Dimensions.fontSizeSmall,
                              color: AppThemeColor.darkBlueColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(Dimensions.paddingSizeDefault),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Time Period Filter
                    _buildTimePeriodFilter(),

                    const SizedBox(height: Dimensions.spaceSizedLarge),

                    // Tab Bar
                    Container(
                      decoration: BoxDecoration(
                        color: AppThemeColor.lightBlueColor,
                        borderRadius: BorderRadius.circular(
                          Dimensions.radiusDefault,
                        ),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(
                          color: AppThemeColor.darkBlueColor,
                          borderRadius: BorderRadius.circular(
                            Dimensions.radiusDefault,
                          ),
                        ),
                        labelColor: AppThemeColor.pureWhiteColor,
                        unselectedLabelColor: AppThemeColor.darkBlueColor,
                        labelStyle: TextStyle(
                          fontSize: Dimensions.fontSizeDefault,
                          fontWeight: FontWeight.w600,
                        ),
                        tabs: const [
                          Tab(text: 'Overview'),
                          Tab(text: 'AI Insights'),
                          Tab(text: 'Trends'),
                          Tab(text: 'Events'),
                        ],
                      ),
                    ),

                    const SizedBox(height: Dimensions.spaceSizedLarge),

                    // Tab Views
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.65,
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildOverviewTab(analytics),
                          _buildAIInsightsTab(),
                          _buildTrendsTab(analytics),
                          _buildEventsTab(analytics),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePeriodFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Text(
            'Time Period',
            style: TextStyle(
              fontSize: Dimensions.fontSizeLarge,
              fontWeight: FontWeight.bold,
              color: AppThemeColor.darkBlueColor,
            ),
          ),
          const SizedBox(width: Dimensions.spaceSizedDefault),
          _buildFilterChip('All Time', 'all'),
          const SizedBox(width: Dimensions.spaceSizeSmall),
          _buildFilterChip('Week', 'week'),
          const SizedBox(width: Dimensions.spaceSizeSmall),
          _buildFilterChip('Month', 'month'),
          const SizedBox(width: Dimensions.spaceSizeSmall),
          _buildFilterChip('Year', 'year'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedDateFilter == value;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected
              ? AppThemeColor.pureWhiteColor
              : AppThemeColor.darkBlueColor,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          fontSize: Dimensions.fontSizeSmall,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedDateFilter = value;
        });
      },
      selectedColor: AppThemeColor.darkBlueColor,
      checkmarkColor: AppThemeColor.pureWhiteColor,
      backgroundColor: AppThemeColor.lightBlueColor,
      side: BorderSide(
        color: isSelected
            ? AppThemeColor.darkBlueColor
            : AppThemeColor.borderColor,
        width: 1.5,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
      ),
      elevation: isSelected ? 6 : 1,
      pressElevation: 8,
      padding: const EdgeInsets.symmetric(
        horizontal: Dimensions.paddingSizeDefault,
        vertical: Dimensions.paddingSizeSmall,
      ),
    );
  }

  Widget _buildOverviewTab(Map<String, dynamic> analytics) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Key Metrics Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      AppThemeColor.darkBlueColor,
                      AppThemeColor.dullBlueColor,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
                ),
                child: const Icon(
                  Icons.insights_rounded,
                  color: AppThemeColor.pureWhiteColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: Dimensions.spaceSizeSmall),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Key Metrics',
                      style: TextStyle(
                        fontSize: Dimensions.fontSizeLarge,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColor.darkBlueColor,
                      ),
                    ),
                    Text(
                      'Overview of your event performance',
                      style: TextStyle(
                        fontSize: Dimensions.fontSizeSmall,
                        color: AppThemeColor.dullFontColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: Dimensions.spaceSizedLarge),

          // Modern Analytics Cards Grid
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: Dimensions.spaceSizedDefault,
            mainAxisSpacing: Dimensions.spaceSizedDefault,
            childAspectRatio: 1.2,
            children: [
              _buildUltraModernAnalyticsCard(
                title: 'Total Events',
                value: '${analytics['totalEvents'] ?? 0}',
                icon: Icons.event_rounded,
                gradient: const LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                change: '+0',
              ),
              _buildUltraModernAnalyticsCard(
                title: 'Total Attendees',
                value: '${analytics['totalAttendees'] ?? 0}',
                icon: Icons.people_rounded,
                gradient: const LinearGradient(
                  colors: [Color(0xFF73ABE4), Color(0xFF4FC3F7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                change: '+0',
              ),
              _buildUltraModernAnalyticsCard(
                title: 'Avg Attendance',
                value: (analytics['averageAttendance'] ?? 0) > 0
                    ? '${(analytics['averageAttendance'] ?? 0).toStringAsFixed(1)}'
                    : '0.0',
                icon: Icons.trending_up_rounded,
                gradient: const LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                change: '+0',
              ),
              _buildUltraModernAnalyticsCard(
                title: 'Retention Rate',
                value:
                    '${(analytics['retentionRate'] ?? 0).toStringAsFixed(0)}%',
                icon: Icons.repeat_rounded,
                gradient: const LinearGradient(
                  colors: [Color(0xFFf093fb), Color(0xFFf5576c)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                change: '+0',
              ),
            ],
          ),

          const SizedBox(height: Dimensions.spaceSizedLarge),

          // Top Performing Event
          if (analytics['topPerformingEvent'] != null)
            _buildTopPerformingEventCard(analytics['topPerformingEvent']),
        ],
      ),
    );
  }

  Widget _buildUltraModernAnalyticsCard({
    required String title,
    required String value,
    required IconData icon,
    required Gradient gradient,
    required String change,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: gradient.colors.first.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background pattern
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Dimensions.paddingSizeDefault),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(
                          Dimensions.radiusDefault,
                        ),
                      ),
                      child: Icon(
                        icon,
                        color: AppThemeColor.pureWhiteColor,
                        size: 20,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        change,
                        style: TextStyle(
                          color: AppThemeColor.pureWhiteColor,
                          fontSize: Dimensions.fontSizeExtraSmall,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: Dimensions.fontSizeOverLarge * 1.2,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColor.pureWhiteColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: Dimensions.fontSizeSmall,
                        color: AppThemeColor.pureWhiteColor.withValues(
                          alpha: 0.9,
                        ),
                        fontWeight: FontWeight.w500,
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

  Widget _buildTopPerformingEventCard(Map<String, dynamic> topEvent) {
    return Container(
      padding: const EdgeInsets.all(Dimensions.paddingSizeDefault),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFDC830), Color(0xFFF37335)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFDC830).withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
            ),
            child: Icon(
              Icons.emoji_events_rounded,
              color: AppThemeColor.pureWhiteColor,
              size: 32,
            ),
          ),
          const SizedBox(width: Dimensions.spaceSizedDefault),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Top Performing Event',
                  style: TextStyle(
                    fontSize: Dimensions.fontSizeSmall,
                    color: AppThemeColor.pureWhiteColor.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  topEvent['title'] ?? 'Unknown Event',
                  style: TextStyle(
                    fontSize: Dimensions.fontSizeLarge,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColor.pureWhiteColor,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${topEvent['attendees'] ?? 0} attendees',
                  style: TextStyle(
                    fontSize: Dimensions.fontSizeDefault,
                    color: AppThemeColor.pureWhiteColor.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAIInsightsTab() {
    if (_isLoadingAI) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                AppThemeColor.darkBlueColor,
              ),
            ),
            const SizedBox(height: Dimensions.spaceSizedDefault),
            Text(
              'Generating AI insights...',
              style: TextStyle(
                fontSize: Dimensions.fontSizeLarge,
                color: AppThemeColor.dullFontColor,
              ),
            ),
          ],
        ),
      );
    }

    if (_globalAIInsights == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.psychology_outlined,
              size: 80,
              color: AppThemeColor.darkBlueColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: Dimensions.spaceSizedDefault),
            Text(
              'AI Insights',
              style: TextStyle(
                fontSize: Dimensions.fontSizeOverLarge,
                fontWeight: FontWeight.bold,
                color: AppThemeColor.darkBlueColor,
              ),
            ),
            const SizedBox(height: Dimensions.spaceSizeSmall),
            Text(
              'Get AI-powered recommendations\nto improve your events',
              style: TextStyle(
                fontSize: Dimensions.fontSizeLarge,
                color: AppThemeColor.dullFontColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_globalAIInsights!.naturalSummary != null)
            _buildAIInsightCard(
              icon: Icons.lightbulb_outline,
              title: 'Summary',
              content: _globalAIInsights!.naturalSummary!,
              color: const Color(0xFF667EEA),
            ),
          const SizedBox(height: Dimensions.spaceSizedDefault),
          if (_globalAIInsights!.strategyRecommendations != null &&
              _globalAIInsights!.strategyRecommendations!.isNotEmpty)
            _buildAIInsightCard(
              icon: Icons.tips_and_updates,
              title: 'Recommendations',
              content: _globalAIInsights!.strategyRecommendations!
                  .map((rec) => '• ${rec['recommendation'] ?? ''}')
                  .join('\n'),
              color: const Color(0xFF4FC3F7),
            ),
          const SizedBox(height: Dimensions.spaceSizedDefault),
          if (_globalAIInsights!.anomalies != null &&
              _globalAIInsights!.anomalies!.isNotEmpty)
            _buildAIInsightCard(
              icon: Icons.warning_amber_rounded,
              title: 'Unusual Patterns',
              content: _globalAIInsights!.anomalies!
                  .map((anomaly) => '• ${anomaly['description'] ?? ''}')
                  .join('\n'),
              color: const Color(0xFFF5576C),
            ),
        ],
      ),
    );
  }

  Widget _buildAIInsightCard({
    required IconData icon,
    required String title,
    required String content,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(Dimensions.paddingSizeDefault),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
                ),
                child: Icon(
                  icon,
                  color: AppThemeColor.pureWhiteColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: Dimensions.spaceSizedDefault),
              Text(
                title,
                style: TextStyle(
                  fontSize: Dimensions.fontSizeLarge,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: Dimensions.spaceSizedDefault),
          Text(
            content,
            style: TextStyle(
              fontSize: Dimensions.fontSizeDefault,
              color: AppThemeColor.darkBlueColor,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendsTab(Map<String, dynamic> analytics) {
    final monthlyTrends = Map<String, dynamic>.from(
      analytics['monthlyTrends'] ?? {},
    );
    final eventCategories = Map<String, int>.from(
      analytics['eventCategories'] ?? {},
    );

    if (monthlyTrends.isEmpty && eventCategories.isEmpty) {
      return Center(
        child: Text(
          'Not enough data for trends analysis',
          style: TextStyle(
            fontSize: Dimensions.fontSizeLarge,
            color: AppThemeColor.dullFontColor,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (monthlyTrends.isNotEmpty) ...[
            Text(
              'Monthly Attendance Trends',
              style: TextStyle(
                fontSize: Dimensions.fontSizeLarge,
                fontWeight: FontWeight.bold,
                color: AppThemeColor.darkBlueColor,
              ),
            ),
            const SizedBox(height: Dimensions.spaceSizedDefault),
            _buildMonthlyTrendsChart(monthlyTrends),
            const SizedBox(height: Dimensions.spaceSizedLarge),
          ],
          if (eventCategories.isNotEmpty) ...[
            Text(
              'Event Categories',
              style: TextStyle(
                fontSize: Dimensions.fontSizeLarge,
                fontWeight: FontWeight.bold,
                color: AppThemeColor.darkBlueColor,
              ),
            ),
            const SizedBox(height: Dimensions.spaceSizedDefault),
            _buildCategoriesChart(eventCategories),
          ],
        ],
      ),
    );
  }

  Widget _buildMonthlyTrendsChart(Map<String, dynamic> monthlyTrends) {
    // Sort by month
    final sortedEntries = monthlyTrends.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (sortedEntries.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: Text(
          'No trend data available',
          style: TextStyle(color: AppThemeColor.dullFontColor),
        ),
      );
    }

    return Container(
      height: 250,
      padding: const EdgeInsets.all(Dimensions.paddingSizeDefault),
      decoration: BoxDecoration(
        color: AppThemeColor.lightBlueColor,
        borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 40),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() >= 0 &&
                      value.toInt() < sortedEntries.length) {
                    final month = sortedEntries[value.toInt()].key.split(
                      '-',
                    )[1];
                    return Text(
                      month,
                      style: TextStyle(
                        fontSize: Dimensions.fontSizeExtraSmall,
                        color: AppThemeColor.dullFontColor,
                      ),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: sortedEntries.asMap().entries.map((entry) {
                return FlSpot(
                  entry.key.toDouble(),
                  (entry.value.value as num).toDouble(),
                );
              }).toList(),
              isCurved: true,
              color: AppThemeColor.darkBlueColor,
              barWidth: 3,
              dotData: FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: AppThemeColor.darkBlueColor.withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesChart(Map<String, int> eventCategories) {
    if (eventCategories.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: Text(
          'No category data available',
          style: TextStyle(color: AppThemeColor.dullFontColor),
        ),
      );
    }

    final colors = [
      const Color(0xFF667EEA),
      const Color(0xFF4FC3F7),
      const Color(0xFFF5576C),
      const Color(0xFFFDC830),
      const Color(0xFF764BA2),
    ];

    return Container(
      height: 250,
      padding: const EdgeInsets.all(Dimensions.paddingSizeDefault),
      decoration: BoxDecoration(
        color: AppThemeColor.lightBlueColor,
        borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
      ),
      child: Row(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sections: eventCategories.entries.toList().asMap().entries.map((
                  entry,
                ) {
                  final index = entry.key;
                  final category = entry.value;
                  final color = colors[index % colors.length];
                  return PieChartSectionData(
                    value: category.value.toDouble(),
                    title: '${category.value}',
                    color: color,
                    radius: 60,
                    titleStyle: TextStyle(
                      fontSize: Dimensions.fontSizeDefault,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColor.pureWhiteColor,
                    ),
                  );
                }).toList(),
                sectionsSpace: 2,
                centerSpaceRadius: 40,
              ),
            ),
          ),
          const SizedBox(width: Dimensions.spaceSizedDefault),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: eventCategories.entries.toList().asMap().entries.map((
              entry,
            ) {
              final index = entry.key;
              final category = entry.value;
              final color = colors[index % colors.length];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      category.key,
                      style: TextStyle(
                        fontSize: Dimensions.fontSizeSmall,
                        color: AppThemeColor.darkBlueColor,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsTab(Map<String, dynamic> analytics) {
    final eventAnalytics = Map<String, dynamic>.from(
      analytics['eventAnalytics'] ?? {},
    );

    if (eventAnalytics.isEmpty) {
      return Center(
        child: Text(
          'No events to display',
          style: TextStyle(
            fontSize: Dimensions.fontSizeLarge,
            color: AppThemeColor.dullFontColor,
          ),
        ),
      );
    }

    // Lazy load events list if needed
    if (_userEvents.isEmpty) {
      _loadUserEventsIfNeeded();
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(
            AppThemeColor.darkBlueColor,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _userEvents.length,
      itemBuilder: (context, index) {
        final event = _userEvents[index];
        final analytics =
            eventAnalytics[event.id] ?? {'attendees': 0, 'repeatAttendees': 0};

        return Container(
          margin: const EdgeInsets.only(bottom: Dimensions.spaceSizedDefault),
          decoration: BoxDecoration(
            color: AppThemeColor.lightBlueColor,
            borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(Dimensions.paddingSizeDefault),
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                ),
                borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
              ),
              child: const Icon(
                Icons.event,
                color: AppThemeColor.pureWhiteColor,
              ),
            ),
            title: Text(
              event.title,
              style: TextStyle(
                fontSize: Dimensions.fontSizeLarge,
                fontWeight: FontWeight.bold,
                color: AppThemeColor.darkBlueColor,
              ),
            ),
            subtitle: Text(
              '${analytics['attendees']} attendees • ${DateFormat('MMM d, y').format(event.selectedDateTime)}',
              style: TextStyle(
                fontSize: Dimensions.fontSizeDefault,
                color: AppThemeColor.dullFontColor,
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.arrow_forward_ios),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        EventAnalyticsScreen(eventId: event.id),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportAnalytics(Map<String, dynamic> analytics) async {
    try {
      // Create a formatted text version of analytics
      final buffer = StringBuffer();
      buffer.writeln('=== Analytics Dashboard Export ===');
      buffer.writeln(
        'Exported: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
      );
      buffer.writeln('');
      buffer.writeln('Key Metrics:');
      buffer.writeln('- Total Events: ${analytics['totalEvents'] ?? 0}');
      buffer.writeln('- Total Attendees: ${analytics['totalAttendees'] ?? 0}');
      buffer.writeln(
        '- Average Attendance: ${(analytics['averageAttendance'] ?? 0).toStringAsFixed(1)}',
      );
      buffer.writeln(
        '- Retention Rate: ${(analytics['retentionRate'] ?? 0).toStringAsFixed(1)}%',
      );
      buffer.writeln('');

      if (analytics['topPerformingEvent'] != null) {
        final topEvent = analytics['topPerformingEvent'];
        buffer.writeln('Top Performing Event:');
        buffer.writeln('- Title: ${topEvent['title']}');
        buffer.writeln('- Attendees: ${topEvent['attendees']}');
        buffer.writeln('');
      }

      // Save to temp file and share
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/analytics_export.txt');
      await file.writeAsString(buffer.toString());

      await Share.shareXFiles([
        XFile(file.path),
      ], subject: 'Analytics Dashboard Export');

      if (mounted) {
        ShowToast().showNormalToast(msg: 'Analytics exported successfully');
      }
    } catch (e) {
      debugPrint('Error exporting analytics: $e');
      if (mounted) {
        ShowToast().showNormalToast(msg: 'Failed to export analytics');
      }
    }
  }
}
