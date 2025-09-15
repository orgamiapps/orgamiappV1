import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/Events/single_event_screen.dart';
import 'package:attendus/screens/Events/chose_sign_in_methods_screen.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/widgets/month_year_picker.dart';
import 'package:attendus/widgets/app_scaffold_wrapper.dart';
import 'dart:async';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // Core state
  DateTime _currentMonth = DateTime.now();
  DateTime? _selectedDate;
  bool _isLoading = false;
  bool _isDayViewExpanded = false;

  // Data
  List<EventModel> _allEvents = [];
  List<EventModel> _filteredEvents = [];

  // Search removed per request

  // Animation controllers
  late AnimationController _monthAnimationController;
  late AnimationController _dayViewAnimationController;
  late Animation<double> _monthSlideAnimation;
  late Animation<double> _dayViewExpandAnimation;
  late Animation<double> _fadeAnimation;

  // Time tracking for live indicator
  Timer? _timeUpdateTimer;
  Timer? _dataRefreshTimer;
  DateTime _currentTime = DateTime.now();

  // Scroll controllers
  final ScrollController _dayViewScrollController = ScrollController();
  final PageController _monthPageController = PageController(initialPage: 12);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAnimations();
    _loadData();
    _startTimeUpdates();
    _startDataRefresh();
    _selectedDate = DateTime.now();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh data when app comes back to foreground
      _loadData();
    }
  }

  void _startDataRefresh() {
    // Refresh data every 30 seconds to keep calendar up to date
    _dataRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _loadData();
      }
    });
  }

  void _initializeAnimations() {
    _monthAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _dayViewAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _monthSlideAnimation = Tween<double>(begin: 0.0, end: -0.3).animate(
      CurvedAnimation(
        parent: _monthAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _dayViewExpandAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _dayViewAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _monthAnimationController, curve: Curves.easeIn),
    );
  }

  void _startTimeUpdates() {
    _timeUpdateTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return;
      }

      // Load ALL events without filters to avoid permission issues
      try {
        // Try simplest query first - no ordering, no filters
        final eventsSnapshot = await FirebaseFirestore.instance
            .collection('Events')
            .get();

        _allEvents = [];
        for (var doc in eventsSnapshot.docs) {
          try {
            final event = EventModel.fromJson(doc);
            // Add all events regardless of status to show past events too
            _allEvents.add(event);
          } catch (e) {
            // Skip malformed events and continue loading others
          }
        }

        // Sort events by date
        _allEvents.sort(
          (a, b) => a.selectedDateTime.compareTo(b.selectedDateTime),
        );
      } catch (e) {
        // Try to load user's own events at least
        try {
          final userEventsSnapshot = await FirebaseFirestore.instance
              .collection('Events')
              .where('customerUid', isEqualTo: user.uid)
              .get();

          _allEvents = userEventsSnapshot.docs
              .map((doc) {
                try {
                  return EventModel.fromJson(doc);
                } catch (e) {
                  return null;
                }
              })
              .where((event) => event != null)
              .cast<EventModel>()
              .toList();

          _allEvents.sort(
            (a, b) => a.selectedDateTime.compareTo(b.selectedDateTime),
          );
        } catch (userEventsError) {
          _allEvents = [];
        }
      }

      // No additional per-user filters required; calendar always shows all events

      _applyFilter();
    } catch (e) {
      if (mounted) {
        ShowToast().showNormalToast(msg: 'Error loading data: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyFilter() {
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _filteredEvents = [];
      return;
    }

    setState(() {
      _filteredEvents = List.from(_allEvents);
    });
  }

  List<EventModel> _getEventsForDay(DateTime day) {
    final dayEvents = _filteredEvents.where((event) {
      final eventDate = event.selectedDateTime;
      final isSameDay =
          eventDate.year == day.year &&
          eventDate.month == day.month &&
          eventDate.day == day.day;
      // Event found for this day
      return isSameDay;
    }).toList();

    return dayEvents;
  }

  void _onDayTapped(DateTime day) {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedDate = day;
      _isDayViewExpanded = true;
    });

    // Animate to day view
    _monthAnimationController.forward();
    _dayViewAnimationController.forward();

    // Scroll to first event if present; otherwise, to current time when today
    final hasEvents = _getEventsForDay(day).isNotEmpty;
    if (hasEvents) {
      _scrollToFirstEvent(day);
    } else if (_isSameDay(day, DateTime.now())) {
      _scrollToCurrentTime();
    }
  }

  void _closeDayView() {
    HapticFeedback.lightImpact();
    _monthAnimationController.reverse();
    _dayViewAnimationController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _isDayViewExpanded = false;
        });
      }
    });
  }

  void _scrollToCurrentTime() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_dayViewScrollController.hasClients) {
        final currentHour = _currentTime.hour;
        final scrollPosition = currentHour * 80.0 - 100;
        _dayViewScrollController.animateTo(
          scrollPosition.clamp(
            0.0,
            _dayViewScrollController.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _scrollToFirstEvent(DateTime day) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_dayViewScrollController.hasClients) return;
      final events = _getEventsForDay(day);
      if (events.isEmpty) return;
      events.sort((a, b) => a.selectedDateTime.compareTo(b.selectedDateTime));
      final first = events.first.selectedDateTime;
      final position = (first.hour * 80.0) + (first.minute * 80.0 / 60) - 100;
      _dayViewScrollController.animateTo(
        position.clamp(0.0, _dayViewScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
      );
    });
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _showMonthYearPicker() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MonthYearPickerSheet(
        initialDate: _currentMonth,
        onDateSelected: (DateTime selectedDate) {
          setState(() {
            _currentMonth = selectedDate;
            // Calculate the page index for the selected month
            final now = DateTime.now();
            final monthDiff =
                (selectedDate.year - now.year) * 12 +
                (selectedDate.month - now.month);
            final pageIndex = 12 + monthDiff;
            _monthPageController.jumpToPage(pageIndex);
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _monthAnimationController.dispose();
    _dayViewAnimationController.dispose();
    _timeUpdateTimer?.cancel();
    _dataRefreshTimer?.cancel();
    _dayViewScrollController.dispose();
    _monthPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffoldWrapper(
      selectedBottomNavIndex: 0, // Home tab
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: Stack(
                    children: [
                      // Month view
                      AnimatedBuilder(
                        animation: _monthAnimationController,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(
                              0,
                              _monthSlideAnimation.value *
                                  MediaQuery.of(context).size.height,
                            ),
                            child: FadeTransition(
                              opacity: _fadeAnimation,
                              child: _buildMonthView(),
                            ),
                          );
                        },
                      ),
                      // Day view overlay
                      if (_isDayViewExpanded)
                        AnimatedBuilder(
                          animation: _dayViewAnimationController,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _dayViewExpandAnimation.value,
                              alignment: Alignment.topCenter,
                              child: Opacity(
                                opacity: _dayViewExpandAnimation.value,
                                child: _buildDayView(),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (_isLoading)
              Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF667EEA),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Back button - always visible
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 20),
                onPressed: _isDayViewExpanded
                    ? _closeDayView
                    : () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: _isDayViewExpanded ? null : _showMonthYearPicker,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final bool useCompactFormat = constraints.maxWidth < 300;
                      final String title =
                          _isDayViewExpanded && _selectedDate != null
                          ? DateFormat(
                              useCompactFormat ? 'EEE, MMM d' : 'EEEE, MMMM d',
                            ).format(_selectedDate!)
                          : DateFormat(
                              useCompactFormat ? 'MMM yyyy' : 'MMMM yyyy',
                            ).format(_currentMonth);
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              switchInCurve: Curves.easeOut,
                              switchOutCurve: Curves.easeIn,
                              child: Text(
                                title,
                                key: ValueKey<String>(title),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),
                            ),
                          ),
                          if (!_isDayViewExpanded) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.keyboard_arrow_down,
                              size: 28,
                              color: Color(0xFF667EEA),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 28),
                onPressed: _createEvent,
                color: const Color(0xFF667EEA),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Filter chips removed per UX: calendar always shows all events

  Widget _buildMonthView() {
    return Column(
      children: [
        _buildWeekDayHeaders(),
        Expanded(
          child: PageView.builder(
            controller: _monthPageController,
            onPageChanged: (index) {
              setState(() {
                _currentMonth = DateTime(
                  DateTime.now().year,
                  DateTime.now().month - 12 + index,
                );
              });
            },
            itemBuilder: (context, index) {
              final month = DateTime(
                DateTime.now().year,
                DateTime.now().month - 12 + index,
              );
              return _buildMonthGrid(month);
            },
          ),
        ),
        if (_selectedDate != null) _buildAgendaView(),
      ],
    );
  }

  Widget _buildWeekDayHeaders() {
    final weekDays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: weekDays
            .map(
              (day) => SizedBox(
                width: 40,
                child: Center(
                  child: Text(
                    day,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildMonthGrid(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    final startWeekday = firstDay.weekday % 7;
    final daysInMonth = lastDay.day;

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 0.88, // Optimized for event indicators
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: 42,
      itemBuilder: (context, index) {
        if (index < startWeekday || index >= startWeekday + daysInMonth) {
          return const SizedBox();
        }

        final day = DateTime(month.year, month.month, index - startWeekday + 1);
        final events = _getEventsForDay(day);
        final isToday = _isSameDay(day, DateTime.now());
        final isSelected =
            _selectedDate != null && _isSameDay(day, _selectedDate!);

        // Sort events by time for display
        events.sort((a, b) => a.selectedDateTime.compareTo(b.selectedDateTime));

        return GestureDetector(
          onTap: () => _onDayTapped(day),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF667EEA)
                  : isToday
                  ? const Color(0xFF667EEA).withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Day number
                Flexible(
                  child: Container(
                    alignment: Alignment.center,
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isToday ? FontWeight.bold : FontWeight.w600,
                        color: isSelected
                            ? Colors.white
                            : isToday
                            ? const Color(0xFF667EEA)
                            : const Color(0xFF374151),
                      ),
                    ),
                  ),
                ),
                // Event indicator section with proper spacing
                if (events.isNotEmpty)
                  Container(
                    height: 16, // Fixed height for consistency
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Event dot indicator
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white
                                : events.any((e) => e.ticketsEnabled)
                                ? const Color(0xFF10B981)
                                : events.any((e) => e.private)
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF667EEA),
                            shape: BoxShape.circle,
                            boxShadow: !isSelected
                                ? [
                                    BoxShadow(
                                      color:
                                          (events.any((e) => e.ticketsEnabled)
                                                  ? const Color(0xFF10B981)
                                                  : events.any((e) => e.private)
                                                  ? const Color(0xFFEF4444)
                                                  : const Color(0xFF667EEA))
                                              .withValues(alpha: 0.3),
                                      blurRadius: 2,
                                      spreadRadius: 0,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        // Event count badge for multiple events
                        if (events.length > 1) ...[
                          const SizedBox(width: 2),
                          Container(
                            constraints: const BoxConstraints(minWidth: 18),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 0.5,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.25)
                                  : const Color(
                                      0xFF6B7280,
                                    ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.white.withValues(alpha: 0.3)
                                    : const Color(
                                        0xFF6B7280,
                                      ).withValues(alpha: 0.15),
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              '+${events.length - 1}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFF374151),
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                else
                  const SizedBox(height: 16), // Maintain consistent spacing
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAgendaView() {
    final events = _selectedDate != null
        ? _getEventsForDay(_selectedDate!)
        : [];

    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: events.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.event_busy,
                          size: 48,
                          color: Color(0xFF9CA3AF),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'No events',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      return _buildEventCard(event);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayView() {
    final events = _selectedDate != null
        ? _getEventsForDay(_selectedDate!)
        : [];

    // Sort events by start time
    events.sort((a, b) => a.selectedDateTime.compareTo(b.selectedDateTime));

    // Check if selected date is today / future
    final isToday =
        _selectedDate != null && _isSameDay(_selectedDate!, DateTime.now());
    // Future/past distinction not needed for UI anymore

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        // Swipe to change days
        if (details.primaryVelocity != null && _selectedDate != null) {
          if (details.primaryVelocity! < -300) {
            // Swipe left - next day
            setState(() {
              _selectedDate = _selectedDate!.add(const Duration(days: 1));
            });
            // After date change, scroll to first event if any
            _scrollToFirstEvent(_selectedDate!);
            HapticFeedback.lightImpact();
          } else if (details.primaryVelocity! > 300) {
            // Swipe right - previous day
            setState(() {
              _selectedDate = _selectedDate!.subtract(const Duration(days: 1));
            });
            // After date change, scroll to first event if any
            _scrollToFirstEvent(_selectedDate!);
            HapticFeedback.lightImpact();
          }
        }
      },
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: CustomScrollView(
                controller: _dayViewScrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: Container(
                      height: 24 * 80.0, // Total height for 24 hours
                      margin: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        bottom: 80,
                      ),
                      child: Stack(
                        children: [
                          // Hour lines and labels
                          Column(
                            children: List.generate(24, (hour) {
                              return Container(
                                height: 80,
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(
                                      color: hour == 0
                                          ? const Color(0xFFD1D5DB)
                                          : const Color(0xFFE5E7EB),
                                      width: hour == 0 ? 1.5 : 1,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Time label
                                    SizedBox(
                                      width: 56,
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          hour == 0
                                              ? '12 AM'
                                              : hour < 12
                                              ? '$hour AM'
                                              : hour == 12
                                              ? '12 PM'
                                              : '${hour - 12} PM',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: const Color(0xFF6B7280),
                                            fontWeight: hour == 0 || hour == 12
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Space for events
                                    const Expanded(child: SizedBox()),
                                  ],
                                ),
                              );
                            }),
                          ),
                          // Events overlay
                          ...events.map((event) => _buildEventBlock(event)),
                          // Current time indicator (only if today)
                          if (isToday)
                            Positioned(
                              top:
                                  (_currentTime.hour * 80.0) +
                                  (_currentTime.minute * 80.0 / 60),
                              left: 0,
                              right: 0,
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFEF4444),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      height: 2,
                                      color: const Color(0xFFEF4444),
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
          ],
        ),
      ),
    );
  }

  Widget _buildEventBlock(EventModel event) {
    final startHour = event.selectedDateTime.hour;
    final startMinute = event.selectedDateTime.minute;
    final duration = event.eventDuration > 0
        ? event.eventDuration
        : 1.0; // Minimum 1 hour height

    // Calculate position and height
    final topPosition = (startHour * 80.0) + (startMinute * 80.0 / 60);
    final eventHeight = (duration * 80.0).clamp(
      30.0,
      double.infinity,
    ); // Minimum height

    // Generate a color based on event properties
    final eventColor = _getEventColor(event);

    return Positioned(
      top: topPosition + 2,
      left: 60,
      right: 4,
      height: eventHeight - 4,
      child: GestureDetector(
        onTap: () => _openEvent(event),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: eventColor.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: eventColor, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: eventColor.withValues(alpha: 0.3),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      event.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: eventHeight > 50 ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (event.ticketsEnabled && eventHeight > 40)
                    Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.confirmation_number,
                        size: 10,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
              if (eventHeight > 50 && event.location.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 10,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        event.location,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (eventHeight > 70) ...[
                const SizedBox(height: 2),
                Text(
                  DateFormat('h:mm a').format(event.selectedDateTime),
                  style: const TextStyle(color: Colors.white60, fontSize: 10),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Removed empty day message per UX: show hours grid only with no message

  // Helper method to get event color based on type/category
  Color _getEventColor(EventModel event) {
    // You can customize this based on event categories or other properties
    if (event.ticketsEnabled) {
      return const Color(0xFF10B981); // Green for ticketed events
    } else if (event.private) {
      return const Color(0xFFEF4444); // Red for private events
    } else if (event.organizationId != null) {
      return const Color(0xFF3B82F6); // Blue for organization events
    } else {
      return const Color(0xFF667EEA); // Default violet
    }
  }

  Widget _buildEventCard(EventModel event) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _openEvent(event),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('h:mm a').format(event.selectedDateTime),
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.location_on,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            event.location,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
            ],
          ),
        ),
      ),
    );
  }

  // FAB removed; action moved to header

  void _openEvent(EventModel event) {
    HapticFeedback.lightImpact();
    RouterClass.nextScreenNormal(context, SingleEventScreen(eventModel: event));
  }

  void _createEvent() async {
    HapticFeedback.mediumImpact();
    await RouterClass.nextScreenNormal(
      context,
      const ChoseSignInMethodsScreen(),
    );
    // Always refresh when returning from event creation
    if (mounted) {
      _loadData();
    }
  }
}
