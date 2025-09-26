import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/firebase/ai_analytics_helper.dart';
import 'package:attendus/models/attendance_model.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/dimensions.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/Utils/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:attendus/widgets/app_scaffold_wrapper.dart';

class EventAnalyticsScreen extends StatefulWidget {
  final String eventId;

  const EventAnalyticsScreen({super.key, required this.eventId});

  @override
  State<EventAnalyticsScreen> createState() => _EventAnalyticsScreenState();
}

class _EventAnalyticsScreenState extends State<EventAnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  // Deprecated: time filtering not used for single-day event view
  bool _isAuthorized = false;
  String? _eventHostUid;
  DateTime? _eventDate;
  String? _eventTitle;
  List<AttendanceModel> _attendeesList = [];
  bool _isLoadingAttendees = false;
  AIInsights? _aiInsights;
  bool _isLoadingAI = false;
  String _attendeesViewFilter = 'all'; // 'all' | 'new' | 'repeat'

  // Repeat-attendance cache keyed by attendee customerUid
  final Map<String, _AttendeeHostHistory> _attendeeHistoryByUid = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadEventData();
  }

  String _getEventStatusLabel() {
    if (_eventDate == null) return 'Status: Unknown';
    final now = DateTime.now();
    final eventDay = DateTime(
      _eventDate!.year,
      _eventDate!.month,
      _eventDate!.day,
    );
    final today = DateTime(now.year, now.month, now.day);
    if (eventDay.isAfter(today)) return 'Upcoming';
    if (eventDay.isAtSameMomentAs(today)) return 'Today';
    return 'Completed';
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Dimensions.paddingSizeDefault,
        vertical: Dimensions.paddingSizeSmall,
      ),
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
        border: Border.all(color: AppThemeColor.borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppThemeColor.darkBlueColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: Dimensions.fontSizeSmall,
              color: AppThemeColor.darkBlueColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadEventData() async {
    try {
      final eventDoc = await FirebaseFirestore.instance
          .collection('Events')
          .doc(widget.eventId)
          .get();

      if (!eventDoc.exists) {
        if (mounted) {
          ShowToast().showSnackBar(
            'Event not found or access denied.',
            context,
          );
          Navigator.pop(context);
        }
        return;
      }

      final eventData = eventDoc.data() as Map<String, dynamic>;
      final eventHostUid = eventData['customerUid'];
      final DateTime? eventDate = (eventData['selectedDateTime'] as Timestamp?)
          ?.toDate();
      final String? eventTitle = eventData['title'] as String?;

      setState(() {
        _eventHostUid = eventHostUid;
        _eventDate = eventDate;
        _eventTitle = eventTitle;
        _isAuthorized = true; // Assume authorization
      });

      // Load attendees data and other dependent data
      await _loadAttendeesData();
      await _buildAttendeeRepeatHistory();
      _loadAIInsights();
    } catch (e) {
      if (mounted) {
        ShowToast().showSnackBar('Error loading event data: $e', context);
        Navigator.pop(context);
      }
    }
  }

  Future<void> _loadAttendeesData() async {
    setState(() {
      _isLoadingAttendees = true;
    });

    try {
      final attendees = await FirebaseFirestoreHelper().getAttendance(
        eventId: widget.eventId,
      );

      setState(() {
        _attendeesList = attendees;
        _isLoadingAttendees = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingAttendees = false;
      });
      // debugPrint('Error loading attendees: $e'); // Replace with proper logging
    }
  }

  // Build a map of attendee -> events (by this host) they have attended
  Future<void> _buildAttendeeRepeatHistory() async {
    try {
      if (_eventHostUid == null || _attendeesList.isEmpty) return;

      // 1. Fetch all events created by this host.
      final eventsQuery = await FirebaseFirestore.instance
          .collection('Events')
          .where('customerUid', isEqualTo: _eventHostUid)
          .get();

      if (eventsQuery.docs.isEmpty) return;

      final Map<String, Map<String, dynamic>> hostEventsById = {
        for (var doc in eventsQuery.docs) doc.id: doc.data(),
      };
      final hostEventIds = hostEventsById.keys.toList();

      // Get the set of customerUids for the *current* event's attendees
      final currentEventAttendeeUids = _attendeesList
          .map((a) => a.customerUid)
          .toSet();

      if (hostEventIds.isEmpty || currentEventAttendeeUids.isEmpty) return;

      // This map will store all attendance records for all of host's events,
      // grouped by customerUid
      final Map<String, List<DocumentSnapshot>> allAttendanceByCustomerUid = {};

      // 2. Batch query for attendance across all host events.
      final hostEventIdBatches = _chunkList(hostEventIds, 30);

      for (final batch in hostEventIdBatches) {
        if (batch.isEmpty) continue;

        final attendanceQuery = await FirebaseFirestore.instance
            .collectionGroup('Attendance')
            .where('eventId', whereIn: batch)
            .get();

        for (final doc in attendanceQuery.docs) {
          final customerUid = doc.data()['customerUid'] as String?;
          // Filter for attendees of the CURRENT event
          if (customerUid != null &&
              currentEventAttendeeUids.contains(customerUid)) {
            (allAttendanceByCustomerUid[customerUid] ??= []).add(doc);
          }
        }
      }

      final Map<String, _AttendeeHostHistory> computed = {};

      // 3. Process the results in memory.
      allAttendanceByCustomerUid.forEach((customerUid, attendanceDocs) {
        final Set<String> attendedEventIds = {};
        final List<_EventSummary> eventSummaries = [];

        for (final doc in attendanceDocs) {
          final eventId = doc['eventId'] as String;
          if (attendedEventIds.contains(eventId)) continue;

          final eventData = hostEventsById[eventId];
          if (eventData != null) {
            attendedEventIds.add(eventId);
            eventSummaries.add(
              _EventSummary(
                eventId: eventId,
                title: eventData['title'] as String,
                when: (eventData['selectedDateTime'] as Timestamp?)?.toDate(),
              ),
            );
          }
        }

        if (attendedEventIds.isNotEmpty) {
          computed[customerUid] = _AttendeeHostHistory(
            totalEventsByHost: attendedEventIds.length,
            attendedEventIdsByHost: attendedEventIds,
            eventSummaries: eventSummaries,
          );
        }
      });

      if (mounted) {
        setState(() {
          _attendeeHistoryByUid.addAll(computed);
        });
      }
    } catch (e) {
      // Swallow errors; UI will simply omit repeat details
      Logger.error('Failed to build attendee repeat history: $e');
    }
  }

  Future<void> _loadAIInsights() async {
    setState(() {
      _isLoadingAI = true;
    });

    try {
      final aiHelper = AIAnalyticsHelper();
      final insights = await aiHelper.getAIInsights(widget.eventId);

      if (insights == null) {
        // Generate new insights if none exist
        final newInsights = await aiHelper.generateAIInsights(widget.eventId);
        await aiHelper.saveAIInsights(widget.eventId, newInsights);
        setState(() {
          _aiInsights = newInsights;
          _isLoadingAI = false;
        });
      } else {
        setState(() {
          _aiInsights = insights;
          _isLoadingAI = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingAI = false;
      });
      Logger.error('Error loading AI insights: $e');
    }
  }

  /// Get display name for attendee, handling anonymous users
  String _getDisplayName(AttendanceModel attendee) {
    if (attendee.isAnonymous) {
      return 'Anonymous';
    }
    final String name = attendee.userName.trim();
    if (name.isEmpty || name.toLowerCase() == 'manual') {
      return 'Anonymous';
    }
    return name;
  }

  DateTime? _getFilterDate() {
    // For single-day event analytics, no time-window filtering is required.
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthorized) {
      return AppScaffoldWrapper(
        backgroundColor: AppThemeColor.backGroundColor,
        body: SafeArea(
          child: Center(
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
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              AppThemeColor.darkBlueColor,
                              AppThemeColor.dullBlueColor,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: const Icon(
                          Icons.security_rounded,
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
                    ],
                  ),
                ),
                const SizedBox(height: Dimensions.spaceSizedLarge * 2),
                Text(
                  'Verifying Access',
                  style: TextStyle(
                    fontSize: Dimensions.fontSizeOverLarge,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColor.darkBlueColor,
                  ),
                ),
                const SizedBox(height: Dimensions.spaceSizeSmall),
                Text(
                  'Checking authorization for event analytics...',
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
      );
    }

    return AppScaffoldWrapper(
      backgroundColor: AppThemeColor.backGroundColor,
      body: DefaultTabController(
        length: 4,
        child: NestedScrollView(
          headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
            return <Widget>[
              SliverAppBar(
                expandedHeight: 250.0,
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
                        padding: EdgeInsets.fromLTRB(
                          Dimensions.paddingSizeLarge,
                          MediaQuery.of(context).padding.top +
                              kToolbarHeight +
                              Dimensions.spaceSizeSmall,
                          Dimensions.paddingSizeLarge,
                          Dimensions.paddingSizeDefault,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF667EEA),
                                        Color(0xFF764BA2),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      Dimensions.radiusDefault,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF667EEA,
                                        ).withValues(alpha: 0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.analytics_rounded,
                                    color: AppThemeColor.pureWhiteColor,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(
                                  width: Dimensions.spaceSizedDefault,
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _eventTitle == null
                                            ? 'Event Analytics'
                                            : _eventTitle!,
                                        style: TextStyle(
                                          fontSize:
                                              Dimensions.fontSizeOverLarge + 2,
                                          fontWeight: FontWeight.bold,
                                          color: AppThemeColor.darkBlueColor,
                                          height: 1.2,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Deep insights & AI-powered analysis',
                                        style: TextStyle(
                                          fontSize: Dimensions.fontSizeLarge,
                                          color: AppThemeColor.dullFontColor,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: Dimensions.spaceSizeSmall),
                            // Event quick facts (single-day event)
                            Wrap(
                              spacing: Dimensions.spaceSizedDefault,
                              runSpacing: Dimensions.spaceSizedDefault,
                              children: [
                                _buildInfoChip(
                                  Icons.calendar_today_rounded,
                                  _eventDate == null
                                      ? 'Date: Unknown'
                                      : DateFormat(
                                          'EEE, MMM d, yyyy',
                                        ).format(_eventDate!),
                                ),
                                _buildInfoChip(
                                  Icons.flag_rounded,
                                  _getEventStatusLabel(),
                                ),
                              ],
                            ),
                            const SizedBox(height: Dimensions.spaceSizeSmall),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverPersistentHeader(
                delegate: _EventSliverAppBarDelegate(
                  Container(
                    margin: const EdgeInsets.fromLTRB(
                      Dimensions.paddingSizeLarge,
                      Dimensions.spaceSizedDefault,
                      Dimensions.paddingSizeLarge,
                      Dimensions.spaceSizedDefault,
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6.0,
                        vertical: 8.0,
                      ),
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: false,
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        indicatorPadding: const EdgeInsets.symmetric(
                          horizontal: 2,
                        ),
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
                          Tab(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _buildTabText('Overview'),
                            ),
                          ),
                          Tab(child: _buildAITabText()),
                          Tab(child: _buildTabText('Trends')),
                          Tab(child: _buildTabText('Users')),
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
              _usersTab(),
            ],
          ),
        ),
      ),
    );
  }

  // Time period chips removed for single-day event view

  Widget _buildTabText(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: Dimensions.fontSizeDefault,
      ),
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      softWrap: false,
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
    final filterDate = _getFilterDate();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('event_analytics')
          .doc(widget.eventId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'Failed to load analytics data',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                    fontFamily: 'Roboto',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Error: ${snapshot.error}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                    fontFamily: 'Roboto',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {}); // Retry by rebuilding
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppThemeColor.darkGreenColor,
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

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return SingleChildScrollView(
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
                      Icons.insights_rounded,
                      size: 80,
                      color: AppThemeColor.darkBlueColor,
                    ),
                  ),
                  const SizedBox(height: Dimensions.spaceSizedLarge * 2),
                  Text(
                    'No Analytics Data Yet',
                    style: TextStyle(
                      fontSize: Dimensions.fontSizeOverLarge,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColor.darkBlueColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Dimensions.spaceSizeSmall),
                  Text(
                    'Analytics will appear once attendees\nstart signing in to your event',
                    style: TextStyle(
                      fontSize: Dimensions.fontSizeLarge,
                      color: AppThemeColor.dullFontColor,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;

        // Apply date filtering if needed
        if (filterDate != null && data['lastUpdated'] != null) {
          final lastUpdated = data['lastUpdated'] as Timestamp;
          if (lastUpdated.toDate().isBefore(filterDate)) {
            // Data is older than filter, show empty state
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No data available for selected period',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
            );
          }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Analytics Header
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
                          _eventDate == null
                              ? 'Real-time event performance data'
                              : DateFormat(
                                  'EEE, MMM d, yyyy',
                                ).format(_eventDate!),
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

              // Ultra-Modern Analytics Cards Grid (responsive)
              // Analytics Cards Grid with Overall Retention
              FutureBuilder<Map<String, dynamic>>(
                future: _calculateOverallRetentionStats(),
                builder: (context, retentionSnapshot) {
                  final overallRetention =
                      retentionSnapshot.data?['retentionRate'] ?? 0.0;
                  final totalUniqueAcrossEvents =
                      retentionSnapshot.data?['totalUniqueAttendees'] ?? 0;

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final double width = constraints.maxWidth;
                      final int crossAxisCount = width < 360 ? 1 : 2;
                      final double childAspectRatio = width < 360 ? 2.0 : 1.2;
                      return GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: Dimensions.spaceSizedDefault,
                        mainAxisSpacing: Dimensions.spaceSizedDefault,
                        childAspectRatio: childAspectRatio,
                        children: [
                          _buildUltraModernAnalyticsCard(
                            title: 'Total Attendees',
                            value: '${data['totalAttendees'] ?? 0}',
                            icon: Icons.people_rounded,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            change: '+0',
                          ),
                          _buildUltraModernAnalyticsCard(
                            title: 'Repeat Attendees',
                            value: '${data['repeatAttendees'] ?? 0}',
                            icon: Icons.repeat_rounded,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF73ABE4), Color(0xFF4FC3F7)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            change: '+0',
                          ),
                          _buildUltraModernAnalyticsCard(
                            title: 'Dropout Rate',
                            value:
                                '${(data['dropoutRate'] ?? 0).toStringAsFixed(1)}%',
                            icon: Icons.trending_down_rounded,
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF6B6B), Color(0xFFFFE66D)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            change: '+0',
                          ),
                          _buildUltraModernAnalyticsCard(
                            title: 'Overall Retention',
                            value: retentionSnapshot.hasData
                                ? '${overallRetention.toStringAsFixed(1)}%'
                                : 'Loading...',
                            icon: Icons.loyalty_rounded,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            change: retentionSnapshot.hasData
                                ? 'All Events'
                                : '+0',
                            subtitle: retentionSnapshot.hasData
                                ? '$totalUniqueAcrossEvents unique attendees'
                                : null,
                          ),
                        ],
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: Dimensions.spaceSizedLarge * 2),

              // Enhanced Last Updated Card
              _buildEnhancedLastUpdatedCard(data),

              const SizedBox(height: Dimensions.spaceSizedLarge),

              // Modern Privacy Notice
              _buildModernPrivacyNotice(),

              const SizedBox(height: Dimensions.spaceSizedLarge),

              // Add comprehensive retention analysis
              FutureBuilder<Map<String, dynamic>>(
                future: _calculateOverallRetentionStats(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox();
                  }
                  return _buildRetentionAnalysisSection(snapshot.data!);
                },
              ),

              const SizedBox(height: Dimensions.spaceSizedLarge),

              _buildTopPerformingEventCard(),

              const SizedBox(height: Dimensions.spaceSizedLarge),

              _buildModernEventCategoriesCard(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUltraModernAnalyticsCard({
    required String title,
    required String value,
    required IconData icon,
    required Gradient gradient,
    String? change,
    String? subtitle,
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
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: AppThemeColor.pureWhiteColor.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEnhancedLastUpdatedCard(Map<String, dynamic> data) {
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
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF667EEA).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.schedule_rounded,
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
                    'Last Updated',
                    style: TextStyle(
                      fontSize: Dimensions.fontSizeSmall,
                      color: AppThemeColor.dullFontColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data['lastUpdated'] != null
                        ? _formatTimestamp(data['lastUpdated'])
                        : 'Never updated',
                    style: TextStyle(
                      fontSize: Dimensions.fontSizeLarge,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColor.darkBlueColor,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF667EEA),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Live',
                    style: TextStyle(
                      fontSize: Dimensions.fontSizeSmall,
                      color: const Color(0xFF667EEA),
                      fontWeight: FontWeight.w600,
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

  Widget _buildModernPrivacyNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppThemeColor.lightBlueColor,
            AppThemeColor.lightBlueColor.withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
        border: Border.all(
          color: AppThemeColor.borderColor.withValues(alpha: 0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppThemeColor.darkBlueColor,
              borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
              boxShadow: [
                BoxShadow(
                  color: AppThemeColor.darkBlueColor.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              size: 20,
              color: AppThemeColor.pureWhiteColor,
            ),
          ),
          const SizedBox(width: Dimensions.spaceSizedDefault),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Privacy & Compliance',
                  style: TextStyle(
                    fontSize: Dimensions.fontSizeDefault,
                    fontWeight: FontWeight.w700,
                    color: AppThemeColor.darkBlueColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'All data is aggregated and anonymized. Personal identifiers are protected in compliance with privacy regulations.',
                  style: TextStyle(
                    fontSize: Dimensions.fontSizeSmall,
                    color: AppThemeColor.dullFontColor,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Deprecated: event-level retention replaced by overall retention metric
  // Keeping method removed to avoid unused warnings.

  Future<Map<String, dynamic>> _calculateOverallRetentionStats() async {
    try {
      if (_eventHostUid == null) {
        return {
          'retentionRate': 0.0,
          'totalReturnees': 0,
          'totalNewAttendees': 0,
          'totalUniqueAttendees': 0,
          'averageEventsPerAttendee': 0.0,
          'loyaltyDistribution': <String, int>{},
        };
      }

      // Get all events by this host
      final eventsQuery = await FirebaseFirestore.instance
          .collection('Events')
          .where('customerUid', isEqualTo: _eventHostUid)
          .get();

      if (eventsQuery.docs.isEmpty) {
        return {
          'retentionRate': 0.0,
          'totalReturnees': 0,
          'totalNewAttendees': 0,
          'totalUniqueAttendees': 0,
          'averageEventsPerAttendee': 0.0,
          'loyaltyDistribution': <String, int>{},
        };
      }

      // Track unique attendees and their event counts
      final Map<String, Set<String>> attendeeEventHistory = {};
      int totalAttendances = 0;

      // Get attendance data for all events
      for (final eventDoc in eventsQuery.docs) {
        final eventId = eventDoc.id;
        final attendanceQuery = await FirebaseFirestore.instance
            .collection('Attendance')
            .where('eventId', isEqualTo: eventId)
            .get();

        for (final attendanceDoc in attendanceQuery.docs) {
          final customerUid = attendanceDoc.data()['customerUid'] as String?;
          if (customerUid != null && customerUid != 'manual') {
            attendeeEventHistory.putIfAbsent(customerUid, () => {});
            attendeeEventHistory[customerUid]!.add(eventId);
            totalAttendances++;
          }
        }
      }

      // Calculate statistics
      int totalReturnees = 0;
      int totalNewAttendees = 0;
      final Map<String, int> loyaltyDistribution = {
        'Once': 0,
        '2-3 times': 0,
        '4-5 times': 0,
        '6+ times': 0,
      };

      for (final entry in attendeeEventHistory.entries) {
        final eventCount = entry.value.length;
        if (eventCount > 1) {
          totalReturnees++;
        } else {
          totalNewAttendees++;
        }

        // Categorize loyalty
        if (eventCount == 1) {
          loyaltyDistribution['Once'] = (loyaltyDistribution['Once'] ?? 0) + 1;
        } else if (eventCount <= 3) {
          loyaltyDistribution['2-3 times'] =
              (loyaltyDistribution['2-3 times'] ?? 0) + 1;
        } else if (eventCount <= 5) {
          loyaltyDistribution['4-5 times'] =
              (loyaltyDistribution['4-5 times'] ?? 0) + 1;
        } else {
          loyaltyDistribution['6+ times'] =
              (loyaltyDistribution['6+ times'] ?? 0) + 1;
        }
      }

      final totalUniqueAttendees = attendeeEventHistory.length;
      final retentionRate = totalUniqueAttendees > 0
          ? (totalReturnees / totalUniqueAttendees) * 100
          : 0.0;
      final averageEventsPerAttendee = totalUniqueAttendees > 0
          ? totalAttendances / totalUniqueAttendees
          : 0.0;

      return {
        'retentionRate': retentionRate,
        'totalReturnees': totalReturnees,
        'totalNewAttendees': totalNewAttendees,
        'totalUniqueAttendees': totalUniqueAttendees,
        'averageEventsPerAttendee': averageEventsPerAttendee,
        'loyaltyDistribution': loyaltyDistribution,
      };
    } catch (e) {
      Logger.error('Error calculating overall retention stats: $e');
      return {
        'retentionRate': 0.0,
        'totalReturnees': 0,
        'totalNewAttendees': 0,
        'totalUniqueAttendees': 0,
        'averageEventsPerAttendee': 0.0,
        'loyaltyDistribution': <String, int>{},
      };
    }
  }

  Widget _trendsTab() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('event_analytics')
          .doc(widget.eventId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'Failed to load trends data',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                    fontFamily: 'Roboto',
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {}); // Retry by rebuilding
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppThemeColor.darkGreenColor,
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

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.trending_up, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No trends data available',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final hourlySignIns =
            data['hourlySignIns'] as Map<String, dynamic>? ?? {};

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Hourly Sign-ins Chart
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
                          'Sign-ins by Hour',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppThemeColor.darkBlueColor,
                            fontFamily: 'Roboto',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: 'Hourly distribution of sign-ins',
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
                      child: _buildHourlyChart(hourlySignIns),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _usersTab() {
    if (_isLoadingAttendees) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_attendeesList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No attendees data available',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Attendee data will appear once people start signing in',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
                fontFamily: 'Roboto',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Calculate repeat vs new attendees based on history across this host's events
    int repeatAttendees = 0;
    for (final attendee in _attendeesList) {
      final uid = attendee.customerUid;
      if (uid.isEmpty || uid == 'manual') {
        continue;
      }
      final history = _attendeeHistoryByUid[uid];
      if (history == null) continue;
      final priorEventsCount =
          history.attendedEventIdsByHost.contains(widget.eventId)
          ? history.totalEventsByHost - 1
          : history.totalEventsByHost;
      if (priorEventsCount > 0) repeatAttendees += 1;
    }
    final newAttendees = _attendeesList.length - repeatAttendees;

    // Filtered view for Attendees List
    final List<AttendanceModel> filtered = _attendeesList.where((a) {
      if (_attendeesViewFilter == 'all') return true;
      final uid = a.customerUid;
      if (uid.isEmpty || uid == 'manual') {
        return _attendeesViewFilter == 'new';
      }
      final history = _attendeeHistoryByUid[uid];
      final priorEventsCount = (history == null)
          ? 0
          : (history.attendedEventIdsByHost.contains(widget.eventId)
                ? history.totalEventsByHost - 1
                : history.totalEventsByHost);
      final isRepeat = priorEventsCount > 0;
      return _attendeesViewFilter == 'repeat' ? isRepeat : !isRepeat;
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Pie Chart
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
                      'Repeat vs New Attendees',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColor.darkBlueColor,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message:
                          'Repeat: users with prior attendance; New: first-time attendees',
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
                  child: _buildAttendeesPieChart(repeatAttendees, newAttendees),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Attendees List
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
                  'Attendees List',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColor.darkBlueColor,
                    fontFamily: 'Roboto',
                  ),
                ),
                const SizedBox(height: 16),
                // Filter chips for All / New / Repeat
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _attendeesViewFilter == 'all',
                      onSelected: (_) =>
                          setState(() => _attendeesViewFilter = 'all'),
                    ),
                    ChoiceChip(
                      label: const Text('New'),
                      selected: _attendeesViewFilter == 'new',
                      onSelected: (_) =>
                          setState(() => _attendeesViewFilter = 'new'),
                    ),
                    ChoiceChip(
                      label: const Text('Repeat'),
                      selected: _attendeesViewFilter == 'repeat',
                      onSelected: (_) =>
                          setState(() => _attendeesViewFilter = 'repeat'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final attendee = filtered[index];
                    final uid = attendee.customerUid;
                    final history = _attendeeHistoryByUid[uid];
                    final totalByHost = history?.totalEventsByHost ?? 0;
                    final priorEventsCount = (history == null)
                        ? 0
                        : (history.attendedEventIdsByHost.contains(
                                widget.eventId,
                              )
                              ? history.totalEventsByHost - 1
                              : history.totalEventsByHost);
                    final isRepeat = priorEventsCount > 0;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF4CAF50),
                        child: Text(
                          _getDisplayName(
                            attendee,
                          ).substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _getDisplayName(attendee),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Roboto',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isRepeat && totalByHost > 0)
                            TextButton(
                              onPressed: () => _showAttendeeHistoryDialog(
                                attendee,
                                history!,
                              ),
                              child: Text('($totalByHost)'),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        'Signed in at ${_formatTimestamp(attendee.attendanceDateTime)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontFamily: 'Roboto',
                        ),
                      ),
                      trailing: attendee.isAnonymous
                          ? Icon(
                              Icons.visibility_off,
                              size: 16,
                              color: Colors.grey[500],
                            )
                          : null,
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

  Widget _buildHourlyChart(Map<String, dynamic> hourlySignIns) {
    if (hourlySignIns.isEmpty) {
      return Center(
        child: Text(
          'No hourly data available',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[500],
            fontFamily: 'Roboto',
          ),
        ),
      );
    }

    final spots = <FlSpot>[];
    final barGroups = <BarChartGroupData>[];

    // Convert to sorted list
    final sortedHours = hourlySignIns.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    for (int i = 0; i < sortedHours.length; i++) {
      final hour = int.tryParse(sortedHours[i].key.split(':')[0]) ?? 0;
      final count = (sortedHours[i].value as num).toDouble();

      spots.add(FlSpot(hour.toDouble(), count));
      barGroups.add(
        BarChartGroupData(
          x: hour,
          barRods: [
            BarChartRodData(
              toY: count,
              color: const Color(0xFF4CAF50),
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
                return Text(
                  '${value.toInt()}:00',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontFamily: 'Roboto',
                  ),
                );
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

  Widget _buildAttendeesPieChart(int repeatAttendees, int newAttendees) {
    if (repeatAttendees == 0 && newAttendees == 0) {
      return Center(
        child: Text(
          'No attendees data available',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[500],
            fontFamily: 'Roboto',
          ),
        ),
      );
    }

    return PieChart(
      PieChartData(
        sections: [
          PieChartSectionData(
            color: const Color(0xFF4CAF50),
            value: repeatAttendees.toDouble(),
            title: 'Repeat\n$repeatAttendees',
            radius: 60,
            titleStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontFamily: 'Roboto',
            ),
          ),
          PieChartSectionData(
            color: Colors.blue[400]!,
            value: newAttendees.toDouble(),
            title: 'New\n$newAttendees',
            radius: 60,
            titleStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontFamily: 'Roboto',
            ),
          ),
        ],
        centerSpaceRadius: 40,
        sectionsSpace: 2,
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp is Timestamp) {
      final date = timestamp.toDate();
      return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (timestamp is DateTime) {
      final date = timestamp;
      return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    return 'Unknown';
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

    if (_aiInsights == null) {
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
                  onPressed: _loadAIInsights,
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
                        'Smart recommendations for your event',
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

          // Peak Hours Analysis
          _modernAiInsightCard(
            title: 'Peak Hours Analysis',
            icon: Icons.access_time_rounded,
            gradient: const LinearGradient(
              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMetricRow(
                  'Peak Hour',
                  _aiInsights!.peakHoursAnalysis['peakHour'] ?? 'N/A',
                  Icons.schedule_rounded,
                ),
                const SizedBox(height: Dimensions.spaceSizedDefault),
                _buildMetricRow(
                  'Peak Count',
                  '${_aiInsights!.peakHoursAnalysis['peakCount'] ?? 0}',
                  Icons.trending_up_rounded,
                ),
                const SizedBox(height: Dimensions.spaceSizedLarge),
                Container(
                  padding: const EdgeInsets.all(Dimensions.paddingSizeDefault),
                  decoration: BoxDecoration(
                    color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(
                      Dimensions.radiusDefault,
                    ),
                    border: Border.all(
                      color: const Color(0xFF667EEA).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        color: const Color(0xFF667EEA),
                        size: 20,
                      ),
                      const SizedBox(width: Dimensions.spaceSizeSmall),
                      Expanded(
                        child: Text(
                          _aiInsights!.peakHoursAnalysis['recommendation'] ??
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

          const SizedBox(height: 16),

          // Sentiment Analysis
          _aiInsightCard(
            title: 'Sentiment Analysis',
            icon: Icons.sentiment_satisfied,
            color: _getSentimentColor(
              _aiInsights!.sentimentAnalysis['overallSentiment'] ?? 'neutral',
            ),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _getSentimentIcon(
                        _aiInsights!.sentimentAnalysis['overallSentiment'] ??
                            'neutral',
                      ),
                      color: _getSentimentColor(
                        _aiInsights!.sentimentAnalysis['overallSentiment'] ??
                            'neutral',
                      ),
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Overall: ${_aiInsights!.sentimentAnalysis['overallSentiment'] ?? 'neutral'}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _sentimentBar(
                        'Positive',
                        _aiInsights!.sentimentAnalysis['positiveRatio'] ?? 0,
                        AppThemeColor.darkBlueColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _sentimentBar(
                        'Neutral',
                        _aiInsights!.sentimentAnalysis['neutralRatio'] ?? 0,
                        AppThemeColor.dullIconColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _sentimentBar(
                        'Negative',
                        _aiInsights!.sentimentAnalysis['negativeRatio'] ?? 0,
                        AppThemeColor.grayColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _getSentimentColor(
                      _aiInsights!.sentimentAnalysis['overallSentiment'] ??
                          'neutral',
                    ).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _aiInsights!.sentimentAnalysis['recommendation'] ??
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

          // Optimization Predictions
          _aiInsightCard(
            title: 'AI Optimization Recommendations',
            icon: Icons.trending_up,
            color: AppThemeColor.dullBlueColor,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...(_aiInsights!.optimizationPredictions).map(
                  (optimization) => Container(
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
                              _getOptimizationIcon(optimization['type'] ?? ''),
                              color: _getOptimizationColor(
                                optimization['type'] ?? '',
                              ),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                optimization['title'] ?? 'Unknown',
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
                                  optimization['impact'] ?? '',
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                optimization['impact'] ?? 'Unknown',
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
                          optimization['description'] ??
                              'No description available',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Confidence: ${((optimization['confidence'] ?? 0) * 100).toStringAsFixed(1)}%',
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

          const SizedBox(height: 16),

          // Dropout Analysis
          _aiInsightCard(
            title: 'Dropout Analysis',
            icon: Icons.trending_down,
            color: AppThemeColor.grayColor,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dropout Rate: ${(_aiInsights!.dropoutAnalysis['dropoutRate'] ?? 0).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getSeverityColor(
                      _aiInsights!.dropoutAnalysis['severity'] ?? '',
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Severity: ${_aiInsights!.dropoutAnalysis['severity'] ?? 'Unknown'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppThemeColor.grayColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _aiInsights!.dropoutAnalysis['recommendation'] ??
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

          // Repeat Attendee Analysis
          _aiInsightCard(
            title: 'Repeat Attendee Analysis',
            icon: Icons.repeat,
            color: AppThemeColor.darkBlueColor,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Repeat Rate: ${(_aiInsights!.repeatAttendeeAnalysis['repeatRate'] ?? 0).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Repeat Attendees: ${_aiInsights!.repeatAttendeeAnalysis['repeatAttendees'] ?? 0}',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  'Total Attendees: ${_aiInsights!.repeatAttendeeAnalysis['totalAttendees'] ?? 0}',
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
                    _aiInsights!.repeatAttendeeAnalysis['recommendation'] ??
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

  Widget _sentimentBar(String label, double ratio, Color color) {
    return Column(
      children: [
        Text(
          '${(ratio * 100).toStringAsFixed(1)}%',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }

  Color _getSentimentColor(String sentiment) {
    switch (sentiment.toLowerCase()) {
      case 'positive':
        return AppThemeColor.darkBlueColor;
      case 'negative':
        return AppThemeColor.grayColor;
      default:
        return AppThemeColor.dullIconColor;
    }
  }

  IconData _getSentimentIcon(String sentiment) {
    switch (sentiment.toLowerCase()) {
      case 'positive':
        return Icons.sentiment_satisfied;
      case 'negative':
        return Icons.sentiment_dissatisfied;
      default:
        return Icons.sentiment_neutral;
    }
  }

  IconData _getOptimizationIcon(String type) {
    switch (type) {
      case 'timing':
        return Icons.access_time;
      case 'scheduling':
        return Icons.calendar_today;
      case 'engagement':
        return Icons.notifications;
      case 'retention':
        return Icons.repeat;
      case 'feedback':
        return Icons.feedback;
      default:
        return Icons.trending_up;
    }
  }

  Color _getOptimizationColor(String type) {
    switch (type) {
      case 'timing':
        return AppThemeColor.darkBlueColor;
      case 'scheduling':
        return AppThemeColor.dullBlueColor;
      case 'engagement':
        return AppThemeColor.grayColor;
      case 'retention':
        return AppThemeColor.darkBlueColor;
      case 'feedback':
        return AppThemeColor.grayColor;
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

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
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

  Future<void> _exportData() async {
    try {
      // Get analytics data
      final analyticsDoc = await FirebaseFirestore.instance
          .collection('event_analytics')
          .doc(widget.eventId)
          .get();

      if (!analyticsDoc.exists) {
        if (!mounted) return;
        ShowToast().showSnackBar('No data to export', context);
        return;
      }

      final analyticsData = analyticsDoc.data() as Map<String, dynamic>;

      // Prepare CSV data
      final csvData = [
        ['Metric', 'Value'],
        ['Total Attendees', '${analyticsData['totalAttendees'] ?? 0}'],
        ['Repeat Attendees', '${analyticsData['repeatAttendees'] ?? 0}'],
        [
          'Dropout Rate',
          '${(analyticsData['dropoutRate'] ?? 0).toStringAsFixed(1)}%',
        ],
        [
          'Last Updated',
          analyticsData['lastUpdated'] != null
              ? _formatTimestamp(analyticsData['lastUpdated'])
              : 'Never',
        ],
      ];

      // Add AI insights if available
      if (_aiInsights != null) {
        csvData.add([]);
        csvData.add(['AI Insights']);
        csvData.add([
          'Peak Hour',
          _aiInsights!.peakHoursAnalysis['peakHour'] ?? 'N/A',
        ]);
        csvData.add([
          'Peak Count',
          '${_aiInsights!.peakHoursAnalysis['peakCount'] ?? 0}',
        ]);
        csvData.add([
          'Overall Sentiment',
          _aiInsights!.sentimentAnalysis['overallSentiment'] ?? 'neutral',
        ]);
        csvData.add([
          'Positive Ratio',
          '${((_aiInsights!.sentimentAnalysis['positiveRatio'] ?? 0) * 100).toStringAsFixed(1)}%',
        ]);
        csvData.add([
          'Negative Ratio',
          '${((_aiInsights!.sentimentAnalysis['negativeRatio'] ?? 0) * 100).toStringAsFixed(1)}%',
        ]);
        csvData.add([
          'Dropout Rate',
          '${(_aiInsights!.dropoutAnalysis['dropoutRate'] ?? 0).toStringAsFixed(1)}%',
        ]);
        csvData.add([
          'Repeat Rate',
          '${(_aiInsights!.repeatAttendeeAnalysis['repeatRate'] ?? 0).toStringAsFixed(1)}%',
        ]);

        // Add optimization recommendations
        if (_aiInsights!.optimizationPredictions.isNotEmpty) {
          csvData.add([]);
          csvData.add(['Optimization Recommendations']);
          for (final optimization in _aiInsights!.optimizationPredictions) {
            csvData.add([
              optimization['title'] ?? 'Unknown',
              optimization['description'] ?? 'No description',
              optimization['impact'] ?? 'Unknown',
              '${((optimization['confidence'] ?? 0) * 100).toStringAsFixed(1)}%',
            ]);
          }
        }
      }

      // Add hourly data
      final hourlySignIns =
          analyticsData['hourlySignIns'] as Map<String, dynamic>? ?? {};
      if (hourlySignIns.isNotEmpty) {
        csvData.add([]);
        csvData.add(['Hour', 'Sign-ins']);
        hourlySignIns.forEach((hour, value) {
          csvData.add([hour, value.toString()]);
        });
      }

      // Add attendees data
      if (_attendeesList.isNotEmpty) {
        csvData.add([]);
        csvData.add(['Attendee', 'Sign-in Time', 'Anonymous']);
        for (final attendee in _attendeesList) {
          csvData.add([
            _getDisplayName(attendee),
            _formatTimestamp(attendee.attendanceDateTime),
            attendee.isAnonymous ? 'Yes' : 'No',
          ]);
        }
      }

      // Convert to CSV format manually
      final csvString = csvData.map((row) => row.join(',')).join('\n');

      // Save to temporary file
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/event_analytics_${widget.eventId}.csv',
      );
      await file.writeAsString(csvString);

      // Share file
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Event Analytics - ${widget.eventId}',
          text: 'Event analytics data exported from AttendUs app',
        ),
      );
      if (!mounted) return;
      ShowToast().showSnackBar('Data exported successfully', context);
    } catch (e) {
      if (!mounted) return;
      ShowToast().showSnackBar('Error exporting data: $e', context);
    }
  }

  Widget _buildTopPerformingEventCard() {
    final topEvent = _getTopPerformingEvent();
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
                      topEvent['date'] != null
                          ? DateFormat('MMM dd').format(topEvent['date'])
                          : 'N/A',
                      Icons.calendar_today_rounded,
                      const Color(0xFF667EEA),
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
    final categories = _getAnalyticsSummary()['eventCategories'] ?? {};
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

  Map<String, dynamic> _getAnalyticsSummary() {
    // This is a placeholder. You'll need to implement the logic to
    // calculate the summary based on your analytics data.
    return {
      'eventCategories': <String, int>{'Default': 1},
    };
  }

  Map<String, dynamic>? _getTopPerformingEvent() {
    // This is a placeholder. In a single-event analytics screen,
    // this might not be applicable, or could return the current event's data.
    return null;
  }

  Widget _buildRetentionAnalysisSection(Map<String, dynamic> stats) {
    final retentionRate = stats['retentionRate'] ?? 0.0;
    final totalReturnees = stats['totalReturnees'] ?? 0;
    final totalNewAttendees = stats['totalNewAttendees'] ?? 0;
    final totalUniqueAttendees = stats['totalUniqueAttendees'] ?? 0;
    final averageEventsPerAttendee = stats['averageEventsPerAttendee'] ?? 0.0;
    final loyaltyDistribution =
        stats['loyaltyDistribution'] as Map<String, int>? ?? {};

    // Calculate statistical metrics
    final newToReturningRatio = totalReturnees > 0
        ? (totalNewAttendees / totalReturnees).toStringAsFixed(2)
        : 'N/A';
    final churnRate = totalUniqueAttendees > 0
        ? (100 - retentionRate).toStringAsFixed(1)
        : '0';
    final lifetimeValue = averageEventsPerAttendee > 0
        ? (averageEventsPerAttendee * 100 / 100).toStringAsFixed(1)
        : '0';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppThemeColor.pureWhiteColor, const Color(0xFFF5F7FA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with professional styling
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(
                      Dimensions.radiusDefault,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6A11CB).withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.analytics_rounded,
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
                        'Attendee Cohort Analysis',
                        style: TextStyle(
                          fontSize: Dimensions.fontSizeLarge,
                          fontWeight: FontWeight.bold,
                          color: AppThemeColor.darkBlueColor,
                        ),
                      ),
                      Text(
                        'Statistical breakdown across all your events',
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

            // Key Statistical Metrics Grid
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.3,
              children: [
                _buildStatCard(
                  'Retention Rate',
                  '${retentionRate.toStringAsFixed(1)}%',
                  Icons.trending_up_rounded,
                  const Color(0xFF667EEA),
                  subtitle: 'Overall',
                ),
                _buildStatCard(
                  'Churn Rate',
                  '$churnRate%',
                  Icons.trending_down_rounded,
                  const Color(0xFFFF6B6B),
                  subtitle: 'One-time',
                ),
                _buildStatCard(
                  'Avg Frequency',
                  averageEventsPerAttendee.toStringAsFixed(1),
                  Icons.event_repeat_rounded,
                  const Color(0xFF667EEA),
                  subtitle: 'Events/User',
                ),
                _buildStatCard(
                  'Total Unique',
                  '$totalUniqueAttendees',
                  Icons.people_rounded,
                  const Color(0xFF764BA2),
                  subtitle: 'Attendees',
                ),
                _buildStatCard(
                  'New:Return',
                  newToReturningRatio,
                  Icons.compare_arrows_rounded,
                  const Color(0xFFFF9800),
                  subtitle: 'Ratio',
                ),
                _buildStatCard(
                  'LTV Score',
                  lifetimeValue,
                  Icons.star_rounded,
                  const Color(0xFFE91E63),
                  subtitle: 'Index',
                ),
              ],
            ),

            const SizedBox(height: Dimensions.spaceSizedLarge),

            // Enhanced Cohort Distribution Visualization
            Text(
              'Cohort Distribution Analysis',
              style: TextStyle(
                fontSize: Dimensions.fontSizeDefault,
                fontWeight: FontWeight.w600,
                color: AppThemeColor.darkBlueColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Behavioral segmentation of your attendee base',
              style: TextStyle(
                fontSize: Dimensions.fontSizeSmall,
                color: AppThemeColor.dullFontColor,
              ),
            ),
            const SizedBox(height: Dimensions.spaceSizedDefault),

            // Advanced Donut Chart with Statistics
            SizedBox(
              height: 280,
              child: Row(
                children: [
                  // Enhanced Donut chart
                  Expanded(
                    flex: 3,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PieChart(
                          PieChartData(
                            startDegreeOffset: -90,
                            centerSpaceRadius: 65,
                            sections: [
                              PieChartSectionData(
                                value: totalReturnees.toDouble(),
                                title: totalUniqueAttendees > 0
                                    ? '${(totalReturnees / totalUniqueAttendees * 100).toStringAsFixed(0)}%'
                                    : '0%',
                                color: const Color(0xFF667EEA),
                                radius: 45,
                                titleStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                badgeWidget: totalReturnees > 0
                                    ? Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.1,
                                              ),
                                              blurRadius: 4,
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.repeat,
                                          size: 14,
                                          color: Color(0xFF11998E),
                                        ),
                                      )
                                    : null,
                                badgePositionPercentageOffset: 1.2,
                              ),
                              PieChartSectionData(
                                value: totalNewAttendees.toDouble(),
                                title: totalUniqueAttendees > 0
                                    ? '${(totalNewAttendees / totalUniqueAttendees * 100).toStringAsFixed(0)}%'
                                    : '0%',
                                color: const Color(0xFF73ABE4),
                                radius: 45,
                                titleStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                badgeWidget: totalNewAttendees > 0
                                    ? Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.1,
                                              ),
                                              blurRadius: 4,
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.person_add,
                                          size: 14,
                                          color: Color(0xFF73ABE4),
                                        ),
                                      )
                                    : null,
                                badgePositionPercentageOffset: 1.2,
                              ),
                            ],
                            sectionsSpace: 3,
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$totalUniqueAttendees',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: AppThemeColor.darkBlueColor,
                              ),
                            ),
                            Text(
                              'Total Cohort',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppThemeColor.dullFontColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Enhanced Legend with detailed stats
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildEnhancedLegendItem(
                            'Returning Cohort',
                            totalReturnees,
                            const Color(0xFF667EEA),
                            totalUniqueAttendees > 0
                                ? (totalReturnees / totalUniqueAttendees * 100)
                                : 0,
                            icon: Icons.repeat,
                          ),
                          const SizedBox(height: 20),
                          _buildEnhancedLegendItem(
                            'New Cohort',
                            totalNewAttendees,
                            const Color(0xFF73ABE4),
                            totalUniqueAttendees > 0
                                ? (totalNewAttendees /
                                      totalUniqueAttendees *
                                      100)
                                : 0,
                            icon: Icons.person_add,
                          ),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppThemeColor.lightBlueColor.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppThemeColor.borderColor.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.insights,
                                  size: 14,
                                  color: AppThemeColor.darkBlueColor.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _getRetentionInsightShort(retentionRate),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppThemeColor.darkBlueColor
                                          .withValues(alpha: 0.7),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
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

            const SizedBox(height: Dimensions.spaceSizedLarge),

            // Loyalty Distribution
            Text(
              'Attendee Loyalty Distribution',
              style: TextStyle(
                fontSize: Dimensions.fontSizeDefault,
                fontWeight: FontWeight.w600,
                color: AppThemeColor.darkBlueColor,
              ),
            ),
            const SizedBox(height: Dimensions.spaceSizeSmall),

            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: loyaltyDistribution.values.isEmpty
                      ? 10
                      : loyaltyDistribution.values
                                .reduce((a, b) => a > b ? a : b)
                                .toDouble() *
                            1.2,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final category = loyaltyDistribution.keys
                            .toList()[groupIndex];
                        final count = rod.toY.toInt();
                        return BarTooltipItem(
                          '$category\\n$count attendees',
                          TextStyle(
                            color: AppThemeColor.pureWhiteColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final categories = loyaltyDistribution.keys.toList();
                          if (value.toInt() >= 0 &&
                              value.toInt() < categories.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                categories[value.toInt()],
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppThemeColor.dullFontColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                        reservedSize: 30,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: TextStyle(
                              fontSize: 10,
                              color: AppThemeColor.dullFontColor,
                            ),
                          );
                        },
                        reservedSize: 30,
                      ),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 5,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: AppThemeColor.borderColor.withValues(alpha: 0.3),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: loyaltyDistribution.entries.map((entry) {
                    final index = loyaltyDistribution.keys.toList().indexOf(
                      entry.key,
                    );
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: entry.value.toDouble(),
                          gradient: LinearGradient(
                            colors: _getBarGradient(index),
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                          width: 30,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6),
                            topRight: Radius.circular(6),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: Dimensions.spaceSizeSmall),

            // Statistical Insights
            Container(
              padding: const EdgeInsets.all(Dimensions.paddingSizeDefault),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 20,
                    color: AppThemeColor.dullBlueColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getRetentionInsight(retentionRate),
                      style: TextStyle(
                        fontSize: Dimensions.fontSizeSmall,
                        color: AppThemeColor.dullFontColor,
                        fontStyle: FontStyle.italic,
                      ),
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

  // Retention metric card replaced by generic _buildStatCard

  // Legacy legend item replaced by enhanced legend

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppThemeColor.darkBlueColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              color: AppThemeColor.dullFontColor,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 9,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEnhancedLegendItem(
    String label,
    int value,
    Color color,
    double percentage, {
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppThemeColor.dullFontColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '$value',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${percentage.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 10,
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
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

  String _getRetentionInsightShort(double retentionRate) {
    if (retentionRate >= 70) {
      return 'Excellent retention';
    } else if (retentionRate >= 50) {
      return 'Good retention';
    } else if (retentionRate >= 30) {
      return 'Average retention';
    } else {
      return 'Room for growth';
    }
  }

  List<Color> _getBarGradient(int index) {
    const gradients = [
      [Color(0xFF73ABE4), Color(0xFF4FC3F7)], // Once
      [Color(0xFF667EEA), Color(0xFF764BA2)], // 2-3 times
      [Color(0xFF11998E), Color(0xFF38EF7D)], // 4-5 times
      [Color(0xFFFF6B6B), Color(0xFFFFE66D)], // 6+ times
    ];
    return gradients[index % gradients.length];
  }

  String _getRetentionInsight(double retentionRate) {
    if (retentionRate >= 70) {
      return 'Excellent retention! Your events have built a strong loyal community.';
    } else if (retentionRate >= 50) {
      return 'Good retention rate. Consider engagement strategies to convert more one-time attendees.';
    } else if (retentionRate >= 30) {
      return 'Average retention. Focus on creating memorable experiences to encourage repeat attendance.';
    } else {
      return 'Growth opportunity: Implement follow-up strategies and loyalty programs to boost retention.';
    }
  }

  Widget _buildCategoriesPieChart(Map<String, int> categories) {
    if (categories.isEmpty) {
      return Center(
        child: Text(
          'No category data available',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[500],
            fontFamily: 'Roboto',
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
}

class _EventSliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _EventSliverAppBarDelegate(this.child);

  @override
  double get minExtent => 100.0;

  @override
  double get maxExtent => 100.0;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // Ensure the sliver header's render height exactly matches the declared extents
    // to avoid SliverGeometry layoutExtent/paintExtent mismatches.
    return SizedBox(height: maxExtent, child: child);
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return false;
  }
}

// Helper types to store repeat-attendance info
class _EventSummary {
  final String eventId;
  final String title;
  final DateTime? when;
  _EventSummary({
    required this.eventId,
    required this.title,
    required this.when,
  });
}

class _AttendeeHostHistory {
  final int totalEventsByHost;
  final Set<String> attendedEventIdsByHost;
  final List<_EventSummary> eventSummaries;
  _AttendeeHostHistory({
    required this.totalEventsByHost,
    required this.attendedEventIdsByHost,
    required this.eventSummaries,
  });
}

List<List<T>> _chunkList<T>(List<T> list, int chunkSize) {
  final List<List<T>> chunks = [];
  for (var i = 0; i < list.length; i += chunkSize) {
    chunks.add(
      list.sublist(
        i,
        i + chunkSize > list.length ? list.length : i + chunkSize,
      ),
    );
  }
  return chunks;
}

extension _AttendeeHistoryDialogs on _EventAnalyticsScreenState {
  void _showAttendeeHistoryDialog(
    AttendanceModel attendee,
    _AttendeeHostHistory history,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Events attended by ${_getDisplayName(attendee)}'),
          content: SizedBox(
            width: double.maxFinite,
            child: history.eventSummaries.isEmpty
                ? const Text('No history available')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: history.eventSummaries.length,
                    itemBuilder: (context, index) {
                      final es = history.eventSummaries[index];
                      final whenText = es.when == null
                          ? 'Unknown date'
                          : '${es.when!.day}/${es.when!.month}/${es.when!.year}';
                      return ListTile(
                        title: Text(es.title),
                        subtitle: Text(whenText),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}
