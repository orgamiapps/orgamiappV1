import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:orgami/firebase/ai_analytics_helper.dart';
import 'package:orgami/models/event_model.dart';
import 'package:orgami/screens/Events/event_analytics_screen.dart';
import 'package:orgami/Utils/colors.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:orgami/Utils/router.dart';
import 'package:flutter/foundation.dart';
import 'package:orgami/Utils/toast.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

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
  bool _isLoading = false;
  List<EventModel> _userEvents = [];
  Map<String, dynamic> _aggregatedAnalytics = {};
  AIInsights? _globalAIInsights;
  bool _isLoadingAI = false;
  bool _hasEvents = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadUserEvents();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserEvents() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        setState(() {
          _isLoading = false;
          _hasEvents = false;
        });
        return;
      }

      // Get all events created by the user
      final eventsQuery = await FirebaseFirestore.instance
          .collection('Events')
          .where('customerUid', isEqualTo: currentUser.uid)
          .get();

      final events = eventsQuery.docs.map((doc) {
        return EventModel.fromJson(doc);
      }).toList();

      setState(() {
        _userEvents = events;
        _hasEvents = events.isNotEmpty;
        _isLoading = false;
      });

      if (events.isNotEmpty) {
        _loadAggregatedAnalytics();
        _loadGlobalAIInsights();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasEvents = false;
      });
      debugPrint('Error loading user events: $e');
    }
  }

  Future<void> _loadAggregatedAnalytics() async {
    try {
      final analytics = <String, dynamic>{
        'totalEvents': _userEvents.length,
        'totalAttendees': 0,
        'totalRevenue': 0.0,
        'averageAttendance': 0.0,
        'topPerformingEvent': null,
        'eventCategories': <String, int>{},
        'monthlyTrends': <String, int>{},
        'attendanceByEvent': <String, int>{},
        'repeatAttendees': 0,
        'dropoutRate': 0.0,
        'engagementScore': 0.0,
      };

      // Aggregate data from all events
      for (final event in _userEvents) {
        try {
          final analyticsDoc = await FirebaseFirestore.instance
              .collection('event_analytics')
              .doc(event.id)
              .get();

          if (analyticsDoc.exists) {
            final eventData = analyticsDoc.data() as Map<String, dynamic>;
            final attendees = eventData['totalAttendees'] ?? 0;
            final repeatAttendees = eventData['repeatAttendees'] ?? 0;

            analytics['totalAttendees'] += attendees;
            analytics['repeatAttendees'] += repeatAttendees;
            analytics['attendanceByEvent'][event.title] = attendees;

            // Track event categories
            final category = event.categories.isNotEmpty
                ? event.categories.first
                : 'Other';
            analytics['eventCategories'][category] =
                (analytics['eventCategories'][category] ?? 0) + 1;

            // Track monthly trends
            final monthKey = DateFormat(
              'yyyy-MM',
            ).format(event.selectedDateTime);
            analytics['monthlyTrends'][monthKey] =
                (analytics['monthlyTrends'][monthKey] ?? 0) + attendees;

            // Find top performing event
            if (analytics['topPerformingEvent'] == null ||
                attendees >
                    (analytics['topPerformingEvent']['attendees'] ?? 0)) {
              analytics['topPerformingEvent'] = {
                'title': event.title,
                'attendees': attendees,
                'date': event.selectedDateTime,
                'id': event.id,
              };
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Error loading analytics for event ${event.id}: $e');
          }
        }
      }

      // Calculate averages and rates
      if (analytics['totalEvents'] > 0) {
        analytics['averageAttendance'] =
            analytics['totalAttendees'] / analytics['totalEvents'];

        if (analytics['totalAttendees'] > 0) {
          analytics['dropoutRate'] =
              ((analytics['totalAttendees'] - analytics['repeatAttendees']) /
                  analytics['totalAttendees']) *
              100;

          analytics['engagementScore'] =
              (analytics['repeatAttendees'] / analytics['totalAttendees']) *
              100;
        }
      }

      setState(() {
        _aggregatedAnalytics = analytics;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading aggregated analytics: $e');
      }
    }
  }

  Future<void> _loadGlobalAIInsights() async {
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
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppThemeColor.backGroundColor,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
                  decoration: BoxDecoration(
                    color: AppThemeColor.lightBlueColor,
                    borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
                  ),
                  child: const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppThemeColor.darkBlueColor,
                    ),
                  ),
                ),
                const SizedBox(height: Dimensions.spaceSizedLarge),
                Text(
                  'Loading your analytics...',
                  style: TextStyle(
                    fontSize: Dimensions.fontSizeLarge,
                    color: AppThemeColor.darkBlueColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_hasEvents) {
      return Scaffold(
        backgroundColor: AppThemeColor.backGroundColor,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
                    decoration: BoxDecoration(
                      color: AppThemeColor.lightBlueColor,
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusLarge,
                      ),
                    ),
                    child: Icon(
                      Icons.analytics_outlined,
                      size: 64,
                      color: AppThemeColor.dullIconColor,
                    ),
                  ),
                  const SizedBox(height: Dimensions.spaceSizedLarge),
                  Text(
                    'No Events Found',
                    style: TextStyle(
                      fontSize: Dimensions.fontSizeExtraLarge,
                      fontWeight: FontWeight.w600,
                      color: AppThemeColor.darkBlueColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Dimensions.spaceSizeSmall),
                  Text(
                    'Create your first event to start gathering analytics and insights',
                    style: TextStyle(
                      fontSize: Dimensions.fontSizeDefault,
                      color: AppThemeColor.dullFontColor,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Dimensions.spaceSizedLarge),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(
                      Dimensions.paddingSizeDefault,
                    ),
                    decoration: BoxDecoration(
                      color: AppThemeColor.darkBlueColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusDefault,
                      ),
                      border: Border.all(
                        color: AppThemeColor.darkBlueColor.withValues(
                          alpha: 0.2,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: AppThemeColor.darkBlueColor,
                        ),
                        const SizedBox(width: Dimensions.spaceSizeSmall),
                        Expanded(
                          child: Text(
                            'Navigate to My Events to create your first event',
                            style: TextStyle(
                              fontSize: Dimensions.fontSizeSmall,
                              color: AppThemeColor.darkBlueColor,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.left,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Dimensions.spaceSizedLarge),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      ShowToast().showNormalToast(
                        msg: 'Navigate to My Events to create your first event',
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Create Your First Event'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppThemeColor.darkBlueColor,
                      foregroundColor: AppThemeColor.pureWhiteColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: Dimensions.paddingSizeLarge,
                        vertical: Dimensions.paddingSizeDefault,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          Dimensions.radiusDefault,
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

    return Scaffold(
      backgroundColor: AppThemeColor.backGroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Enhanced App Bar with better spacing
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Dimensions.paddingSizeLarge,
                vertical: Dimensions.paddingSizeLarge,
              ),
              decoration: BoxDecoration(
                color: AppThemeColor.pureWhiteColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 15,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: AppThemeColor.lightBlueColor,
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusDefault,
                      ),
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: AppThemeColor.darkBlueColor,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: Dimensions.spaceSizedLarge),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Analytics Dashboard',
                          style: TextStyle(
                            fontSize: Dimensions.fontSizeExtraLarge,
                            fontWeight: FontWeight.bold,
                            color: AppThemeColor.darkBlueColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Comprehensive insights across all events',
                          style: TextStyle(
                            fontSize: Dimensions.fontSizeSmall,
                            color: AppThemeColor.dullFontColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: AppThemeColor.darkBlueColor,
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusDefault,
                      ),
                    ),
                    child: IconButton(
                      onPressed: _exportData,
                      icon: const Icon(
                        Icons.download_rounded,
                        color: AppThemeColor.pureWhiteColor,
                        size: 20,
                      ),
                      tooltip: 'Export Data',
                    ),
                  ),
                ],
              ),
            ),

            // Enhanced Date Filter Chips with better spacing
            Container(
              margin: const EdgeInsets.symmetric(
                horizontal: Dimensions.paddingSizeLarge,
                vertical: Dimensions.paddingSizeLarge,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Time Period',
                    style: TextStyle(
                      fontSize: Dimensions.fontSizeDefault,
                      fontWeight: FontWeight.w600,
                      color: AppThemeColor.darkBlueColor,
                    ),
                  ),
                  const SizedBox(height: Dimensions.spaceSizeSmall),
                  Wrap(
                    spacing: Dimensions.spaceSizeSmall,
                    runSpacing: Dimensions.spaceSizeSmall,
                    children: [
                      _buildFilterChip('All Time', 'all'),
                      _buildFilterChip('Last Week', 'week'),
                      _buildFilterChip('Last Month', 'month'),
                      _buildFilterChip('Last Year', 'year'),
                    ],
                  ),
                ],
              ),
            ),

            // Enhanced Tab Bar with better spacing and design
            Container(
              margin: const EdgeInsets.symmetric(
                horizontal: Dimensions.paddingSizeLarge,
                vertical: Dimensions.paddingSizeDefault,
              ),
              decoration: BoxDecoration(
                color: AppThemeColor.lightBlueColor,
                borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(6.0),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelPadding: const EdgeInsets.symmetric(vertical: 8),
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      Dimensions.radiusDefault,
                    ),
                    color: AppThemeColor.darkBlueColor,
                    boxShadow: [
                      BoxShadow(
                        color: AppThemeColor.darkBlueColor.withValues(
                          alpha: 0.3,
                        ),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  labelColor: AppThemeColor.pureWhiteColor,
                  unselectedLabelColor: AppThemeColor.darkBlueColor,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: Dimensions.fontSizeDefault,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: Dimensions.fontSizeDefault,
                  ),
                  tabs: [
                    Tab(child: _buildTabText('Overview')),
                    Tab(child: _buildAITabText()),
                    Tab(child: _buildTabText('Trends')),
                    Tab(child: _buildTabText('Events')),
                  ],
                ),
              ),
            ),

            // Enhanced Tab Bar View with better spacing
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: Dimensions.paddingSizeLarge,
                ),
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _overviewTab(),
                    _aiInsightsTab(),
                    _trendsTab(),
                    _eventsTab(),
                  ],
                ),
              ),
            ),
          ],
        ),
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

  Widget _buildTabText(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: Dimensions.fontSizeDefault,
      ),
      textAlign: TextAlign.center,
      overflow: TextOverflow.visible,
    );
  }

  Widget _buildAITabText() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'AI',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: Dimensions.fontSizeSmall,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          'Insights',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: Dimensions.fontSizeSmall,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _overviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
      child: Column(
        children: [
          // Modern Analytics Cards Grid
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: Dimensions.spaceSizeSmall,
            mainAxisSpacing: Dimensions.spaceSizeSmall,
            childAspectRatio: 1.4,
            children: [
              _buildModernAnalyticsCard(
                title: 'Total Events',
                value: '${_aggregatedAnalytics['totalEvents'] ?? 0}',
                icon: Icons.event_rounded,
                color: AppThemeColor.darkBlueColor,
                gradient: const LinearGradient(
                  colors: [Color(0xFF2C5A96), Color(0xFF4A90E2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              _buildModernAnalyticsCard(
                title: 'Total Attendees',
                value: '${_aggregatedAnalytics['totalAttendees'] ?? 0}',
                icon: Icons.people_rounded,
                color: AppThemeColor.dullBlueColor,
                gradient: const LinearGradient(
                  colors: [Color(0xFF73ABE4), Color(0xFF9BC2F0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              _buildModernAnalyticsCard(
                title: 'Avg Attendance',
                value:
                    '${(_aggregatedAnalytics['averageAttendance'] ?? 0).toStringAsFixed(1)}',
                icon: Icons.trending_up_rounded,
                color: AppThemeColor.grayColor,
                gradient: const LinearGradient(
                  colors: [Color(0xFF60676C), Color(0xFF8A8A8A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              _buildModernAnalyticsCard(
                title: 'Engagement Score',
                value:
                    '${(_aggregatedAnalytics['engagementScore'] ?? 0).toStringAsFixed(0)}%',
                icon: Icons.insights_rounded,
                color: AppThemeColor.darkBlueColor,
                gradient: const LinearGradient(
                  colors: [Color(0xFF2C5A96), Color(0xFF5B7BC0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ],
          ),

          const SizedBox(height: Dimensions.spaceSizedLarge),

          // Top Performing Event Card
          if (_aggregatedAnalytics['topPerformingEvent'] != null)
            _buildTopPerformingEventCard(),

          const SizedBox(height: Dimensions.spaceSizedLarge),

          // Event Categories Chart
          _buildEventCategoriesCard(),
        ],
      ),
    );
  }

  Widget _buildModernAnalyticsCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Gradient gradient,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(Dimensions.paddingSizeDefault),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(Dimensions.paddingSizeSmall),
              decoration: BoxDecoration(
                color: AppThemeColor.pureWhiteColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
              ),
              child: Icon(icon, color: AppThemeColor.pureWhiteColor, size: 20),
            ),
            const SizedBox(height: Dimensions.spaceSizeSmall),
            Flexible(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: Dimensions.fontSizeLarge,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColor.pureWhiteColor,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 2),
            Flexible(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: Dimensions.fontSizeSmall,
                  fontWeight: FontWeight.w500,
                  color: AppThemeColor.pureWhiteColor,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopPerformingEventCard() {
    final topEvent =
        _aggregatedAnalytics['topPerformingEvent'] as Map<String, dynamic>?;
    if (topEvent == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
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
                padding: const EdgeInsets.all(Dimensions.paddingSizeSmall),
                decoration: BoxDecoration(
                  color: AppThemeColor.lightBlueColor,
                  borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
                ),
                child: Icon(
                  Icons.star_rounded,
                  color: AppThemeColor.darkBlueColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: Dimensions.spaceSizeSmall),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Top Performing Event',
                      style: TextStyle(
                        fontSize: Dimensions.fontSizeDefault,
                        fontWeight: FontWeight.w600,
                        color: AppThemeColor.darkBlueColor,
                      ),
                    ),
                    Text(
                      topEvent['title'] ?? 'Unknown Event',
                      style: TextStyle(
                        fontSize: Dimensions.fontSizeLarge,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColor.darkBlueColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Dimensions.spaceSizeSmall),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Attendees',
                  '${topEvent['attendees'] ?? 0}',
                  Icons.people,
                  AppThemeColor.darkBlueColor,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Date',
                  DateFormat('MMM dd, yyyy').format(topEvent['date']),
                  Icons.calendar_today,
                  AppThemeColor.dullBlueColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(Dimensions.paddingSizeSmall),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: Dimensions.fontSizeDefault,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: Dimensions.fontSizeSmall,
              color: AppThemeColor.dullFontColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEventCategoriesCard() {
    final categories =
        _aggregatedAnalytics['eventCategories'] as Map<String, int>? ?? {};
    if (categories.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
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
                padding: const EdgeInsets.all(Dimensions.paddingSizeSmall),
                decoration: BoxDecoration(
                  color: AppThemeColor.lightBlueColor,
                  borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
                ),
                child: Icon(
                  Icons.category_rounded,
                  color: AppThemeColor.darkBlueColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: Dimensions.spaceSizeSmall),
              Text(
                'Event Categories',
                style: TextStyle(
                  fontSize: Dimensions.fontSizeDefault,
                  fontWeight: FontWeight.w600,
                  color: AppThemeColor.darkBlueColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: Dimensions.spaceSizeSmall),
          SizedBox(height: 200, child: _buildCategoriesPieChart(categories)),
        ],
      ),
    );
  }

  Widget _buildCategoriesPieChart(Map<String, int> categories) {
    if (categories.isEmpty) {
      return Center(
        child: Text(
          'No category data available',
          style: TextStyle(
            fontSize: Dimensions.fontSizeSmall,
            color: AppThemeColor.dullFontColor,
          ),
        ),
      );
    }

    final colors = [
      AppThemeColor.darkBlueColor,
      AppThemeColor.dullBlueColor,
      AppThemeColor.grayColor,
      AppThemeColor.dullIconColor,
      AppThemeColor.darkGreenColor,
    ];

    final sections = categories.entries.map((entry) {
      final index = categories.keys.toList().indexOf(entry.key);
      return PieChartSectionData(
        color: colors[index % colors.length],
        value: entry.value.toDouble(),
        title: '${entry.key}\n${entry.value}',
        radius: 60,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          fontFamily: 'Roboto',
        ),
      );
    }).toList();

    return PieChart(
      PieChartData(sections: sections, centerSpaceRadius: 40, sectionsSpace: 2),
    );
  }

  Widget _aiInsightsTab() {
    if (_isLoadingAI) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_globalAIInsights == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.psychology, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No AI insights available',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'AI insights will be generated once sufficient data is available',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
                fontFamily: 'Roboto',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadGlobalAIInsights,
              icon: const Icon(Icons.refresh),
              label: const Text('Generate Insights'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppThemeColor.darkBlueColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Global Performance Analysis
          _aiInsightCard(
            title: 'Global Performance Analysis',
            icon: Icons.analytics_rounded,
            color: AppThemeColor.darkBlueColor,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Overall Performance Score: ${_globalAIInsights!.globalPerformanceAnalysis?['performanceScore']?.toStringAsFixed(1) ?? 'N/A'}%',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Growth Rate: ${_globalAIInsights!.globalPerformanceAnalysis?['growthRate']?.toStringAsFixed(1) ?? 'N/A'}%',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppThemeColor.darkBlueColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _globalAIInsights!
                            .globalPerformanceAnalysis?['recommendation'] ??
                        'No recommendation available',
                    style: const TextStyle(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Event Strategy Recommendations
          _aiInsightCard(
            title: 'Event Strategy Recommendations',
            icon: Icons.lightbulb_rounded,
            color: AppThemeColor.dullBlueColor,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...(_globalAIInsights!.strategyRecommendations ?? []).map(
                  (recommendation) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _getStrategyIcon(recommendation['type'] ?? ''),
                              color: _getStrategyColor(
                                recommendation['type'] ?? '',
                              ),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                recommendation['title'] ?? 'Unknown',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _getImpactColor(
                                  recommendation['impact'] ?? '',
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                recommendation['impact'] ?? 'Unknown',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          recommendation['description'] ??
                              'No description available',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Confidence: ${((recommendation['confidence'] ?? 0) * 100).toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiInsightCard({
    required String title,
    required IconData icon,
    required Color color,
    required Widget content,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColor.darkBlueColor,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          content,
        ],
      ),
    );
  }

  IconData _getStrategyIcon(String type) {
    switch (type) {
      case 'timing':
        return Icons.access_time;
      case 'marketing':
        return Icons.campaign;
      case 'content':
        return Icons.content_copy;
      case 'engagement':
        return Icons.notifications;
      default:
        return Icons.lightbulb;
    }
  }

  Color _getStrategyColor(String type) {
    switch (type) {
      case 'timing':
        return AppThemeColor.darkBlueColor;
      case 'marketing':
        return AppThemeColor.dullBlueColor;
      case 'content':
        return AppThemeColor.grayColor;
      case 'engagement':
        return AppThemeColor.darkGreenColor;
      default:
        return AppThemeColor.dullIconColor;
    }
  }

  Color _getImpactColor(String impact) {
    switch (impact.toLowerCase()) {
      case 'high':
        return AppThemeColor.darkBlueColor;
      case 'medium':
        return AppThemeColor.dullBlueColor;
      case 'low':
        return AppThemeColor.grayColor;
      default:
        return AppThemeColor.dullIconColor;
    }
  }

  Widget _trendsTab() {
    final monthlyTrends =
        _aggregatedAnalytics['monthlyTrends'] as Map<String, int>? ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Monthly Trends Chart
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.1),
                  spreadRadius: 1,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Monthly Attendance Trends',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColor.darkBlueColor,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Monthly distribution of attendees',
                      child: Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: _buildMonthlyTrendsChart(monthlyTrends),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyTrendsChart(Map<String, int> monthlyTrends) {
    if (monthlyTrends.isEmpty) {
      return Center(
        child: Text(
          'No trend data available',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[500],
            fontFamily: 'Roboto',
          ),
        ),
      );
    }

    final sortedMonths = monthlyTrends.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final spots = <FlSpot>[];
    final barGroups = <BarChartGroupData>[];

    for (int i = 0; i < sortedMonths.length; i++) {
      final count = sortedMonths[i].value.toDouble();

      spots.add(FlSpot(i.toDouble(), count));
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: count,
              color: AppThemeColor.darkBlueColor,
              width: 20,
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: spots.isNotEmpty
            ? spots.map((spot) => spot.y).reduce((a, b) => a > b ? a : b) * 1.2
            : 10,
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 && value.toInt() < sortedMonths.length) {
                  final month = sortedMonths[value.toInt()].key;
                  return Text(
                    DateFormat('MMM yy').format(DateTime.parse('$month-01')),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontFamily: 'Roboto',
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontFamily: 'Roboto',
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: barGroups,
        gridData: FlGridData(
          show: true,
          horizontalInterval: 1,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) {
            return FlLine(color: Colors.grey[300]!, strokeWidth: 1);
          },
        ),
      ),
    );
  }

  Widget _eventsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Events List
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.1),
                  spreadRadius: 1,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Events',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColor.darkBlueColor,
                    fontFamily: 'Roboto',
                  ),
                ),
                const SizedBox(height: 16),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _userEvents.length,
                  itemBuilder: (context, index) {
                    final event = _userEvents[index];
                    final attendees =
                        _aggregatedAnalytics['attendanceByEvent']?[event
                            .title] ??
                        0;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppThemeColor.darkBlueColor,
                        child: Text(
                          event.title.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        event.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Roboto',
                        ),
                      ),
                      subtitle: Text(
                        '${DateFormat('MMM dd, yyyy').format(event.selectedDateTime)} • $attendees attendees',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontFamily: 'Roboto',
                        ),
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.grey[500],
                      ),
                      onTap: () {
                        // Navigate to event analytics
                        RouterClass.nextScreenNormal(
                          context,
                          EventAnalyticsScreen(eventId: event.id),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportData() async {
    try {
      // Prepare CSV data
      final csvData = [
        ['Metric', 'Value'],
        ['Total Events', '${_aggregatedAnalytics['totalEvents'] ?? 0}'],
        ['Total Attendees', '${_aggregatedAnalytics['totalAttendees'] ?? 0}'],
        [
          'Average Attendance',
          '${(_aggregatedAnalytics['averageAttendance'] ?? 0).toStringAsFixed(1)}',
        ],
        [
          'Engagement Score',
          '${(_aggregatedAnalytics['engagementScore'] ?? 0).toStringAsFixed(1)}%',
        ],
        [
          'Dropout Rate',
          '${(_aggregatedAnalytics['dropoutRate'] ?? 0).toStringAsFixed(1)}%',
        ],
      ];

      // Add event categories
      final categories =
          _aggregatedAnalytics['eventCategories'] as Map<String, int>? ?? {};
      if (categories.isNotEmpty) {
        csvData.add([]);
        csvData.add(['Event Categories']);
        categories.forEach((category, value) {
          csvData.add([category, value.toString()]);
        });
      }

      // Add monthly trends
      final monthlyTrends =
          _aggregatedAnalytics['monthlyTrends'] as Map<String, int>? ?? {};
      if (monthlyTrends.isNotEmpty) {
        csvData.add([]);
        csvData.add(['Month', 'Attendees']);
        monthlyTrends.forEach((month, value) {
          csvData.add([month, value.toString()]);
        });
      }

      // Add individual event data
      if (_userEvents.isNotEmpty) {
        csvData.add([]);
        csvData.add(['Event Title', 'Date', 'Attendees']);
        for (final event in _userEvents) {
          final attendees =
              _aggregatedAnalytics['attendanceByEvent']?[event.title] ?? 0;
          csvData.add([
            event.title,
            DateFormat('yyyy-MM-dd').format(event.selectedDateTime),
            attendees.toString(),
          ]);
        }
      }

      // Convert to CSV format
      final csvString = csvData.map((row) => row.join(',')).join('\n');

      // Save to temporary file
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/analytics_dashboard_${DateTime.now().millisecondsSinceEpoch}.csv',
      );
      await file.writeAsString(csvString);

      // Share file
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Analytics Dashboard - ${DateTime.now().toString()}',
          text: 'Analytics dashboard data exported from Orgami app',
        ),
      );

      if (!mounted) return;
      ShowToast().showSnackBar('Data exported successfully', context);
    } catch (e) {
      if (!mounted) return;
      ShowToast().showSnackBar('Error exporting data: $e', context);
    }
  }
}
