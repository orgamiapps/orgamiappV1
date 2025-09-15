import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:attendus/firebase/ai_analytics_helper.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/Events/event_analytics_screen.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/dimensions.dart';
import 'package:attendus/Utils/router.dart';
import 'package:flutter/foundation.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:attendus/widgets/app_scaffold_wrapper.dart';

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
  final TextEditingController _aiQuestionController = TextEditingController();
  String? _aiAnswer;
  bool _qaLoading = false;

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
    });
    _loadUserEvents();
  }

  // ignore: unused_element
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

  @override
  void dispose() {
    _tabController.dispose();
    _aiQuestionController.dispose();
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
        // Defer AI generation until AI tab is opened to avoid jank
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

          int attendees = 0;
          int repeatAttendees = 0;

          if (analyticsDoc.exists) {
            final eventData = analyticsDoc.data() as Map<String, dynamic>;
            attendees = eventData['totalAttendees'] ?? 0;
            repeatAttendees = eventData['repeatAttendees'] ?? 0;
          } else {
            // If no analytics document exists, create placeholder data
            // This ensures the UI shows some data even for new events
            attendees = 0;
            repeatAttendees = 0;
          }

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
          final monthKey = DateFormat('yyyy-MM').format(event.selectedDateTime);
          analytics['monthlyTrends'][monthKey] =
              (analytics['monthlyTrends'][monthKey] ?? 0) + attendees;

          // Find top performing event (include events with 0 attendees)
          if (analytics['topPerformingEvent'] == null ||
              attendees > (analytics['topPerformingEvent']['attendees'] ?? 0)) {
            analytics['topPerformingEvent'] = {
              'title': event.title,
              'attendees': attendees,
              'date': event.selectedDateTime,
              'id': event.id,
            };
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Error loading analytics for event ${event.id}: $e');
          }
          // Still process the event even if analytics loading fails
          final category = event.categories.isNotEmpty
              ? event.categories.first
              : 'Other';
          analytics['eventCategories'][category] =
              (analytics['eventCategories'][category] ?? 0) + 1;

          analytics['attendanceByEvent'][event.title] = 0;

          if (analytics['topPerformingEvent'] == null) {
            analytics['topPerformingEvent'] = {
              'title': event.title,
              'attendees': 0,
              'date': event.selectedDateTime,
              'id': event.id,
            };
          }
        }
      }

      // Compute Retention Rate based on unique attendees across all events
      try {
        // Analyze up to 60 most recent events to bound load
        final List<EventModel> retentionEvents = _userEvents.length > 60
            ? (_userEvents..sort(
                    (a, b) => b.selectedDateTime.compareTo(a.selectedDateTime),
                  ))
                  .take(60)
                  .toList()
            : _userEvents;

        final futures = retentionEvents.map((event) {
          return FirebaseFirestore.instance
              .collection('Attendance')
              .where('eventId', isEqualTo: event.id)
              .get();
        }).toList();

        final snapshots = await Future.wait(futures);

        final Map<String, int> attendeeCountsByUser = {};
        for (final snap in snapshots) {
          for (final doc in snap.docs) {
            final data = doc.data();
            final uid = data['customerUid'] as String?;
            if (uid == null || uid.isEmpty) continue;
            attendeeCountsByUser[uid] = (attendeeCountsByUser[uid] ?? 0) + 1;
          }
        }

        final int totalUniqueAttendees = attendeeCountsByUser.length;
        final int repeatUniqueAttendees = attendeeCountsByUser.values
            .where((count) => count > 1)
            .length;
        final double retentionRate = totalUniqueAttendees > 0
            ? (repeatUniqueAttendees / totalUniqueAttendees) * 100.0
            : 0.0;

        analytics['retentionRate'] = retentionRate;
        analytics['totalUniqueAttendees'] = totalUniqueAttendees;
        analytics['repeatUniqueAttendees'] = repeatUniqueAttendees;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error computing retention rate: $e');
        }
        analytics['retentionRate'] = 0.0;
      }

      // Calculate averages and rates
      if (analytics['totalEvents'] > 0) {
        analytics['averageAttendance'] = analytics['totalEvents'] > 0
            ? (analytics['totalAttendees'] as int) /
                  (analytics['totalEvents'] as int)
            : 0.0;

        if (analytics['totalAttendees'] > 0) {
          analytics['dropoutRate'] =
              ((analytics['totalAttendees'] - analytics['repeatAttendees']) /
                  analytics['totalAttendees']) *
              100;

          // Keep engagementScore for backward compatibility but prefer retentionRate in UI
          analytics['engagementScore'] = analytics['retentionRate'] ?? 0.0;
        } else {
          analytics['dropoutRate'] = 0.0;
          analytics['engagementScore'] = analytics['retentionRate'] ?? 0.0;
        }
      }

      if (kDebugMode) {
        debugPrint('Aggregated Analytics: $analytics');
      }

      setState(() {
        _aggregatedAnalytics = analytics;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading aggregated analytics: $e');
      }
      // Provide fallback analytics data
      setState(() {
        _aggregatedAnalytics = {
          'totalEvents': _userEvents.length,
          'totalAttendees': 0,
          'totalRevenue': 0.0,
          'averageAttendance': 0.0,
          'topPerformingEvent': _userEvents.isNotEmpty
              ? {
                  'title': _userEvents.first.title,
                  'attendees': 0,
                  'date': _userEvents.first.selectedDateTime,
                  'id': _userEvents.first.id,
                }
              : null,
          'eventCategories': _userEvents.fold<Map<String, int>>({}, (
            map,
            event,
          ) {
            final category = event.categories.isNotEmpty
                ? event.categories.first
                : 'Other';
            map[category] = (map[category] ?? 0) + 1;
            return map;
          }),
          'monthlyTrends': <String, int>{},
          'attendanceByEvent': _userEvents.fold<Map<String, int>>({}, (
            map,
            event,
          ) {
            map[event.title] = 0;
            return map;
          }),
          'repeatAttendees': 0,
          'dropoutRate': 0.0,
          'engagementScore': 0.0,
        };
      });
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
      return AppScaffoldWrapper(
        selectedBottomNavIndex: 5, // Account tab
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
      return AppScaffoldWrapper(
        selectedBottomNavIndex: 5, // Account tab
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
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppThemeColor.darkBlueColor.withValues(alpha: 0.1),
                          AppThemeColor.lightBlueColor,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusLarge,
                      ),
                      border: Border.all(
                        color: AppThemeColor.darkBlueColor.withValues(
                          alpha: 0.2,
                        ),
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppThemeColor.darkBlueColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.lightbulb_outline,
                            size: 20,
                            color: AppThemeColor.pureWhiteColor,
                          ),
                        ),
                        const SizedBox(width: Dimensions.spaceSizeSmall),
                        Expanded(
                          child: Text(
                            'Navigate to My Events to create your first event',
                            style: TextStyle(
                              fontSize: Dimensions.fontSizeDefault,
                              color: AppThemeColor.darkBlueColor,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.left,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Dimensions.spaceSizedLarge * 2),
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppThemeColor.darkBlueColor,
                          AppThemeColor.dullBlueColor,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusLarge,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppThemeColor.darkBlueColor.withValues(
                            alpha: 0.3,
                          ),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        ShowToast().showNormalToast(
                          msg:
                              'Navigate to My Events to create your first event',
                        );
                      },
                      icon: const Icon(Icons.add_rounded, size: 22),
                      label: const Text(
                        'Create Your First Event',
                        style: TextStyle(
                          fontSize: Dimensions.fontSizeLarge,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: AppThemeColor.pureWhiteColor,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: Dimensions.paddingSizeLarge * 2,
                          vertical: Dimensions.paddingSizeLarge,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            Dimensions.radiusLarge,
                          ),
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

    return AppScaffoldWrapper(
      selectedBottomNavIndex: 5, // Account tab
      backgroundColor: AppThemeColor.backGroundColor,
      body: DefaultTabController(
        length: 4,
        child: NestedScrollView(
          headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
            return <Widget>[
              SliverAppBar(
                expandedHeight: 240.0,
                floating: false,
                pinned: false,
                snap: false,
                backgroundColor: AppThemeColor.backGroundColor,
                elevation: 0,
                leading: Container(
                  margin: const EdgeInsets.all(8),
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
                actions: [
                  Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppThemeColor.darkBlueColor,
                          AppThemeColor.dullBlueColor,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusDefault,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppThemeColor.darkBlueColor.withValues(
                            alpha: 0.3,
                          ),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
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
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppThemeColor.backGroundColor,
                          AppThemeColor.lightBlueColor.withValues(alpha: 0.3),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Dimensions.paddingSizeLarge,
                          Dimensions.paddingSizeLarge * 2,
                          Dimensions.paddingSizeLarge,
                          Dimensions.paddingSizeDefault,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Analytics Dashboard',
                              style: TextStyle(
                                fontSize: Dimensions.fontSizeOverLarge + 4,
                                fontWeight: FontWeight.bold,
                                color: AppThemeColor.darkBlueColor,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Comprehensive insights across all your events',
                              style: TextStyle(
                                fontSize: Dimensions.fontSizeLarge,
                                color: AppThemeColor.dullFontColor,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: Dimensions.spaceSizedLarge),
                            // Time Period Filters (restored to flexible space)
                            Text(
                              'Time Period',
                              style: TextStyle(
                                fontSize: Dimensions.fontSizeDefault,
                                fontWeight: FontWeight.w600,
                                color: AppThemeColor.darkBlueColor,
                              ),
                            ),
                            const SizedBox(height: Dimensions.spaceSizeSmall),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                children: [
                                  _buildModernFilterChip('All Time', 'all'),
                                  const SizedBox(
                                    width: Dimensions.spaceSizeSmall,
                                  ),
                                  _buildModernFilterChip('Week', 'week'),
                                  const SizedBox(
                                    width: Dimensions.spaceSizeSmall,
                                  ),
                                  _buildModernFilterChip('Month', 'month'),
                                  const SizedBox(
                                    width: Dimensions.spaceSizeSmall,
                                  ),
                                  _buildModernFilterChip('Year', 'year'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverPersistentHeader(
                delegate: _SliverAppBarDelegate(
                  Container(
                    margin: const EdgeInsets.fromLTRB(
                      Dimensions.paddingSizeLarge,
                      0,
                      Dimensions.paddingSizeLarge,
                      Dimensions.spaceSizeSmall,
                    ),
                    decoration: BoxDecoration(
                      color: AppThemeColor.pureWhiteColor,
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusLarge,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(6.0),
                      child: TabBar(
                        controller: _tabController,
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelPadding: const EdgeInsets.symmetric(vertical: 12),
                        indicator: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            Dimensions.radiusDefault,
                          ),
                          gradient: const LinearGradient(
                            colors: [
                              AppThemeColor.darkBlueColor,
                              AppThemeColor.dullBlueColor,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppThemeColor.darkBlueColor.withValues(
                                alpha: 0.3,
                              ),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        labelColor: AppThemeColor.pureWhiteColor,
                        unselectedLabelColor: AppThemeColor.darkBlueColor,
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
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
                ),
                pinned: true,
              ),
            ];
          },
          body: TabBarView(
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
    );
  }

  Widget _buildModernFilterChip(String label, String value) {
    final isSelected = _selectedDateFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedDateFilter = value;
        });
        // Reload analytics when filter changes
        if (_userEvents.isNotEmpty) {
          _loadAggregatedAnalytics();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: Dimensions.paddingSizeDefault,
          vertical: Dimensions.paddingSizeSmall,
        ),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [
                    AppThemeColor.darkBlueColor,
                    AppThemeColor.dullBlueColor,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : AppThemeColor.pureWhiteColor,
          borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
          border: Border.all(
            color: isSelected ? Colors.transparent : AppThemeColor.borderColor,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? AppThemeColor.darkBlueColor.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: isSelected ? 10 : 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? AppThemeColor.pureWhiteColor
                : AppThemeColor.darkBlueColor,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: Dimensions.fontSizeSmall,
          ),
        ),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Loading state for analytics data
          if (_aggregatedAnalytics.isEmpty && _userEvents.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Dimensions.paddingSizeLarge * 2),
              decoration: BoxDecoration(
                color: AppThemeColor.lightBlueColor,
                borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppThemeColor.darkBlueColor,
                    ),
                  ),
                  const SizedBox(height: Dimensions.spaceSizedLarge),
                  Text(
                    'Loading analytics data...',
                    style: TextStyle(
                      fontSize: Dimensions.fontSizeDefault,
                      color: AppThemeColor.darkBlueColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          // Analytics Header
          if (_aggregatedAnalytics.isNotEmpty) ...[
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
                    borderRadius: BorderRadius.circular(
                      Dimensions.radiusDefault,
                    ),
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
                  value: '${_aggregatedAnalytics['totalEvents'] ?? 0}',
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
                  value: '${_aggregatedAnalytics['totalAttendees'] ?? 0}',
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
                  value: (_aggregatedAnalytics['averageAttendance'] ?? 0) > 0
                      ? '${(_aggregatedAnalytics['averageAttendance'] ?? 0).toStringAsFixed(1)}'
                      : '0.0',
                  icon: Icons.trending_up_rounded,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  change: '+0',
                ),
                _buildUltraModernAnalyticsCard(
                  title: 'Retention Rate',
                  value: (_aggregatedAnalytics['retentionRate'] ?? 0) > 0
                      ? '${(_aggregatedAnalytics['retentionRate'] ?? 0).toStringAsFixed(0)}%'
                      : '0%',
                  icon: Icons.loyalty_rounded,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B6B), Color(0xFFFFE66D)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  change: '+0',
                ),
              ],
            ),

            const SizedBox(height: Dimensions.spaceSizedLarge * 2),

            // Top Performing Event Card
            if (_aggregatedAnalytics['topPerformingEvent'] != null)
              _buildEnhancedTopPerformingEventCard(),

            const SizedBox(height: Dimensions.spaceSizedLarge),

            // Event Categories Chart
            _buildModernEventCategoriesCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildUltraModernAnalyticsCard({
    required String title,
    required String value,
    required IconData icon,
    required Gradient gradient,
    String? change,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
          gradient: LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.1),
              Colors.white.withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
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
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: AppThemeColor.pureWhiteColor,
                    size: 20,
                  ),
                ),
                if (change != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      change,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppThemeColor.pureWhiteColor,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Dimensions.spaceSizeSmall),
            Text(
              value,
              style: const TextStyle(
                fontSize: Dimensions.fontSizeOverLarge,
                fontWeight: FontWeight.bold,
                color: AppThemeColor.pureWhiteColor,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: Dimensions.fontSizeSmall,
                fontWeight: FontWeight.w500,
                color: AppThemeColor.pureWhiteColor.withValues(alpha: 0.9),
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnhancedTopPerformingEventCard() {
    final topEvent =
        _aggregatedAnalytics['topPerformingEvent'] as Map<String, dynamic>?;
    if (topEvent == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppThemeColor.pureWhiteColor,
            AppThemeColor.lightBlueColor.withValues(alpha: 0.3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(
                      Dimensions.radiusDefault,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    color: AppThemeColor.pureWhiteColor,
                    size: 24,
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
                          fontWeight: FontWeight.w500,
                          color: AppThemeColor.dullFontColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        topEvent['title'] ?? 'Unknown Event',
                        style: TextStyle(
                          fontSize: Dimensions.fontSizeLarge,
                          fontWeight: FontWeight.bold,
                          color: AppThemeColor.darkBlueColor,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Dimensions.spaceSizedLarge),
            Container(
              padding: const EdgeInsets.all(Dimensions.paddingSizeDefault),
              decoration: BoxDecoration(
                color: AppThemeColor.pureWhiteColor.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
                border: Border.all(
                  color: AppThemeColor.borderColor.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildEnhancedStatItem(
                      'Attendees',
                      '${topEvent['attendees'] ?? 0}',
                      Icons.people_rounded,
                      const Color(0xFF667EEA),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: AppThemeColor.borderColor,
                  ),
                  Expanded(
                    child: _buildEnhancedStatItem(
                      'Date',
                      DateFormat('MMM dd').format(topEvent['date']),
                      Icons.calendar_today_rounded,
                      const Color(0xFF11998E),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
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

  // ignore: unused_element
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
                child: _buildLegacyStatItem(
                  'Attendees',
                  '${topEvent['attendees'] ?? 0}',
                  Icons.people,
                  AppThemeColor.darkBlueColor,
                ),
              ),
              Expanded(
                child: _buildLegacyStatItem(
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

  // ignore: unused_element
  Widget _buildLegacyStatItem(
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

  // ignore: unused_element
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

  Widget _buildEnhancedStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: Dimensions.fontSizeLarge,
            fontWeight: FontWeight.bold,
            color: AppThemeColor.darkBlueColor,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: Dimensions.fontSizeSmall,
            color: AppThemeColor.dullFontColor,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildModernEventCategoriesCard() {
    final categories =
        _aggregatedAnalytics['eventCategories'] as Map<String, int>? ?? {};
    if (categories.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppThemeColor.pureWhiteColor,
            AppThemeColor.lightBlueColor.withValues(alpha: 0.2),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(
                      Dimensions.radiusDefault,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF667EEA).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.donut_large_rounded,
                    color: AppThemeColor.pureWhiteColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: Dimensions.spaceSizedDefault),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Event Categories',
                        style: TextStyle(
                          fontSize: Dimensions.fontSizeLarge,
                          fontWeight: FontWeight.bold,
                          color: AppThemeColor.darkBlueColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Distribution of your events by category',
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
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: AppThemeColor.pureWhiteColor.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
                border: Border.all(
                  color: AppThemeColor.borderColor.withValues(alpha: 0.5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(Dimensions.paddingSizeDefault),
                child: _buildCategoriesPieChart(categories),
              ),
            ),
          ],
        ),
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
      return Center(
        child: Container(
          padding: const EdgeInsets.all(Dimensions.paddingSizeLarge * 2),
          decoration: BoxDecoration(
            color: AppThemeColor.lightBlueColor,
            borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: const Icon(
                  Icons.psychology_rounded,
                  color: AppThemeColor.pureWhiteColor,
                  size: 32,
                ),
              ),
              const SizedBox(height: Dimensions.spaceSizedLarge),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppThemeColor.darkBlueColor,
                ),
              ),
              const SizedBox(height: Dimensions.spaceSizedLarge),
              Text(
                'Generating AI Insights...',
                style: TextStyle(
                  fontSize: Dimensions.fontSizeLarge,
                  color: AppThemeColor.darkBlueColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Dimensions.spaceSizeSmall),
              Text(
                'Our AI is analyzing your event data',
                style: TextStyle(
                  fontSize: Dimensions.fontSizeDefault,
                  color: AppThemeColor.dullFontColor,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_globalAIInsights == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(Dimensions.paddingSizeLarge * 2),
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
                      color: AppThemeColor.darkBlueColor.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.psychology_rounded,
                  size: 80,
                  color: AppThemeColor.darkBlueColor,
                ),
              ),
              const SizedBox(height: Dimensions.spaceSizedLarge * 2),
              Text(
                'No AI Insights Available',
                style: TextStyle(
                  fontSize: Dimensions.fontSizeOverLarge,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColor.darkBlueColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Dimensions.spaceSizeSmall),
              Text(
                'AI insights will be generated once\nsufficient data is available',
                style: TextStyle(
                  fontSize: Dimensions.fontSizeLarge,
                  color: AppThemeColor.dullFontColor,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Dimensions.spaceSizedLarge * 2),
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF667EEA).withValues(alpha: 0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: _loadGlobalAIInsights,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 22),
                  label: const Text(
                    'Generate AI Insights',
                    style: TextStyle(
                      fontSize: Dimensions.fontSizeLarge,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: AppThemeColor.pureWhiteColor,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: Dimensions.paddingSizeLarge * 2,
                      vertical: Dimensions.paddingSizeLarge,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusLarge,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
      child: Column(
        children: [
          // AI Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.3),
                  blurRadius: 20,
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
                    borderRadius: BorderRadius.circular(
                      Dimensions.radiusDefault,
                    ),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: AppThemeColor.pureWhiteColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: Dimensions.spaceSizedDefault),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI-Powered Insights',
                        style: TextStyle(
                          fontSize: Dimensions.fontSizeLarge,
                          fontWeight: FontWeight.bold,
                          color: AppThemeColor.pureWhiteColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Smart recommendations based on your event data',
                        style: TextStyle(
                          fontSize: Dimensions.fontSizeDefault,
                          color: AppThemeColor.pureWhiteColor.withValues(
                            alpha: 0.9,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: Dimensions.spaceSizedLarge),

          // Narrative Summary
          if (_globalAIInsights!.naturalSummary != null)
            _modernAiInsightCard(
              title: 'Executive Summary',
              icon: Icons.summarize_rounded,
              gradient: const LinearGradient(
                colors: [Color(0xFF6A85B6), Color(0xFFBAC8E0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              content: Text(
                _globalAIInsights!.naturalSummary!,
                style: TextStyle(
                  fontSize: Dimensions.fontSizeDefault,
                  color: AppThemeColor.darkBlueColor,
                  height: 1.4,
                ),
              ),
            ),

          const SizedBox(height: Dimensions.spaceSizedLarge),

          // Global Performance Analysis
          _modernAiInsightCard(
            title: 'Global Performance Analysis',
            icon: Icons.analytics_rounded,
            gradient: const LinearGradient(
              colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMetricRow(
                  'Performance Score',
                  '${_globalAIInsights!.globalPerformanceAnalysis?['performanceScore']?.toStringAsFixed(1) ?? 'N/A'}%',
                  Icons.speed_rounded,
                ),
                const SizedBox(height: Dimensions.spaceSizedDefault),
                _buildMetricRow(
                  'Growth Rate',
                  '${_globalAIInsights!.globalPerformanceAnalysis?['growthRate']?.toStringAsFixed(1) ?? 'N/A'}%',
                  Icons.trending_up_rounded,
                ),
                const SizedBox(height: Dimensions.spaceSizedLarge),
                Container(
                  padding: const EdgeInsets.all(Dimensions.paddingSizeDefault),
                  decoration: BoxDecoration(
                    color: const Color(0xFF11998E).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(
                      Dimensions.radiusDefault,
                    ),
                    border: Border.all(
                      color: const Color(0xFF11998E).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        color: const Color(0xFF11998E),
                        size: 20,
                      ),
                      const SizedBox(width: Dimensions.spaceSizeSmall),
                      Expanded(
                        child: Text(
                          _globalAIInsights!
                                  .globalPerformanceAnalysis?['recommendation'] ??
                              'No recommendation available',
                          style: TextStyle(
                            fontSize: Dimensions.fontSizeDefault,
                            color: AppThemeColor.darkBlueColor,
                            fontStyle: FontStyle.italic,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: Dimensions.spaceSizedLarge),

          // Best Day and Time-of-Day
          Row(
            children: [
              Expanded(
                child: _modernAiInsightCard(
                  title: 'Best Day to Host',
                  icon: Icons.event_available_rounded,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF56CCF2), Color(0xFF2F80ED)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  content: _buildMetricRow(
                    'Best Day',
                    _globalAIInsights!.dayOfWeekInsights?['bestDay'] ?? 'N/A',
                    Icons.today_rounded,
                  ),
                ),
              ),
              const SizedBox(width: Dimensions.spaceSizedDefault),
              Expanded(
                child: _modernAiInsightCard(
                  title: 'Best Time of Day',
                  icon: Icons.access_time_rounded,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF9A9E), Color(0xFFFAD0C4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  content: _buildMetricRow(
                    'Peak Window',
                    _globalAIInsights!.timeOfDayInsights?['bestHourRange'] ??
                        'N/A',
                    Icons.timelapse_rounded,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: Dimensions.spaceSizedLarge),

          // Forecast
          _modernAiInsightCard(
            title: 'Attendance Forecast',
            icon: Icons.query_stats_rounded,
            gradient: const LinearGradient(
              colors: [Color(0xFF00B09B), Color(0xFF96C93D)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMetricRow(
                  'Next Month Projection',
                  '${_globalAIInsights!.forecast?['nextMonth'] ?? 0}',
                  Icons.trending_up_rounded,
                ),
                const SizedBox(height: Dimensions.spaceSizedDefault),
                _buildMetricRow(
                  'Confidence',
                  '${((_globalAIInsights!.forecast?['confidence'] ?? 0.0) * 100).toStringAsFixed(0)}%',
                  Icons.verified_rounded,
                ),
              ],
            ),
          ),

          const SizedBox(height: Dimensions.spaceSizedLarge),

          // Dwell Insights
          if (_globalAIInsights!.dwellInsights != null)
            _modernAiInsightCard(
              title: 'Dwell Time Insights',
              icon: Icons.av_timer_rounded,
              gradient: const LinearGradient(
                colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMetricRow(
                    'Average Dwell',
                    '${(_globalAIInsights!.dwellInsights!['avgMinutes'] as num).toStringAsFixed(0)} minutes',
                    Icons.schedule_rounded,
                  ),
                  const SizedBox(height: Dimensions.spaceSizedDefault),
                  _buildMetricRow(
                    'High Engagement',
                    '${(_globalAIInsights!.dwellInsights!['highEngagementPercent'] as num).toStringAsFixed(0)}% stay >45m',
                    Icons.emoji_events_rounded,
                  ),
                ],
              ),
            ),

          if ((_globalAIInsights!.anomalies ?? []).isNotEmpty) ...[
            const SizedBox(height: Dimensions.spaceSizedLarge),
            _modernAiInsightCard(
              title: 'Attendance Anomalies',
              icon: Icons.warning_amber_rounded,
              gradient: const LinearGradient(
                colors: [Color(0xFFFFD200), Color(0xFFF7971E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              content: Column(
                children: [
                  ..._globalAIInsights!.anomalies!.map(
                    (a) => Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: Dimensions.spaceSizeSmall,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            a['type'] == 'high'
                                ? Icons.trending_up
                                : Icons.trending_down,
                            color: a['type'] == 'high'
                                ? Colors.green
                                : Colors.red,
                            size: 18,
                          ),
                          const SizedBox(width: Dimensions.spaceSizeSmall),
                          Expanded(
                            child: Text(
                              '${a['title']} • ${a['attendees']} attendees',
                              style: TextStyle(
                                fontSize: Dimensions.fontSizeSmall,
                                color: AppThemeColor.darkBlueColor,
                                fontWeight: FontWeight.w600,
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
          ],

          const SizedBox(height: Dimensions.spaceSizedLarge),

          // Event Strategy Recommendations
          _modernAiInsightCard(
            title: 'Strategy Recommendations',
            icon: Icons.psychology_rounded,
            gradient: const LinearGradient(
              colors: [Color(0xFFFF6B6B), Color(0xFFFFE66D)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...(_globalAIInsights!.strategyRecommendations ?? []).map(
                  (recommendation) => Container(
                    margin: const EdgeInsets.only(
                      bottom: Dimensions.spaceSizedDefault,
                    ),
                    padding: const EdgeInsets.all(
                      Dimensions.paddingSizeDefault,
                    ),
                    decoration: BoxDecoration(
                      color: AppThemeColor.pureWhiteColor.withValues(
                        alpha: 0.7,
                      ),
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusDefault,
                      ),
                      border: Border.all(
                        color: AppThemeColor.borderColor.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: _getStrategyColor(
                                  recommendation['type'] ?? '',
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                _getStrategyIcon(recommendation['type'] ?? ''),
                                color: AppThemeColor.pureWhiteColor,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: Dimensions.spaceSizeSmall),
                            Expanded(
                              child: Text(
                                recommendation['title'] ?? 'Unknown',
                                style: TextStyle(
                                  fontSize: Dimensions.fontSizeDefault,
                                  fontWeight: FontWeight.w600,
                                  color: AppThemeColor.darkBlueColor,
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
                        const SizedBox(height: Dimensions.spaceSizeSmall),
                        Text(
                          recommendation['description'] ??
                              'No description available',
                          style: TextStyle(
                            fontSize: Dimensions.fontSizeSmall,
                            color: AppThemeColor.dullFontColor,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: Dimensions.spaceSizeSmall),
                        Row(
                          children: [
                            Icon(
                              Icons.psychology_outlined,
                              size: 14,
                              color: AppThemeColor.dullIconColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Confidence: ${((recommendation['confidence'] ?? 0) * 100).toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: Dimensions.fontSizeSmall,
                                color: AppThemeColor.dullIconColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: Dimensions.spaceSizedLarge),

          // Ask AI Q&A
          _modernAiInsightCard(
            title: 'Ask AI About Your Events',
            icon: Icons.smart_toy_rounded,
            gradient: const LinearGradient(
              colors: [Color(0xFF7F7FD5), Color(0xFF86A8E7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            content: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _aiQuestionController,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _onAskAI(),
                        decoration: const InputDecoration(
                          hintText:
                              'e.g., What day should I host my next event?',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _qaLoading ? null : _onAskAI,
                      icon: _qaLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded, size: 16),
                      label: const Text('Ask'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppThemeColor.darkBlueColor,
                        foregroundColor: AppThemeColor.pureWhiteColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_aiAnswer != null) ...[
                  const SizedBox(height: Dimensions.spaceSizedDefault),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _aiAnswer!,
                      style: TextStyle(
                        fontSize: Dimensions.fontSizeDefault,
                        color: AppThemeColor.darkBlueColor,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _modernAiInsightCard({
    required String title,
    required IconData icon,
    required Gradient gradient,
    required Widget content,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppThemeColor.pureWhiteColor,
            AppThemeColor.lightBlueColor.withValues(alpha: 0.2),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(
                      Dimensions.radiusDefault,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    icon,
                    color: AppThemeColor.pureWhiteColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: Dimensions.spaceSizedDefault),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: Dimensions.fontSizeLarge,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColor.darkBlueColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Dimensions.spaceSizedLarge),
            Container(
              padding: const EdgeInsets.all(Dimensions.paddingSizeDefault),
              decoration: BoxDecoration(
                color: AppThemeColor.pureWhiteColor.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
                border: Border.all(
                  color: AppThemeColor.borderColor.withValues(alpha: 0.5),
                ),
              ),
              child: content,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppThemeColor.darkBlueColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: AppThemeColor.darkBlueColor),
        ),
        const SizedBox(width: Dimensions.spaceSizedDefault),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: Dimensions.fontSizeSmall,
                  color: AppThemeColor.dullFontColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
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

  Future<void> _onAskAI() async {
    final q = _aiQuestionController.text.trim();
    if (q.isEmpty || _globalAIInsights == null) return;
    setState(() {
      _qaLoading = true;
      _aiAnswer = null;
    });
    try {
      final helper = AIAnalyticsHelper();
      final answer = await helper.answerQuestion(q, _globalAIInsights!);
      if (!mounted) return;
      setState(() {
        _aiAnswer = answer;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiAnswer = 'Sorry, I could not process that question: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _qaLoading = false;
      });
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

  // ignore: unused_element
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

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _SliverAppBarDelegate(this.child);

  @override
  double get minExtent => 80.0;

  @override
  double get maxExtent => 80.0;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return false;
  }
}
