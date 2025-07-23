import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:orgami/Utils/Colors.dart';
import 'package:orgami/Utils/dimensions.dart';
import 'package:orgami/Utils/Toast.dart';
import 'package:orgami/Firebase/FirebaseFirestoreHelper.dart';
import 'package:orgami/Models/AttendanceModel.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';

class EventAnalyticsScreen extends StatefulWidget {
  final String eventId;

  const EventAnalyticsScreen({
    super.key,
    required this.eventId,
  });

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
        ShowToast().showSnackBar(
            'Access denied. Only event hosts can view analytics.', context);
        Navigator.pop(context);
      } else {
        // Load attendees data if authorized
        _loadAttendeesData();
      }
    } catch (e) {
      setState(() {
        _isAuthorized = false;
      });
      ShowToast().showSnackBar('Error checking authorization: $e', context);
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
      print('Error loading attendees: $e');
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
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(
                  'Checking authorization...',
                  style: TextStyle(
                    fontSize: Dimensions.fontSizeDefault,
                    color: AppThemeColor.darkBlueColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // App Bar
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Text(
                      'Event Analytics',
                      style: TextStyle(
                        fontSize: Dimensions.fontSizeLarge,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColor.darkBlueColor,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _exportData,
                    icon: const Icon(Icons.download),
                    tooltip: 'Export Data',
                  ),
                ],
              ),
            ),

            // Date Filter Chips
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('All Time'),
                    selected: _selectedDateFilter == 'all',
                    onSelected: (selected) {
                      setState(() {
                        _selectedDateFilter = 'all';
                      });
                    },
                    selectedColor: AppThemeColor.darkGreenColor,
                    checkmarkColor: Colors.white,
                  ),
                  FilterChip(
                    label: const Text('Last Week'),
                    selected: _selectedDateFilter == 'week',
                    onSelected: (selected) {
                      setState(() {
                        _selectedDateFilter = 'week';
                      });
                    },
                    selectedColor: AppThemeColor.darkGreenColor,
                    checkmarkColor: Colors.white,
                  ),
                  FilterChip(
                    label: const Text('Last Month'),
                    selected: _selectedDateFilter == 'month',
                    onSelected: (selected) {
                      setState(() {
                        _selectedDateFilter = 'month';
                      });
                    },
                    selectedColor: AppThemeColor.darkGreenColor,
                    checkmarkColor: Colors.white,
                  ),
                ],
              ),
            ),

            // Tab Bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: AppThemeColor.darkGreenColor,
                ),
                labelColor: Colors.white,
                unselectedLabelColor: AppThemeColor.darkBlueColor,
                tabs: const [
                  Tab(text: 'Overview'),
                  Tab(text: 'Trends'),
                  Tab(text: 'Users'),
                ],
              ),
            ),

            // Tab Bar View
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _overviewTab(),
                  _trendsTab(),
                  _usersTab(),
                ],
              ),
            ),

            // Compliance Notice
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.security,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Privacy & Compliance',
                        style: TextStyle(
                          fontSize: Dimensions.fontSizeDefault,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Data is aggregated without personal identifiers. Analytics are anonymized for privacy compliance.',
                    style: TextStyle(
                      fontSize: Dimensions.fontSizeSmall,
                      color: Colors.grey[600],
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
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.grey[400],
                ),
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
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.analytics_outlined,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No analytics data available',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                    fontFamily: 'Roboto',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Analytics will appear once attendees start signing in',
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
                  Icon(
                    Icons.history,
                    size: 64,
                    color: Colors.grey[400],
                  ),
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
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Total Attendees Card
              _analyticsCard(
                title: 'Total Attendees',
                value: '${data['totalAttendees'] ?? 0}',
                icon: Icons.people,
                color: const Color(0xFF4CAF50), // Green accent
                tooltip: 'Number of unique sign-ins',
              ),

              const SizedBox(height: 16),

              // Repeat Attendees Card
              _analyticsCard(
                title: 'Repeat Attendees',
                value: '${data['repeatAttendees'] ?? 0}',
                icon: Icons.repeat,
                color: const Color(0xFF4CAF50), // Green accent
                tooltip: 'Users who attended previous events by you',
              ),

              const SizedBox(height: 16),

              // Dropout Rate Card
              _analyticsCard(
                title: 'Dropout Rate',
                value: '${(data['dropoutRate'] ?? 0).toStringAsFixed(1)}%',
                icon: Icons.trending_down,
                color: const Color(0xFF4CAF50), // Green accent
                tooltip:
                    'Percentage of pre-registered who didn\'t attend ((Pre-registered - Attendees) / Pre-registered * 100)',
              ),

              const SizedBox(height: 16),

              // Last Updated
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last Updated',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColor.darkBlueColor,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      data['lastUpdated'] != null
                          ? _formatTimestamp(data['lastUpdated'])
                          : 'Never',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        fontFamily: 'Roboto',
                      ),
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

  Widget _trendsTab() {
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
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.grey[400],
                ),
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
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.trending_up,
                  size: 64,
                  color: Colors.grey[400],
                ),
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
                      color: Colors.grey.withOpacity(0.1),
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
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_attendeesList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: Colors.grey[400],
            ),
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

    // Calculate repeat vs new attendees
    final repeatAttendees = _attendeesList.where((attendee) {
      // This is a simplified calculation - in a real app you'd check against previous events
      return attendee.customerUid != 'manual' &&
          attendee.customerUid.isNotEmpty;
    }).length;

    final newAttendees = _attendeesList.length - repeatAttendees;

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
                  color: Colors.grey.withOpacity(0.1),
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
                  color: Colors.grey.withOpacity(0.1),
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
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _attendeesList.length,
                  itemBuilder: (context, index) {
                    final attendee = _attendeesList[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF4CAF50),
                        child: Text(
                          _getDisplayName(attendee)
                              .substring(0, 1)
                              .toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        _getDisplayName(attendee),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Roboto',
                        ),
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

  Widget _analyticsCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? tooltip,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
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
                    if (tooltip != null)
                      Tooltip(
                        message: tooltip,
                        child: Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontFamily: 'Roboto',
                  ),
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
            return FlLine(
              color: Colors.grey[300]!,
              strokeWidth: 1,
            );
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

  Future<void> _exportData() async {
    try {
      // Get analytics data
      final analyticsDoc = await FirebaseFirestore.instance
          .collection('event_analytics')
          .doc(widget.eventId)
          .get();

      if (!analyticsDoc.exists) {
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
          '${(analyticsData['dropoutRate'] ?? 0).toStringAsFixed(1)}%'
        ],
        [
          'Last Updated',
          analyticsData['lastUpdated'] != null
              ? _formatTimestamp(analyticsData['lastUpdated'])
              : 'Never'
        ],
      ];

      // Add hourly data
      final hourlySignIns =
          analyticsData['hourlySignIns'] as Map<String, dynamic>? ?? {};
      if (hourlySignIns.isNotEmpty) {
        csvData.add([]);
        csvData.add(['Hour', 'Sign-ins']);
        hourlySignIns.forEach((hour, count) {
          csvData.add([hour, count.toString()]);
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

      // Convert to CSV
      final csvString = const ListToCsvConverter().convert(csvData);

      // Save to temporary file
      final directory = await getTemporaryDirectory();
      final file =
          File('${directory.path}/event_analytics_${widget.eventId}.csv');
      await file.writeAsString(csvString);

      // Share file
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Event Analytics - ${widget.eventId}',
        text: 'Event analytics data exported from Orgami app',
      );

      ShowToast().showSnackBar('Data exported successfully', context);
    } catch (e) {
      ShowToast().showSnackBar('Error exporting data: $e', context);
    }
  }
}
