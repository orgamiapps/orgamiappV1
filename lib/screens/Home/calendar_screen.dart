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

enum CalendarFilter { all, created, tickets, saved }

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDate = DateTime.now();
  CalendarFilter _filter = CalendarFilter.all;

  bool _loading = false;

  // Data sources
  List<EventModel> _createdEvents = [];
  List<EventModel> _savedEvents = [];
  List<TicketModel> _ticketModels = [];
  final Map<String, EventModel> _eventCache = {};

  @override
  void initState() {
    super.initState();
    _loadData();
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
      final saved = await FirebaseFirestoreHelper().getFavoritedEvents(userId: uid);

      // Load tickets
      final tickets = await FirebaseFirestoreHelper().getUserTickets(customerUid: uid);

      setState(() {
        _createdEvents = created;
        _savedEvents = saved;
        _ticketModels = tickets;
      });
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

      final allDocs = <DocumentSnapshot>{...createdSnap.docs, ...cohostSnap.docs};
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

    for (final e in _createdEvents) {
      addItem(e.selectedDateTime, _CalendarItem.created(e));
    }
    for (final e in _savedEvents) {
      addItem(e.selectedDateTime, _CalendarItem.saved(e));
    }
    for (final t in _ticketModels) {
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
    switch (t) {
      case _CalendarItemType.created:
        return const Color(0xFF10B981); // emerald
      case _CalendarItemType.ticket:
        return const Color(0xFF3B82F6); // blue
      case _CalendarItemType.saved:
        return const Color(0xFF8B5CF6); // violet
    }
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

    return Scaffold(
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
            tooltip: 'Today',
            icon: const Icon(Icons.today),
            onPressed: () {
              setState(() {
                _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
                _selectedDate = DateTime.now();
              });
            },
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadData,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildMonthHeader(monthLabel),
                const SizedBox(height: 8),
                _buildFilters(),
                const SizedBox(height: 8),
                _buildWeekdayHeader(),
                _buildCalendarGrid(),
                const SizedBox(height: 12),
                _buildLegend(),
                const SizedBox(height: 16),
                _buildAgendaHeader(),
                _buildAgendaList(selectedItems),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthHeader(String monthLabel) {
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
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() {
                _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
              });
            },
          ),
          Expanded(
            child: Center(
              child: Text(
                monthLabel,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              setState(() {
                _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
              });
            },
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
                _selectedDate = DateTime.now();
              });
            },
            icon: const Icon(Icons.calendar_today, size: 16, color: Color(0xFF667EEA)),
            label: const Text(
              'Today',
              style: TextStyle(color: Color(0xFF667EEA), fontWeight: FontWeight.bold),
            ),
            style: TextButton.styleFrom(
              foregroundColor: primary,
            ),
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

  Widget _buildDayCell(DateTime date) {
    final isToday = _truncateDate(date) == _truncateDate(DateTime.now());
    final isSelected = _truncateDate(date) == _truncateDate(_selectedDate);
    final items = _itemsForDate(date);

    return GestureDetector(
      onTap: () => setState(() => _selectedDate = date),
      onLongPress: items.isEmpty ? null : () => _showDayBottomSheet(date, items),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: _buildMarkers(items),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMarkers(List<_CalendarItem> items) {
    // Up to 3 markers per day (created, tickets, saved) unique by type
    final types = <_CalendarItemType>{};
    final unique = <_CalendarItem>[];
    for (final i in items) {
      if (types.add(i.type)) unique.add(i);
      if (unique.length == 3) break;
    }
    return unique
        .map((i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _markerColorFor(i.type),
                  shape: BoxShape.circle,
                ),
              ),
            ))
        .toList();
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
            style: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
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
          child: const Center(
            child: Text(
              'No events for this day',
              style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
            ),
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
                          Icon(Icons.schedule, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            timeLabel,
                            style: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Icon(Icons.place, size: 14, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
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
                          if (item.type == _CalendarItemType.ticket)
                            ActionChip(
                              label: const Text('My Tickets'),
                              avatar: const Icon(Icons.confirmation_num, size: 18),
                              onPressed: () {
                                RouterClass.nextScreenNormal(context, const MyTicketsScreen());
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
    final text = t == _CalendarItemType.created
        ? 'Created by You'
        : t == _CalendarItemType.ticket
            ? 'Have Ticket'
            : 'Saved';
    final color = _markerColorFor(t);
    return Chip(
      label: Text(text),
      labelStyle: TextStyle(color: color.shade900, fontWeight: FontWeight.w600),
      backgroundColor: color.withOpacity(0.1),
      side: BorderSide(color: color.withOpacity(0.2)),
    );
  }

  Future<void> _openItem(_CalendarItem item) async {
    EventModel? event;
    if (item.event != null) {
      event = item.event;
    } else if (item.ticket != null) {
      // Try cache first
      event = _eventCache[item.ticket!.eventId];
      event ??= await FirebaseFirestoreHelper().getSingleEvent(item.ticket!.eventId);
      if (event != null) _eventCache[item.ticket!.eventId] = event!;
    }

    if (!mounted) return;
    if (event != null) {
      RouterClass.nextScreenNormal(context, SingleEventScreen(eventModel: event));
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

    final url = 'https://calendar.google.com/calendar/r/eventedit?text=$title&dates=$dates&details=$details&location=$location';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...items.map((it) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: _buildAgendaItem(it),
                    )),
              ],
            ),
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