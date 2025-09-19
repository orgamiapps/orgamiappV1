import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:attendus/firebase/ai_analytics_helper.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/Events/event_analytics_screen.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/dimensions.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

class GroupAnalyticsDashboardScreen extends StatefulWidget {
  final String organizationId;

  const GroupAnalyticsDashboardScreen({
    super.key,
    required this.organizationId,
  });

  @override
  State<GroupAnalyticsDashboardScreen> createState() =>
      _GroupAnalyticsDashboardScreenState();
}

class _GroupAnalyticsDashboardScreenState
    extends State<GroupAnalyticsDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedDateFilter = 'all'; // 'all', 'week', 'month', 'year'
  bool _isLoading = false;
  List<EventModel> _groupEvents = [];
  Map<String, dynamic> _aggregatedAnalytics = {};
  AIInsights? _globalAIInsights;
  bool _isLoadingAI = false;
  bool _hasEvents = false;
  final TextEditingController _aiQuestionController = TextEditingController();
  String? _aiAnswer;
  bool _qaLoading = false;
  String _groupName = '';

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
    _loadGroupData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _aiQuestionController.dispose();
    super.dispose();
  }

  Future<void> _loadGroupData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load group information first
      final groupDoc = await FirebaseFirestore.instance
          .collection('Organizations')
          .doc(widget.organizationId)
          .get();

      if (groupDoc.exists) {
        _groupName = groupDoc.data()?['name'] ?? 'Unknown Group';
      }

      // Get all events created for this organization/group
      final eventsQuery = await FirebaseFirestore.instance
          .collection('Events')
          .where('organizationId', isEqualTo: widget.organizationId)
          .get();

      final events = eventsQuery.docs.map((doc) {
        return EventModel.fromJson(doc);
      }).toList();

      // Sort events by date (newest first)
      events.sort((a, b) => b.selectedDateTime.compareTo(a.selectedDateTime));

      setState(() {
        _groupEvents = events;
        _hasEvents = events.isNotEmpty;
        _isLoading = false;
      });

      if (events.isNotEmpty) {
        _loadAggregatedAnalytics();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasEvents = false;
      });
      debugPrint('Error loading group events: $e');
    }
  }

  Future<void> _loadAggregatedAnalytics() async {
    try {
      final analytics = <String, dynamic>{
        'totalEvents': _groupEvents.length,
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
        'upcomingEvents': 0,
        'pastEvents': 0,
        'activeEvents': 0,
        'totalTicketsSold': 0,
        'totalTicketRevenue': 0.0,
      };

      final now = DateTime.now();

      // Aggregate data from all group events
      for (final event in _groupEvents) {
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
            attendees = 0;
            repeatAttendees = 0;
          }

          analytics['totalAttendees'] += attendees;
          analytics['repeatAttendees'] += repeatAttendees;
          analytics['attendanceByEvent'][event.title] = attendees;

          // Track event status
          if (event.selectedDateTime.isAfter(now)) {
            analytics['upcomingEvents']++;
          } else if (event.eventEndTime.isBefore(now)) {
            analytics['pastEvents']++;
          } else {
            analytics['activeEvents']++;
          }

          // Track ticket data
          if (event.ticketsEnabled) {
            analytics['totalTicketsSold'] += event.issuedTickets;
            if (event.ticketPrice != null) {
              analytics['totalTicketRevenue'] +=
                  (event.issuedTickets * event.ticketPrice!);
            }
          }

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

          // Find top performing event
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

      // Compute retention rate and engagement metrics
      try {
        final retentionEvents = _groupEvents.length > 60
            ? (_groupEvents..sort(
                    (a, b) => b.selectedDateTime.compareTo(a.selectedDateTime),
                  ))
                  .take(60)
                  .toList()
            : _groupEvents;

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

          analytics['engagementScore'] = analytics['retentionRate'] ?? 0.0;
        } else {
          analytics['dropoutRate'] = 0.0;
          analytics['engagementScore'] = analytics['retentionRate'] ?? 0.0;
        }
      }

      if (kDebugMode) {
        debugPrint('Group Aggregated Analytics: $analytics');
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
          'totalEvents': _groupEvents.length,
          'totalAttendees': 0,
          'totalRevenue': 0.0,
          'averageAttendance': 0.0,
          'upcomingEvents': _groupEvents
              .where((e) => e.selectedDateTime.isAfter(DateTime.now()))
              .length,
          'pastEvents': _groupEvents
              .where((e) => e.eventEndTime.isBefore(DateTime.now()))
              .length,
          'activeEvents': 0,
          'totalTicketsSold': 0,
          'totalTicketRevenue': 0.0,
          'topPerformingEvent': _groupEvents.isNotEmpty
              ? {
                  'title': _groupEvents.first.title,
                  'attendees': 0,
                  'date': _groupEvents.first.selectedDateTime,
                  'id': _groupEvents.first.id,
                }
              : null,
          'eventCategories': _groupEvents.fold<Map<String, int>>({}, (
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
          'attendanceByEvent': _groupEvents.fold<Map<String, int>>({}, (
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
      final insights = await aiHelper.generateGlobalAIInsights(_groupEvents);

      setState(() {
        _globalAIInsights = insights;
        _isLoadingAI = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingAI = false;
      });
      debugPrint('Error loading group AI insights: $e');
    }
  }

  Future<void> _exportData() async {
    final xlsio.Workbook workbook = xlsio.Workbook();
    final xlsio.Worksheet sheet = workbook.worksheets[0];
    sheet.name = 'Group Analytics';

    // Headers
    sheet.getRangeByName('A1').setText('Metric');
    sheet.getRangeByName('B1').setText('Value');

    // Data
    int rowIndex = 2;
    _aggregatedAnalytics.forEach((key, value) {
      sheet.getRangeByIndex(rowIndex, 1).setText(key);
      if (value is Map) {
        // Handle maps (like topPerformingEvent) by serializing them to a string
        sheet
            .getRangeByIndex(rowIndex, 2)
            .setText(
              value.entries.map((e) => '${e.key}: ${e.value}').join(', '),
            );
      } else {
        sheet.getRangeByIndex(rowIndex, 2).setText(value.toString());
      }
      rowIndex++;
    });

    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();

    final String? directory = (await getTemporaryDirectory()).path;
    final String fileName =
        '$directory/group_analytics_${_groupName.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';
    final File file = File(fileName);
    await file.writeAsBytes(bytes, flush: true);

    await Share.shareXFiles([XFile(fileName)], text: 'Group Analytics Export');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppThemeColor.backGroundColor,
        appBar: AppBar(
          title: const Text(
            'Group Analytics',
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
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
                  'Loading group analytics...',
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
        appBar: AppBar(
          title: Text(
            '$_groupName Analytics',
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
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
                    'No Group Events Found',
                    style: TextStyle(
                      fontSize: Dimensions.fontSizeOverLarge,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColor.darkBlueColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Dimensions.spaceSizeSmall),
                  Text(
                    'This group hasn\'t created any events yet.\nGroup analytics will appear once events are created.',
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
                            'Group admins can create events for the group to start tracking analytics',
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
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppThemeColor.backGroundColor,
      body: DefaultTabController(
        length: 4,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverAppBar(
                expandedHeight: 220,
                floating: false,
                pinned: true,
                backgroundColor: AppThemeColor.darkBlueColor,
                foregroundColor: AppThemeColor.pureWhiteColor,
                surfaceTintColor: AppThemeColor.darkBlueColor,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.download),
                    onPressed: _exportData,
                    tooltip: 'Export Data',
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    '$_groupName Analytics',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppThemeColor.pureWhiteColor,
                    ),
                  ),
                  titlePadding: const EdgeInsetsDirectional.only(
                    start: 16.0,
                    bottom: 56.0, // Above the tab bar
                  ),
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppThemeColor.darkBlueColor,
                          AppThemeColor.dullBlueColor,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(
                        bottom: 50.0,
                      ), // Space for title and tab bar
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildQuickStat(
                            'Total Events',
                            '${_aggregatedAnalytics['totalEvents'] ?? 0}',
                            Icons.event,
                          ),
                          _buildQuickStat(
                            'Total Attendees',
                            '${_aggregatedAnalytics['totalAttendees'] ?? 0}',
                            Icons.people,
                          ),
                          _buildQuickStat(
                            'Avg Attendance',
                            '${(_aggregatedAnalytics['averageAttendance'] ?? 0.0).toStringAsFixed(1)}',
                            Icons.trending_up,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                bottom: TabBar(
                  controller: _tabController,
                  indicatorColor: AppThemeColor.pureWhiteColor,
                  labelColor: AppThemeColor.pureWhiteColor,
                  unselectedLabelColor: AppThemeColor.pureWhiteColor.withValues(
                    alpha: 0.7,
                  ),
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                  ),
                  tabs: const [
                    Tab(text: 'Overview'),
                    Tab(text: 'AI Insights'),
                    Tab(text: 'Events'),
                    Tab(text: 'Q&A'),
                  ],
                ),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              _overviewTab(),
              _aiInsightsTab(),
              _eventsTab(),
              _qaTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStat(String title, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: AppThemeColor.pureWhiteColor.withAlpha((255 * 0.9).round()),
          size: 24,
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: AppThemeColor.pureWhiteColor,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            color: AppThemeColor.pureWhiteColor.withAlpha((255 * 0.7).round()),
            fontSize: 12,
          ),
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
          if (_aggregatedAnalytics.isEmpty && _groupEvents.isNotEmpty)
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

          // Analytics Content
          if (_aggregatedAnalytics.isNotEmpty) ...[
            // Key Metrics Cards
            _buildMetricsSection(),

            const SizedBox(height: Dimensions.spaceSizedLarge),

            // Charts Section
            _buildChartsSection(),

            const SizedBox(height: Dimensions.spaceSizedLarge),

            // Top Performing Event
            if (_aggregatedAnalytics['topPerformingEvent'] != null)
              _buildTopPerformingEventCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricsSection() {
    final metrics = [
      {
        'title': 'Total Events',
        'value': '${_aggregatedAnalytics['totalEvents']}',
        'icon': Icons.event,
        'color': Colors.blue,
      },
      {
        'title': 'Total Attendees',
        'value': '${_aggregatedAnalytics['totalAttendees']}',
        'icon': Icons.people,
        'color': const Color(0xFF667EEA),
      },
      {
        'title': 'Upcoming Events',
        'value': '${_aggregatedAnalytics['upcomingEvents']}',
        'icon': Icons.schedule,
        'color': Colors.orange,
      },
      {
        'title': 'Past Events',
        'value': '${_aggregatedAnalytics['pastEvents']}',
        'icon': Icons.history,
        'color': Colors.purple,
      },
      {
        'title': 'Avg Attendance',
        'value':
            '${(_aggregatedAnalytics['averageAttendance'] as double).toStringAsFixed(1)}',
        'icon': Icons.trending_up,
        'color': Colors.teal,
      },
      {
        'title': 'Retention Rate',
        'value':
            '${(_aggregatedAnalytics['retentionRate'] ?? 0.0).toStringAsFixed(1)}%',
        'icon': Icons.repeat,
        'color': Colors.indigo,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Key Metrics',
          style: TextStyle(
            fontSize: Dimensions.fontSizeOverLarge,
            fontWeight: FontWeight.bold,
            color: AppThemeColor.darkBlueColor,
          ),
        ),
        const SizedBox(height: Dimensions.spaceSizeSmall),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
          ),
          itemCount: metrics.length,
          itemBuilder: (context, index) {
            final metric = metrics[index];
            return _buildMetricCard(
              metric['title'] as String,
              metric['value'] as String,
              metric['icon'] as IconData,
              metric['color'] as Color,
            );
          },
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 24),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColor.darkBlueColor,
                ),
              ),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: AppThemeColor.dullFontColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Analytics Charts',
          style: TextStyle(
            fontSize: Dimensions.fontSizeOverLarge,
            fontWeight: FontWeight.bold,
            color: AppThemeColor.darkBlueColor,
          ),
        ),
        const SizedBox(height: Dimensions.spaceSizeSmall),

        // Event Categories Chart
        if ((_aggregatedAnalytics['eventCategories'] as Map).isNotEmpty)
          _buildCategoriesChart(),

        const SizedBox(height: Dimensions.spaceSizedLarge),

        // Monthly Trends Chart
        if ((_aggregatedAnalytics['monthlyTrends'] as Map).isNotEmpty)
          _buildMonthlyTrendsChart(),
      ],
    );
  }

  Widget _buildCategoriesChart() {
    final categories =
        _aggregatedAnalytics['eventCategories'] as Map<String, int>;
    final total = categories.values.fold(0, (sum, value) => sum + value);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Event Categories',
            style: TextStyle(
              fontSize: Dimensions.fontSizeLarge,
              fontWeight: FontWeight.w600,
              color: AppThemeColor.darkBlueColor,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: PieChart(
                    PieChartData(
                      sections: categories.entries.map((entry) {
                        final percentage = (entry.value / total * 100);
                        return PieChartSectionData(
                          value: entry.value.toDouble(),
                          title: '${percentage.toStringAsFixed(1)}%',
                          radius: 60,
                          color: _getCategoryColor(entry.key),
                          titleStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: categories.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: _getCategoryColor(entry.key),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${entry.key} (${entry.value})',
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getCategoryColor(String category) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.red,
      Colors.indigo,
      Colors.pink,
    ];
    return colors[category.hashCode % colors.length];
  }

  Widget _buildMonthlyTrendsChart() {
    final trends = _aggregatedAnalytics['monthlyTrends'] as Map<String, int>;
    if (trends.isEmpty) return const SizedBox.shrink();

    final sortedEntries = trends.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Monthly Attendance Trends',
            style: TextStyle(
              fontSize: Dimensions.fontSizeLarge,
              fontWeight: FontWeight.w600,
              color: AppThemeColor.darkBlueColor,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: true),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: true),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index >= 0 && index < sortedEntries.length) {
                          final date = DateTime.parse(
                            '${sortedEntries[index].key}-01',
                          );
                          return Text(
                            DateFormat('MMM').format(date),
                            style: const TextStyle(fontSize: 10),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: true),
                lineBarsData: [
                  LineChartBarData(
                    spots: sortedEntries.asMap().entries.map((entry) {
                      return FlSpot(
                        entry.key.toDouble(),
                        entry.value.value.toDouble(),
                      );
                    }).toList(),
                    isCurved: true,
                    color: AppThemeColor.darkBlueColor,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopPerformingEventCard() {
    final event =
        _aggregatedAnalytics['topPerformingEvent'] as Map<String, dynamic>;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                EventAnalyticsScreen(eventId: event['id'] as String),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppThemeColor.darkBlueColor, AppThemeColor.dullBlueColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppThemeColor.darkBlueColor.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.star,
                  color: AppThemeColor.pureWhiteColor,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Top Performing Event',
                  style: TextStyle(
                    fontSize: Dimensions.fontSizeLarge,
                    fontWeight: FontWeight.w600,
                    color: AppThemeColor.pureWhiteColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              event['title'] as String,
              style: TextStyle(
                fontSize: Dimensions.fontSizeOverLarge,
                fontWeight: FontWeight.bold,
                color: AppThemeColor.pureWhiteColor,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.people,
                  color: AppThemeColor.pureWhiteColor.withValues(alpha: 0.8),
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  '${event['attendees']} attendees',
                  style: TextStyle(
                    color: AppThemeColor.pureWhiteColor.withValues(alpha: 0.8),
                    fontSize: Dimensions.fontSizeDefault,
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.calendar_today,
                  color: AppThemeColor.pureWhiteColor.withValues(alpha: 0.8),
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  DateFormat('MMM dd, yyyy').format(event['date'] as DateTime),
                  style: TextStyle(
                    color: AppThemeColor.pureWhiteColor.withValues(alpha: 0.8),
                    fontSize: Dimensions.fontSizeDefault,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _aiInsightsTab() {
    if (_isLoadingAI) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppThemeColor.lightBlueColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppThemeColor.darkBlueColor,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Generating AI insights...',
              style: TextStyle(
                fontSize: Dimensions.fontSizeLarge,
                color: AppThemeColor.darkBlueColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This may take a few moments',
              style: TextStyle(color: AppThemeColor.dullFontColor),
            ),
          ],
        ),
      );
    }

    if (_globalAIInsights == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.psychology_outlined,
                size: 64,
                color: AppThemeColor.dullFontColor,
              ),
              const SizedBox(height: 16),
              Text(
                'AI Insights Not Available',
                style: TextStyle(
                  fontSize: Dimensions.fontSizeOverLarge,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColor.darkBlueColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'AI insights couldn\'t be generated for this group\'s events.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppThemeColor.dullFontColor),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadGlobalAIInsights,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppThemeColor.darkBlueColor,
                  foregroundColor: AppThemeColor.pureWhiteColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI Insights content would go here
          // This would mirror the AI insights structure from the original analytics dashboard
          Text(
            'AI-Powered Group Insights',
            style: TextStyle(
              fontSize: Dimensions.fontSizeOverLarge,
              fontWeight: FontWeight.bold,
              color: AppThemeColor.darkBlueColor,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppThemeColor.pureWhiteColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Text(
              'AI insights for group events will be displayed here. This includes recommendations for improving event attendance, optimal timing, popular categories, and engagement strategies.',
              style: TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _groupEvents.length,
      itemBuilder: (context, index) {
        final event = _groupEvents[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppThemeColor.darkBlueColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.event,
                color: AppThemeColor.darkBlueColor,
              ),
            ),
            title: Text(
              event.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat(
                    'MMM dd, yyyy • HH:mm',
                  ).format(event.selectedDateTime),
                ),
                if (event.categories.isNotEmpty)
                  Text(
                    event.categories.first,
                    style: TextStyle(
                      color: AppThemeColor.darkBlueColor,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.analytics),
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
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EventAnalyticsScreen(eventId: event.id),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _qaTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ask Questions About Your Group Analytics',
            style: TextStyle(
              fontSize: Dimensions.fontSizeLarge,
              fontWeight: FontWeight.bold,
              color: AppThemeColor.darkBlueColor,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppThemeColor.lightBlueColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.lightbulb_outline,
                  color: AppThemeColor.darkBlueColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ask questions about your group\'s event performance, trends, and recommendations.',
                    style: TextStyle(
                      color: AppThemeColor.darkBlueColor,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _aiQuestionController,
            decoration: InputDecoration(
              hintText: 'e.g., "What time of day works best for our events?"',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: IconButton(
                icon: _qaLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                onPressed: _qaLoading ? null : _askAIQuestion,
              ),
            ),
            maxLines: 3,
            onSubmitted: _qaLoading ? null : (_) => _askAIQuestion(),
          ),
          const SizedBox(height: 16),
          if (_aiAnswer != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppThemeColor.pureWhiteColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.psychology,
                        color: AppThemeColor.darkBlueColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'AI Response',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppThemeColor.darkBlueColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(_aiAnswer!),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _askAIQuestion() async {
    if (_aiQuestionController.text.trim().isEmpty || _qaLoading) return;

    setState(() {
      _qaLoading = true;
      _aiAnswer = null;
    });

    try {
      // This would integrate with the AI helper to answer questions
      // For now, provide a placeholder response
      await Future.delayed(const Duration(seconds: 2));

      setState(() {
        _aiAnswer =
            'This feature is being developed. AI-powered Q&A about your group analytics will provide insights about event performance, optimal timing, audience engagement, and recommendations for improvement.';
        _qaLoading = false;
      });

      _aiQuestionController.clear();
    } catch (e) {
      setState(() {
        _aiAnswer =
            'Sorry, I couldn\'t process your question. Please try again.';
        _qaLoading = false;
      });
    }
  }
}
