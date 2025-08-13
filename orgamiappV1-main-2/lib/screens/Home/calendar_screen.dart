import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:orgami/Utils/colors.dart';
import 'package:orgami/Utils/router.dart';
import 'package:orgami/models/event_model.dart';
import 'package:orgami/models/ticket_model.dart';
import 'package:orgami/firebase/firebase_firestore_helper.dart';
import 'package:orgami/screens/Events/single_event_screen.dart';
import 'package:orgami/screens/MyProfile/my_tickets_screen.dart';
import 'package:orgami/Services/notification_service.dart';
import 'package:orgami/screens/Events/chose_date_time_screen.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/services.dart';

enum CalendarFilter { all, created, tickets, saved }

enum ViewMode { month, week, day }

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDate = DateTime.now();
  CalendarFilter _filter = CalendarFilter.all;
  ViewMode _viewMode = ViewMode.month;

  String _searchQuery = '';
  final TextEditingController _searchCtlr = TextEditingController();

  bool _loading = false;
  bool _agendaExpanded = true;

  // Data sources
  List<EventModel> _createdEvents = [];
  List<EventModel> _savedEvents = [];
  List<TicketModel> _ticketModels = [];
  final Map<String, EventModel> _eventCache = {};
  late EventController _eventController;
  late PageController _monthPageController;
  static const int _kMonthPageCount = 1200;
  static const int _kMonthBaseIndex = _kMonthPageCount ~/ 2;
  late DateTime _pagerAnchorMonth;

  int get _monthPageIndex => _monthPageController.hasClients
      ? _monthPageController.page?.round() ?? _kMonthBaseIndex
      : _kMonthBaseIndex;

  @override
  void initState() {
    super.initState();
    _loadData();
    _eventController = EventController();
    _monthPageController = PageController(initialPage: _kMonthBaseIndex);
    _pagerAnchorMonth = DateTime(_currentMonth.year, _currentMonth.month);
  }

  @override
  void dispose() {
    _searchCtlr.dispose();
    _monthPageController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _createdEvents = [];
        _savedEvents = [];
        _ticketModels = [];
      });
      return;
    }

    setState(() => _loading = true);
    try {
      // Load created events (creator and co-host)
      final created = await _fetchCreatedAndCoHostedEvents(uid);

      // Load saved events
      final saved = await FirebaseFirestoreHelper().getFavoritedEvents(
        userId: uid,
      );

      // Load tickets
      final tickets = await FirebaseFirestoreHelper().getUserTickets(
        customerUid: uid,
      );

      setState(() {
        _createdEvents = created;
        _savedEvents = saved;
        _ticketModels = tickets;
      });

      Map<String, EventModel> ticketEvents = {};
      for (final t in _ticketModels) {
        final id = t.eventId;
        if (_eventCache.containsKey(id)) {
          ticketEvents[id] = _eventCache[id]!;
        } else {
          final e = await FirebaseFirestoreHelper().getSingleEvent(id);
          if (e != null) {
            _eventCache[id] = e;
            ticketEvents[id] = e;
          }
        }
      }
      _eventController.removeWhere((e) => true);
      for (final e in _createdEvents) {
        _eventController.add(
          CalendarEventData(
            date: e.selectedDateTime,
            startTime: e.selectedDateTime,
            endTime:
                e.eventEndTime ??
                e.selectedDateTime.add(const Duration(hours: 2)),
            title: e.title,
            description: e.description ?? '',
            color: const Color(0xFF10B981),
          ),
        );
      }
      for (final e in _savedEvents) {
        _eventController.add(
          CalendarEventData(
            date: e.selectedDateTime,
            startTime: e.selectedDateTime,
            endTime:
                e.eventEndTime ??
                e.selectedDateTime.add(const Duration(hours: 2)),
            title: e.title,
            description: e.description ?? '',
            color: const Color(0xFF8B5CF6),
          ),
        );
      }
      for (final e in ticketEvents.values) {
        _eventController.add(
          CalendarEventData(
            date: e.selectedDateTime,
            startTime: e.selectedDateTime,
            endTime:
                e.eventEndTime ??
                e.selectedDateTime.add(const Duration(hours: 2)),
            title: e.title,
            description: e.description ?? '',
            color: const Color(0xFF3B82F6),
          ),
        );
      }
    } catch (_) {
      // Ignore errors; show what we can
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<EventModel>> _fetchCreatedAndCoHostedEvents(String uid) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final createdSnap = await firestore
          .collection(EventModel.firebaseKey)
          .where('customerUid', isEqualTo: uid)
          .limit(500)
          .get();
      final cohostSnap = await firestore
          .collection(EventModel.firebaseKey)
          .where('coHosts', arrayContains: uid)
          .limit(500)
          .get();

      final allDocs = <DocumentSnapshot>{
        ...createdSnap.docs,
        ...cohostSnap.docs,
      };
      final events = allDocs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        data['id'] = d.id;
        return EventModel.fromJson(data);
      }).toList();

      return events;
    } catch (_) {
      return [];
    }
  }

  // Helpers for calendar
  DateTime _startOfMonth(DateTime d) => DateTime(d.year, d.month);
  DateTime _endOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);

  int _daysInMonth(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

  DateTime _truncateDate(DateTime d) => DateTime(d.year, d.month, d.day);

  // Build a map of date -> items for markers and agenda
  Map<DateTime, List<_CalendarItem>> get _dateToItems {
    final Map<DateTime, List<_CalendarItem>> map = {};

    void addItem(DateTime date, _CalendarItem item) {
      final key = _truncateDate(date);
      map.putIfAbsent(key, () => []);
      map[key]!.add(item);
    }

    Iterable<EventModel> created = _createdEvents;
    Iterable<EventModel> saved = _savedEvents;

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      bool matchesEvent(EventModel e) =>
          e.title.toLowerCase().contains(q) ||
          e.description.toLowerCase().contains(q) ||
          e.location.toLowerCase().contains(q);
      created = created.where(matchesEvent);
      saved = saved.where(matchesEvent);
    }

    for (final e in created) {
      addItem(e.selectedDateTime, _CalendarItem.created(e));
    }
    for (final e in saved) {
      addItem(e.selectedDateTime, _CalendarItem.saved(e));
    }
    for (final t in _ticketModels) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!(t.eventTitle.toLowerCase().contains(q) ||
            t.eventLocation.toLowerCase().contains(q))) {
          continue;
        }
      }
      addItem(t.eventDateTime, _CalendarItem.ticket(t));
    }
    return map;
  }

  List<_CalendarItem> _itemsForDate(DateTime date) {
    final items = _dateToItems[_truncateDate(date)] ?? [];
    switch (_filter) {
      case CalendarFilter.created:
        return items.where((i) => i.type == _CalendarItemType.created).toList();
      case CalendarFilter.tickets:
        return items.where((i) => i.type == _CalendarItemType.ticket).toList();
      case CalendarFilter.saved:
        return items.where((i) => i.type == _CalendarItemType.saved).toList();
      case CalendarFilter.all:
      default:
        return items;
    }
  }

  Color _markerColorFor(_CalendarItemType t) {
    // Unified color for all events in month view to match requested design
    return const Color(0xFF8B5CF6); // violet
  }

  String _labelForFilter(CalendarFilter f) {
    switch (f) {
      case CalendarFilter.created:
        return 'Created';
      case CalendarFilter.tickets:
        return 'Tickets';
      case CalendarFilter.saved:
        return 'Saved';
      case CalendarFilter.all:
      default:
        return 'All';
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat.yMMMM().format(_currentMonth);
    final selectedItems = _itemsForDate(_selectedDate);

    Widget calendarWidget = switch (_viewMode) {
      ViewMode.month => _buildMonthPager(context),
      ViewMode.week => _buildWeekRow(),
      ViewMode.day => _buildDayView(),
    };

    return Scaffold
(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Calendar',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: switch (_viewMode) {
              ViewMode.month => 'Week view',
              ViewMode.week => 'Day view',
              ViewMode.day => 'Month view',
            },
            icon: Icon(switch (_viewMode) {
              ViewMode.month => Icons.view_week,
              ViewMode.week => Icons.view_day,
              ViewMode.day => Icons.calendar_month,
            }),
            onPressed: () => setState(() {
              _viewMode = switch (_viewMode) {
                ViewMode.month => ViewMode.week,
                ViewMode.week => ViewMode.day,
                ViewMode.day => ViewMode.month,
              };
            }),
          ),
          IconButton(
            tooltip: 'Jump to date',
            icon: const Icon(Icons.date_range),
            onPressed: _jumpToDate,
          ),
          IconButton(
            tooltip: 'Today',
            icon: const Icon(Icons.today),
            onPressed: () {
              if (_viewMode == ViewMode.month) {
                _monthPageController.jumpToPage(_kMonthBaseIndex);
              }
              setState(() {
                _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
                _selectedDate = DateTime.now();
              });
              HapticFeedback.selectionClick();
            },
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadData,
          ),
          IconButton(
            tooltip: 'Add event',
            icon: const Icon(Icons.add),
            onPressed: () {
              HapticFeedback.heavyImpact();
              RouterClass.nextScreenNormal(context, const ChoseDateTimeScreen());
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildSearchBar()),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedHeaderDelegate(
                  minExtent: 56,
                  maxExtent: 64,
                  builder: (context, shrink, overlaps) => _buildHeader(),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              if (_viewMode == ViewMode.month)
                SliverToBoxAdapter(child: _buildWeekdayHeader()),
              SliverToBoxAdapter(child: calendarWidget),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverToBoxAdapter(child: _buildAgendaCollapsible(selectedItems)),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _jumpToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    if (_viewMode == ViewMode.month) {
      final monthsFromAnchor =
          (picked.year - _pagerAnchorMonth.year) * 12 + (picked.month - _pagerAnchorMonth.month);
      final target = (_kMonthBaseIndex + monthsFromAnchor).clamp(0, _kMonthPageCount - 1);
      _monthPageController.jumpToPage(target);
    }
    setState(() {
      _currentMonth = DateTime(picked.year, picked.month);
      _selectedDate = picked;
    });
    HapticFeedback.selectionClick();
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: Color(0xFF64748B)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtlr,
              decoration: const InputDecoration(
                hintText: 'Search events by title, location, or description',
                border: InputBorder.none,
              ),
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchCtlr.clear();
                setState(() => _searchQuery = '');
              },
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    String label = '';
    switch (_viewMode) {
      case ViewMode.month:
        label = DateFormat.yMMMM().format(_currentMonth);
        break;
      case ViewMode.week:
        final start = _selectedDate.subtract(
          Duration(days: _selectedDate.weekday % 7),
        );
        final end = start.add(Duration(days: 6));
        label =
            '${DateFormat.MMMd().format(start)} - ${DateFormat.MMMd().format(end)}';
        break;
      case ViewMode.day:
        label = DateFormat.yMMMMEEEEd().format(_selectedDate);
        break;
    }
    final Color primary = const Color(0xFF667EEA);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous',
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              if (_viewMode == ViewMode.month) {
                final target = (_monthPageIndex - 1).clamp(0, _kMonthPageCount - 1);
                _monthPageController.animateToPage(
                  target,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                );
              } else {
                setState(() {
                  switch (_viewMode) {
                    case ViewMode.week:
                      _selectedDate = _selectedDate.subtract(const Duration(days: 7));
                      break;
                    case ViewMode.day:
                      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                      break;
                    case ViewMode.month:
                      break;
                  }
                });
              }
            },
          ),
          Expanded(
            child: Center(
              child: _viewMode == ViewMode.month
                  ? _buildFadingMonthLabel()
                  : Text(
                      label,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E293B),
                      ),
                    ),
            ),
          ),
          IconButton(
            tooltip: 'Next',
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              if (_viewMode == ViewMode.month) {
                final target = (_monthPageIndex + 1).clamp(0, _kMonthPageCount - 1);
                _monthPageController.animateToPage(
                  target,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                );
              } else {
                setState(() {
                  switch (_viewMode) {
                    case ViewMode.week:
                      _selectedDate = _selectedDate.add(const Duration(days: 7));
                      break;
                    case ViewMode.day:
                      _selectedDate = _selectedDate.add(const Duration(days: 1));
                      break;
                    case ViewMode.month:
                      break;
                  }
                });
              }
            },
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () {
              if (_viewMode == ViewMode.month) {
                _monthPageController.jumpToPage(_kMonthBaseIndex);
              }
              setState(() {
                _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
                _selectedDate = DateTime.now();
              });
            },
            icon: const Icon(
              Icons.calendar_today,
              size: 16,
              color: Color(0xFF667EEA),
            ),
            label: const Text(
              'Today',
              style: TextStyle(
                color: Color(0xFF667EEA),
                fontWeight: FontWeight.bold,
              ),
            ),
            style: TextButton.styleFrom(foregroundColor: primary),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final chips = [
      CalendarFilter.all,
      CalendarFilter.created,
      CalendarFilter.tickets,
      CalendarFilter.saved,
    ];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: chips.map((f) => _buildFilterChip(f)).toList(),
      ),
    );
  }

  Widget _buildFilterChip(CalendarFilter f) {
    final selected = _filter == f;
    final color = const Color(0xFF667EEA);
    return ChoiceChip(
      label: Text(_labelForFilter(f)),
      selected: selected,
      onSelected: (_) => setState(() => _filter = f),
      selectedColor: color.withOpacity(0.12),
      labelStyle: TextStyle(
        color: selected ? color : const Color(0xFF475569),
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: const Color(0xFFF8FAFC),
      side: BorderSide(color: selected ? color : const Color(0xFFE2E8F0)),
    );
  }

  Widget _buildWeekdayHeader() {
    const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(names.length, (i) {
          return Expanded(
            child: Center(
              child: Text(
                names[i],
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final firstDay = _startOfMonth(_currentMonth);
    final totalDays = _daysInMonth(_currentMonth);
    final startWeekday = firstDay.weekday % 7; // 0=Sunday, 6=Saturday

    final cells = <Widget>[];
    for (int i = 0; i < startWeekday; i++) {
      cells.add(const SizedBox());
    }
    for (int day = 1; day <= totalDays; day++) {
      final date = DateTime(_currentMonth.year, _currentMonth.month, day);
      cells.add(_buildDayCell(date));
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: GridView.count(
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 7,
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        children: cells,
      ),
    );
  }

  // Month pager (vertical, virtually infinite)
  Widget _buildMonthPager(BuildContext context) {
    final media = MediaQuery.of(context);
    final double gridPaddingH = 16 + 8 + 8; // outer + inner
    final double cellWidth = (media.size.width - gridPaddingH - (6 * 6)) / 7;
    final double cellHeight = cellWidth * 0.9; // slightly squarer like iOS
    final double gridHeight = (cellHeight + 14) * 6 + 16; // 6 weeks max

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: SizedBox(
        height: gridHeight,
        child: PageView.builder(
          controller: _monthPageController,
          scrollDirection: Axis.vertical,
          itemCount: _kMonthPageCount,
          onPageChanged: (index) {
            final month = _monthFromIndex(index);
            setState(() {
              _currentMonth = DateTime(month.year, month.month);
            });
          },
          itemBuilder: (context, index) {
            final month = _monthFromIndex(index);
            return _buildMonthGridFor(month);
          },
        ),
      ),
    );
  }

  DateTime _monthFromIndex(int index) {
    final delta = index - _kMonthBaseIndex;
    return DateTime(_pagerAnchorMonth.year, _pagerAnchorMonth.month + delta);
  }

  Widget _buildMonthGridFor(DateTime month) {
    final firstDay = _startOfMonth(month);
    final totalDays = _daysInMonth(month);
    final startWeekday = firstDay.weekday % 7; // 0=Sun

    final cells = <Widget>[];
    for (int i = 0; i < startWeekday; i++) {
      cells.add(const SizedBox());
    }
    for (int day = 1; day <= totalDays; day++) {
      final date = DateTime(month.year, month.month, day);
      cells.add(_buildDayCell(date));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: GridView.count(
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 7,
        shrinkWrap: true,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        children: cells,
      ),
    );
  }

  Widget _buildWeekRow() {
    // Show the week containing _selectedDate
    final mondayBased = _selectedDate.subtract(
      Duration(days: (_selectedDate.weekday % 7)),
    );
    final start = mondayBased; // with Sunday=0 above, this yields Sunday start
    final days = List.generate(
      7,
      (i) => _truncateDate(start.add(Duration(days: i))),
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: days.map((d) => Expanded(child: _buildDayCell(d))).toList(),
      ),
    );
  }

  Widget _buildDayCell(DateTime date) {
    final isToday = _truncateDate(date) == _truncateDate(DateTime.now());
    final isSelected = _truncateDate(date) == _truncateDate(_selectedDate);
    final items = _itemsForDate(date);

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedDate = date; // stay in month and show agenda below
        });
        HapticFeedback.selectionClick();
      },
      onLongPress: () => _showDayBottomSheet(date, items),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF667EEA)
                : const Color(0xFFE2E8F0),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? const Color(0xFF4338CA)
                        : const Color(0xFF0F172A),
                  ),
                ),
                if (isToday) ...[
                  const SizedBox(width: 4),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            if (items.isNotEmpty)
              _buildEventBars(items),
          ],
        ),
      ),
    );
  }

  // Collapsible agenda tray
  Widget _buildAgendaCollapsible(List<_CalendarItem> items) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() => _agendaExpanded = !_agendaExpanded);
              HapticFeedback.lightImpact();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        DateFormat.yMMMMEEEEd().format(_selectedDate),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        _agendaExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: const Color(0xFF9CA3AF),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState:
                _agendaExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildAgendaList(items),
            ),
            secondChild: const SizedBox(height: 0),
          ),
        ],
      ),
    );
  }

  // Apple-like stacked horizontal bars for events under each day cell
  Widget _buildEventBars(List<_CalendarItem> items) {
    // Sort by time for a consistent look
    final sorted = [...items]
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final visible = sorted.take(3).toList();
    final overflow = items.length - visible.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final barWidth = width * 0.8; // slightly inset
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...visible.map(
              (i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Container(
                  width: barWidth,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _markerColorFor(i.type),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            if (overflow > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '+$overflow',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9CA3AF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildLegend() {
    Widget dot(Color c) => Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          dot(_markerColorFor(_CalendarItemType.created)),
          const SizedBox(width: 6),
          const Text('Created'),
          const SizedBox(width: 16),
          dot(_markerColorFor(_CalendarItemType.ticket)),
          const SizedBox(width: 6),
          const Text('Tickets'),
          const SizedBox(width: 16),
          dot(_markerColorFor(_CalendarItemType.saved)),
          const SizedBox(width: 6),
          const Text('Saved'),
        ],
      ),
    );
  }

  Widget _buildAgendaHeader() {
    final label = DateFormat.yMMMMEEEEd().format(_selectedDate);
    final itemsCount = _itemsForDate(_selectedDate).length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1F2937),
            ),
          ),
          const Spacer(),
          Text(
            itemsCount == 0
                ? 'No events'
                : itemsCount == 1
                ? '1 event'
                : '$itemsCount events',
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgendaList(List<_CalendarItem> items) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'No events for this day',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              _buildCreateEventShortcut(_selectedDate),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) => _buildAgendaItem(items[index]),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemCount: items.length,
    );
  }

  Widget _buildCreateEventShortcut(DateTime date) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.add),
      label: Text('Create an event on ${DateFormat.MMMd().format(date)}'),
      onPressed: () {
        RouterClass.nextScreenNormal(context, const ChoseDateTimeScreen());
      },
    );
  }

  Widget _buildAgendaItem(_CalendarItem item) {
    final Color color = _markerColorFor(item.type);
    final String timeLabel = () {
      final dt = item.dateTime;
      return DateFormat.jm().format(dt);
    }();

    final String title = item.title;
    final String subtitle = item.location ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openItem(item),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.event, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 14,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            timeLabel,
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Icon(
                              Icons.place,
                              size: 14,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          _chipForType(item.type),
                          ActionChip(
                            label: const Text('Add to Calendar'),
                            avatar: const Icon(Icons.add_alert, size: 18),
                            onPressed: () => _addToGoogleCalendar(item),
                          ),
                          ActionChip(
                            label: const Text('Remind me'),
                            avatar: const Icon(Icons.alarm, size: 18),
                            onPressed: () => _scheduleReminder(item),
                          ),
                          if (item.type == _CalendarItemType.ticket)
                            ActionChip(
                              label: const Text('My Tickets'),
                              avatar: const Icon(
                                Icons.confirmation_num,
                                size: 18,
                              ),
                              onPressed: () {
                                RouterClass.nextScreenNormal(
                                  context,
                                  const MyTicketsScreen(),
                                );
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chipForType(_CalendarItemType t) {
    return const SizedBox.shrink();
  }

  Future<void> _openItem(_CalendarItem item) async {
    EventModel? event;
    if (item.event != null) {
      event = item.event;
    } else if (item.ticket != null) {
      // Try cache first
      event = _eventCache[item.ticket!.eventId];
      event ??= await FirebaseFirestoreHelper().getSingleEvent(
        item.ticket!.eventId,
      );
      if (event != null) _eventCache[item.ticket!.eventId] = event!;
    }

    if (!mounted) return;
    if (event != null) {
      RouterClass.nextScreenNormal(
        context,
        SingleEventScreen(eventModel: event),
      );
    }
  }

  Future<void> _addToGoogleCalendar(_CalendarItem item) async {
    // Build a Google Calendar event creation URL
    final title = Uri.encodeComponent(item.title);
    final details = Uri.encodeComponent(item.description ?? '');
    final location = Uri.encodeComponent(item.location ?? '');

    final start = item.dateTime.toUtc();
    final end = start.add(const Duration(hours: 2));
    final fmt = DateFormat("yyyyMMdd'T'HHmmss'Z'");
    final dates = '${fmt.format(start)}/${fmt.format(end)}';

    final url =
        'https://calendar.google.com/calendar/r/eventedit?text=$title&dates=$dates&details=$details&location=$location';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _scheduleReminder(_CalendarItem item) async {
    final when = item.dateTime.subtract(const Duration(minutes: 30));
    if (when.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event starts too soon for a reminder')),
      );
      return;
    }

    // Use a simple immediate notification as a placeholder; scheduling API not implemented here.
    // If you later extend NotificationService with scheduling, call that here instead.
    await NotificationService.showNotification(
      title: 'Reminder set',
      body: 'We will remind you 30 minutes before ${item.title}',
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reminder scheduled 30 minutes before event'),
      ),
    );
  }

  void _showDayBottomSheet(DateTime date, List<_CalendarItem> items) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.event, color: Color(0xFF667EEA)),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat.yMMMMEEEEd().format(date),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: 'New Event',
                      onPressed: () {
                        // Smart default: next top-of-hour for today, else 9:00 AM
                        DateTime initial;
                        final now = DateTime.now();
                        if (DateUtils.isSameDay(now, date)) {
                          final nextHour = now.add(const Duration(hours: 1));
                          initial = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            nextHour.hour,
                            0,
                          );
                        } else {
                          initial = DateTime(date.year, date.month, date.day, 9, 0);
                        }
                        Navigator.pop(context);
                        HapticFeedback.heavyImpact();
                        RouterClass.nextScreenNormal(
                          context,
                          ChoseDateTimeScreen(
                            initialDateTime: initial,
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...items.map(
                  (it) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _buildAgendaItem(it),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDayView() {
    return DayView(
      controller: _eventController,
      initialDay: _selectedDate,
      heightPerMinute: 1.0,
      liveTimeIndicatorSettings: LiveTimeIndicatorSettings(color: Colors.red),
      timeLineWidth: 56.0,
      onPageChange: (date, page) => setState(() => _selectedDate = date),
    );
  }

  // Sticky fading month label for pager scroll
  Widget _buildFadingMonthLabel() {
    final textStyle = const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w800,
      color: Color(0xFF1E293B),
    );
    return AnimatedBuilder(
      animation: _monthPageController,
      builder: (context, _) {
        final double page = _monthPageController.hasClients
            ? (_monthPageController.page ?? _kMonthBaseIndex.toDouble())
            : _kMonthBaseIndex.toDouble();
        final int base = page.floor();
        final double frac = page - base;
        final DateTime m1 = _monthFromIndex(base);
        final DateTime m2 = _monthFromIndex(base + 1);
        return SizedBox(
          height: 22,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: 1 - frac,
                child: Text(DateFormat.yMMMM().format(m1), style: textStyle),
              ),
              Opacity(
                opacity: frac,
                child: Text(DateFormat.yMMMM().format(m2), style: textStyle),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _CalendarItemType { created, ticket, saved }

class _CalendarItem {
  final _CalendarItemType type;
  final EventModel? event;
  final TicketModel? ticket;

  _CalendarItem.created(this.event)
    : type = _CalendarItemType.created,
      ticket = null;

  _CalendarItem.saved(this.event)
    : type = _CalendarItemType.saved,
      ticket = null;

  _CalendarItem.ticket(this.ticket)
    : type = _CalendarItemType.ticket,
      event = null;

  DateTime get dateTime => event?.selectedDateTime ?? ticket!.eventDateTime;
  String get title => event?.title ?? ticket!.eventTitle;
  String? get location => event?.location ?? ticket!.eventLocation;
  String? get description => event?.description;
}

class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PinnedHeaderDelegate({
    required this.minExtent,
    required this.maxExtent,
    required this.builder,
  });

  @override
  final double minExtent;
  @override
  final double maxExtent;
  final Widget Function(BuildContext context, bool shrinkOffset, bool overlaps) builder;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final double range = (maxExtent - minExtent).clamp(1.0, double.infinity);
    final double t = (shrinkOffset / range).clamp(0.0, 1.0);
    final double elevation = 0.0 + 3.0 * t; // subtle shadow as it overlaps
    return Material(
      elevation: overlapsContent ? elevation : 0.0,
      color: Colors.white,
      child: builder(context, shrinkOffset > 0, overlapsContent),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) {
    return minExtent != oldDelegate.minExtent ||
        maxExtent != oldDelegate.maxExtent ||
        builder != oldDelegate.builder;
  }
}