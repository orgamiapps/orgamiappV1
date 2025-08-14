import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:orgami/models/event_model.dart';
import 'package:orgami/models/ticket_model.dart';
import 'package:orgami/screens/Events/single_event_screen.dart';
import 'package:orgami/screens/Events/chose_date_time_screen.dart';
import 'package:orgami/Utils/Router.dart';
import 'package:orgami/Utils/Toast.dart';
import 'dart:async';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with TickerProviderStateMixin {
  // Core state
  DateTime _currentMonth = DateTime.now();
  DateTime? _selectedDate;
  String _filter = 'all'; // all, created, tickets, saved
  String _viewMode = 'month'; // month, week, day
  bool _isLoading = false;
  bool _isDayViewExpanded = false;
  
  // Data
  List<EventModel> _allEvents = [];
  List<EventModel> _filteredEvents = [];
  List<String> _savedEventIds = [];
  List<TicketModel> _myTickets = [];
  Map<String, EventModel> _eventsCache = {};
  
  // Search
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  
  // Animation controllers
  late AnimationController _monthAnimationController;
  late AnimationController _dayViewAnimationController;
  late Animation<double> _monthSlideAnimation;
  late Animation<double> _dayViewExpandAnimation;
  late Animation<double> _fadeAnimation;
  
  // Time tracking for live indicator
  Timer? _timeUpdateTimer;
  DateTime _currentTime = DateTime.now();
  
  // Scroll controllers
  final ScrollController _dayViewScrollController = ScrollController();
  final PageController _monthPageController = PageController(initialPage: 12);
  
  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadData();
    _startTimeUpdates();
    _selectedDate = DateTime.now();
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
    
    _monthSlideAnimation = Tween<double>(
      begin: 0.0,
      end: -0.3,
    ).animate(CurvedAnimation(
      parent: _monthAnimationController,
      curve: Curves.easeInOut,
    ));
    
    _dayViewExpandAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _dayViewAnimationController,
      curve: Curves.easeOutCubic,
    ));
    
    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _monthAnimationController,
      curve: Curves.easeIn,
    ));
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
    setState(() => _isLoading = true);
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      // Load events
      final eventsSnapshot = await FirebaseFirestore.instance
          .collection('Events')
          .where('status', isEqualTo: 'active')
          .orderBy('selectedDateTime')
          .get();
      
      _allEvents = eventsSnapshot.docs
          .map((doc) => EventModel.fromJson(doc))
          .toList();
      
      // Load saved events
      final savedSnapshot = await FirebaseFirestore.instance
          .collection('SavedEvents')
          .where('userId', isEqualTo: user.uid)
          .get();
      
      _savedEventIds = savedSnapshot.docs
          .map((doc) => doc.data()['eventId'] as String)
          .toList();
      
      // Load tickets
      final ticketsSnapshot = await FirebaseFirestore.instance
          .collection('Tickets')
          .where('customerUid', isEqualTo: user.uid)
          .get();
      
      _myTickets = ticketsSnapshot.docs
          .map((doc) => TicketModel.fromJson(doc.data()))
          .toList();
      
      // Cache events by ID
      for (var event in _allEvents) {
        _eventsCache[event.id] = event;
      }
      
      _applyFilter();
    } catch (e) {
      showToast('Error loading events: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  void _applyFilter() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _filteredEvents = [];
      return;
    }
    
    setState(() {
      switch (_filter) {
        case 'created':
          _filteredEvents = _allEvents
              .where((e) => e.customerUid == user.uid)
              .toList();
          break;
        case 'tickets':
          final ticketEventIds = _myTickets.map((t) => t.eventId).toSet();
          _filteredEvents = _allEvents
              .where((e) => ticketEventIds.contains(e.id))
              .toList();
          break;
        case 'saved':
          _filteredEvents = _allEvents
              .where((e) => _savedEventIds.contains(e.id))
              .toList();
          break;
        default:
          _filteredEvents = List.from(_allEvents);
      }
      
      // Apply search filter
      if (_searchController.text.isNotEmpty) {
        final query = _searchController.text.toLowerCase();
        _filteredEvents = _filteredEvents.where((e) =>
            e.title.toLowerCase().contains(query) ||
            e.description.toLowerCase().contains(query) ||
            e.location.toLowerCase().contains(query)
        ).toList();
      }
    });
  }
  
  List<EventModel> _getEventsForDay(DateTime day) {
    return _filteredEvents.where((event) {
      final eventDate = event.selectedDateTime;
      return eventDate.year == day.year &&
          eventDate.month == day.month &&
          eventDate.day == day.day;
    }).toList();
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
    
    // Scroll to current hour if today
    if (_isSameDay(day, DateTime.now())) {
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
          scrollPosition.clamp(0.0, _dayViewScrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
        );
      }
    });
  }
  
  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
  
  @override
  void dispose() {
    _monthAnimationController.dispose();
    _dayViewAnimationController.dispose();
    _timeUpdateTimer?.cancel();
    _searchController.dispose();
    _dayViewScrollController.dispose();
    _monthPageController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(),
                if (!_isDayViewExpanded) _buildFilters(),
                Expanded(
                  child: Stack(
                    children: [
                      // Month view
                      AnimatedBuilder(
                        animation: _monthAnimationController,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(0, _monthSlideAnimation.value * MediaQuery.of(context).size.height),
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
                color: Colors.black.withOpacity(0.3),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667EEA)),
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: _buildFAB(),
    );
  }
  
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (_isDayViewExpanded)
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios, size: 20),
                  onPressed: _closeDayView,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
              Expanded(
                child: Text(
                  _isDayViewExpanded && _selectedDate != null
                      ? DateFormat('EEEE, MMMM d').format(_selectedDate!)
                      : DateFormat('MMMM yyyy').format(_currentMonth),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.search, size: 24),
                onPressed: () => setState(() => _isSearching = !_isSearching),
                color: const Color(0xFF667EEA),
              ),
              IconButton(
                icon: const Icon(Icons.today, size: 24),
                onPressed: () {
                  setState(() {
                    _currentMonth = DateTime.now();
                    _selectedDate = DateTime.now();
                  });
                  if (_isDayViewExpanded) {
                    _scrollToCurrentTime();
                  }
                },
                color: const Color(0xFF667EEA),
              ),
            ],
          ),
          if (_isSearching)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search events...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      _searchController.clear();
                      _applyFilter();
                    },
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF3F4F6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onChanged: (_) => _applyFilter(),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildFilters() {
    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _buildFilterChip('All', 'all'),
          const SizedBox(width: 8),
          _buildFilterChip('Created', 'created'),
          const SizedBox(width: 8),
          _buildFilterChip('Tickets', 'tickets'),
          const SizedBox(width: 8),
          _buildFilterChip('Saved', 'saved'),
        ],
      ),
    );
  }
  
  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filter == value;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _filter = value);
        _applyFilter();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF667EEA) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF667EEA) : const Color(0xFFE5E7EB),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF6B7280),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
  
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
        children: weekDays.map((day) => SizedBox(
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
        )).toList(),
      ),
    );
  }
  
  Widget _buildMonthGrid(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    final startWeekday = firstDay.weekday % 7;
    final daysInMonth = lastDay.day;
    
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: 42,
      itemBuilder: (context, index) {
        if (index < startWeekday || index >= startWeekday + daysInMonth) {
          return const SizedBox();
        }
        
        final day = DateTime(month.year, month.month, index - startWeekday + 1);
        final events = _getEventsForDay(day);
        final isToday = _isSameDay(day, DateTime.now());
        final isSelected = _selectedDate != null && _isSameDay(day, _selectedDate!);
        
        return GestureDetector(
          onTap: () => _onDayTapped(day),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF667EEA)
                  : isToday
                      ? const Color(0xFF667EEA).withOpacity(0.1)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? Colors.white
                        : isToday
                            ? const Color(0xFF667EEA)
                            : const Color(0xFF1A1A1A),
                  ),
                ),
                if (events.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        events.length > 3 ? 3 : events.length,
                        (i) => Container(
                          width: 4,
                          height: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF667EEA),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildAgendaView() {
    final events = _selectedDate != null ? _getEventsForDay(_selectedDate!) : [];
    
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: () => _createEvent(),
                          icon: const Icon(Icons.add, size: 20),
                          label: const Text('Create Event'),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF667EEA),
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
    final events = _selectedDate != null ? _getEventsForDay(_selectedDate!) : [];
    
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
            child: Stack(
              children: [
                // Hour lines and events
                ListView.builder(
                  controller: _dayViewScrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: 24,
                  itemBuilder: (context, hour) {
                    final hourEvents = events.where((e) {
                      final eventHour = e.selectedDateTime.hour;
                      return eventHour == hour;
                    }).toList();
                    
                    return SizedBox(
                      height: 80,
                      child: Row(
                        children: [
                          // Time label
                          SizedBox(
                            width: 50,
                            child: Text(
                              DateFormat('h a').format(
                                DateTime(2024, 1, 1, hour),
                              ),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF9CA3AF),
                              ),
                            ),
                          ),
                          // Hour content
                          Expanded(
                            child: Stack(
                              children: [
                                // Hour line
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    height: 1,
                                    color: const Color(0xFFE5E7EB),
                                  ),
                                ),
                                // Events for this hour
                                ...hourEvents.map((event) {
                                  final duration = event.eventDuration;
                                  final height = duration * 80.0;
                                  
                                  return Positioned(
                                    top: 2,
                                    left: 0,
                                    right: 0,
                                    child: GestureDetector(
                                      onTap: () => _openEvent(event),
                                      child: Container(
                                        height: height - 4,
                                        margin: const EdgeInsets.only(right: 4),
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF667EEA).withOpacity(0.9),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              event.title,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (duration > 1)
                                              Text(
                                                event.location,
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 12,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                // Current time indicator
                if (_selectedDate != null && _isSameDay(_selectedDate!, DateTime.now()))
                  Positioned(
                    top: (_currentTime.hour * 80.0) + (_currentTime.minute * 80.0 / 60),
                    left: 70,
                    right: 20,
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Container(
                            height: 2,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (events.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(
                    Icons.event_available,
                    size: 48,
                    color: Color(0xFF9CA3AF),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No events scheduled',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _createEvent(),
                    icon: const Icon(Icons.add),
                    label: const Text('Create Event'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF667EEA),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
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
  
  Widget _buildEventCard(EventModel event) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
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
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF9CA3AF),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildFAB() {
    return FloatingActionButton(
      onPressed: () => _createEvent(),
      backgroundColor: const Color(0xFF667EEA),
      child: const Icon(Icons.add, color: Colors.white),
    );
  }
  
  void _openEvent(EventModel event) {
    HapticFeedback.lightImpact();
    RouterClass.nextScreenNormal(
      context,
      SingleEventScreen(eventModel: event),
    );
  }
  
  void _createEvent() {
    HapticFeedback.mediumImpact();
    RouterClass.nextScreenNormal(
      context,
      ChoseDateTimeScreen(
        preselectedOrganizationId: null,
        forceOrganizationEvent: false,
      ),
    ).then((_) => _loadData());
  }
}