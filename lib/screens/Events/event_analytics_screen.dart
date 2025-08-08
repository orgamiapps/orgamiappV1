import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:orgami/firebase/firebase_firestore_helper.dart';
import 'package:orgami/firebase/ai_analytics_helper.dart';
import 'package:orgami/models/attendance_model.dart';
import 'package:orgami/Utils/colors.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:orgami/Utils/toast.dart';
import 'package:orgami/Utils/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class EventAnalyticsScreen extends StatefulWidget {
  final String eventId;

  const EventAnalyticsScreen({super.key, required this.eventId});

  @override
  State<EventAnalyticsScreen> createState() => _EventAnalyticsScreenState();
}

class _EventAnalyticsScreenState extends State<EventAnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedDateFilter = 'all'; // 'all', 'week', 'month'
  bool _isAuthorized = false;
  String? _eventHostUid;
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
    _checkAuthorization();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkAuthorization() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        setState(() {
          _isAuthorized = false;
        });
        return;
      }

      // Get event details to check if user is the host
      final eventDoc = await FirebaseFirestore.instance
          .collection('Events')
          .doc(widget.eventId)
          .get();

      if (!eventDoc.exists) {
        setState(() {
          _isAuthorized = false;
        });
        return;
      }

      final eventData = eventDoc.data() as Map<String, dynamic>;
      final eventHostUid = eventData['customerUid'];

      setState(() {
        _isAuthorized = currentUser.uid == eventHostUid;
        _eventHostUid = eventHostUid;
      });

      if (!_isAuthorized) {
        if (!mounted) return;
        ShowToast().showSnackBar(
          'Access denied. Only event hosts can view analytics.',
          context,
        );
        if (!mounted) return;
        Navigator.pop(context);
      } else {
        // Load attendees data if authorized
        await _loadAttendeesData();
        // Build repeat-attendance history for Users tab
        await _buildAttendeeRepeatHistory();
        _loadAIInsights();
      }
    } catch (e) {
      setState(() {
        _isAuthorized = false;
      });
      if (!mounted) return;
      ShowToast().showSnackBar('Error checking authorization: $e', context);
      if (!mounted) return;
      Navigator.pop(context);
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

      // Fetch all events created by this host
      final eventsQuery = await FirebaseFirestore.instance
          .collection('Events')
          .where('customerUid', isEqualTo: _eventHostUid)
          .get();

      if (eventsQuery.docs.isEmpty) return;

      final Map<String, Map<String, dynamic>> hostEventIdToData = {};
      for (final doc in eventsQuery.docs) {
        hostEventIdToData[doc.id] = doc.data();
      }
      final hostEventIds = hostEventIdToData.keys.toList();

      // Build set of unique attendee customerUids for this event
      final Set<String> uniqueCustomerUids = {
        for (final a in _attendeesList)
          if (a.customerUid.isNotEmpty && a.customerUid != 'manual')
            a.customerUid,
      };

      // For each attendee, query Attendance across host's events in chunks of 10 ids (Firestore 'in' limit)
      final Map<String, _AttendeeHostHistory> computed = {};
      for (final uid in uniqueCustomerUids) {
        final Set<String> attendedEventIdsByHost = {};
        for (final chunk in _chunkList(hostEventIds, 10)) {
          final snap = await FirebaseFirestore.instance
              .collection('Attendance')
              .where('customerUid', isEqualTo: uid)
              .where('eventId', whereIn: chunk)
              .get();
          for (final doc in snap.docs) {
            final data = doc.data();
            final eventId = data['eventId'] as String?;
            if (eventId != null && eventId.isNotEmpty) {
              attendedEventIdsByHost.add(eventId);
            }
          }
        }

        // Build event summaries
        final List<_EventSummary> summaries =
            attendedEventIdsByHost.map((eventId) {
              final map = hostEventIdToData[eventId] ?? {};
              final title = (map['title'] ?? 'Untitled').toString();
              final ts = map['selectedDateTime'];
              DateTime? when;
              if (ts is Timestamp) when = ts.toDate();
              return _EventSummary(eventId: eventId, title: title, when: when);
            }).toList()..sort((a, b) {
              final aTime = a.when ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bTime = b.when ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bTime.compareTo(aTime);
            });

        computed[uid] = _AttendeeHostHistory(
          totalEventsByHost: attendedEventIdsByHost.length,
          attendedEventIdsByHost: attendedEventIdsByHost,
          eventSummaries: summaries,
        );
      }

      if (mounted) {
        setState(() {
          _attendeeHistoryByUid.clear();
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
    return attendee.userName == 'Manual' ? 'Anonymous' : attendee.userName;
  }

  DateTime? _getFilterDate() {
    final now = DateTime.now();
    switch (_selectedDateFilter) {
      case 'week':
        return now.subtract(const Duration(days: 7));
      case 'month':
        return DateTime(now.year, now.month - 1, now.day);
      default:
        return null; // 'all' - no filter
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthorized) {
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
                  'Checking authorization...',
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
                          'Event Analytics',
                          style: TextStyle(
                            fontSize: Dimensions.fontSizeExtraLarge,
                            fontWeight: FontWeight.bold,
                            color: AppThemeColor.darkBlueColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Comprehensive insights & AI analysis',
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
                    ],
                  ),
                ],
              ),
            ),

            // Modern Tab Bar
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
                    Tab(child: _buildTabText('Users')),
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
                    _usersTab(),
                  ],
                ),
              ),
            ),

            // Enhanced Compliance Notice with better spacing
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Dimensions.paddingSizeLarge),
              margin: const EdgeInsets.all(Dimensions.paddingSizeLarge),
              decoration: BoxDecoration(
                color: AppThemeColor.lightBlueColor,
                borderRadius: BorderRadius.circular(Dimensions.radiusLarge),
                border: Border.all(color: AppThemeColor.borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(Dimensions.paddingSizeSmall),
                    decoration: BoxDecoration(
                      color: AppThemeColor.darkBlueColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(
                        Dimensions.radiusDefault,
                      ),
                    ),
                    child: Icon(
                      Icons.security_rounded,
                      size: 18,
                      color: AppThemeColor.darkBlueColor,
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
                            fontWeight: FontWeight.w600,
                            color: AppThemeColor.darkBlueColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Data is aggregated without personal identifiers. Analytics are anonymized for privacy compliance.',
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
          return Center(
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
                    'No Analytics Data Available',
                    style: TextStyle(
                      fontSize: Dimensions.fontSizeExtraLarge,
                      fontWeight: FontWeight.w600,
                      color: AppThemeColor.darkBlueColor,
                      fontFamily: 'Roboto',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Dimensions.spaceSizeSmall),
                  Text(
                    'Analytics will appear once attendees start signing in to your event',
                    style: TextStyle(
                      fontSize: Dimensions.fontSizeDefault,
                      color: AppThemeColor.dullFontColor,
                      fontFamily: 'Roboto',
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
                            'Share your event QR code to start collecting data',
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
            children: [
              // Modern Analytics Cards Grid
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: Dimensions.spaceSizeSmall,
                mainAxisSpacing: Dimensions.spaceSizeSmall,
                childAspectRatio: 1.2,
                children: [
                  _buildModernAnalyticsCard(
                    title: 'Total Attendees',
                    value: '${data['totalAttendees'] ?? 0}',
                    icon: Icons.people_rounded,
                    color: AppThemeColor.darkBlueColor,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2C5A96), Color(0xFF4A90E2)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  _buildModernAnalyticsCard(
                    title: 'Repeat Attendees',
                    value: '${data['repeatAttendees'] ?? 0}',
                    icon: Icons.repeat_rounded,
                    color: AppThemeColor.dullBlueColor,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF73ABE4), Color(0xFF9BC2F0)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  _buildModernAnalyticsCard(
                    title: 'Dropout Rate',
                    value: '${(data['dropoutRate'] ?? 0).toStringAsFixed(1)}%',
                    icon: Icons.trending_down_rounded,
                    color: AppThemeColor.grayColor,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF60676C), Color(0xFF8A8A8A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  _buildModernAnalyticsCard(
                    title: 'Engagement Score',
                    value: _calculateEngagementScore(data).toStringAsFixed(0),
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

              // Last Updated Card
              _buildLastUpdatedCard(data),
            ],
          ),
        );
      },
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
              child: Icon(icon, color: AppThemeColor.pureWhiteColor, size: 24),
            ),
            const SizedBox(height: Dimensions.spaceSizeSmall),
            Text(
              value,
              style: const TextStyle(
                fontSize: Dimensions.fontSizeOverLarge,
                fontWeight: FontWeight.bold,
                color: AppThemeColor.pureWhiteColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: Dimensions.fontSizeSmall,
                fontWeight: FontWeight.w500,
                color: AppThemeColor.pureWhiteColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastUpdatedCard(Map<String, dynamic> data) {
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(Dimensions.paddingSizeSmall),
            decoration: BoxDecoration(
              color: AppThemeColor.lightBlueColor,
              borderRadius: BorderRadius.circular(Dimensions.radiusDefault),
            ),
            child: Icon(
              Icons.update_rounded,
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
                  'Last Updated',
                  style: TextStyle(
                    fontSize: Dimensions.fontSizeDefault,
                    fontWeight: FontWeight.w600,
                    color: AppThemeColor.darkBlueColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data['lastUpdated'] != null
                      ? _formatTimestamp(data['lastUpdated'])
                      : 'Never',
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
    );
  }

  double _calculateEngagementScore(Map<String, dynamic> data) {
    final totalAttendees = data['totalAttendees'] ?? 0;
    final repeatAttendees = data['repeatAttendees'] ?? 0;
    final dropoutRate = data['dropoutRate'] ?? 0.0;

    if (totalAttendees == 0) return 0;

    // Calculate engagement score based on multiple factors
    final repeatRate = (repeatAttendees / totalAttendees) * 100;
    final retentionScore = (100 - dropoutRate) * 0.4; // 40% weight
    final repeatScore = repeatRate * 0.6; // 60% weight

    return retentionScore + repeatScore;
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
          return Center(
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
    }
    return 'Unknown';
  }

  Widget _aiInsightsTab() {
    if (_isLoadingAI) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_aiInsights == null) {
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
              onPressed: _loadAIInsights,
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
          // Peak Hours Analysis
          _aiInsightCard(
            title: 'Peak Hours Analysis',
            icon: Icons.access_time,
            color: AppThemeColor.darkBlueColor,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Peak Hour: ${_aiInsights!.peakHoursAnalysis['peakHour'] ?? 'N/A'}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Peak Count: ${_aiInsights!.peakHoursAnalysis['peakCount'] ?? 0}',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  'Confidence: ${((_aiInsights!.peakHoursAnalysis['confidence'] ?? 0) * 100).toStringAsFixed(1)}%',
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
                    _aiInsights!.peakHoursAnalysis['recommendation'] ??
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
          text: 'Event analytics data exported from Orgami app',
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
