import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/ticket_model.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/screens/MyProfile/Widgets/realistic_ticket_card.dart';
import 'package:attendus/screens/MyProfile/Widgets/ticket_stats_dashboard.dart';
import 'package:attendus/widgets/attendus_design_system.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

class MyTicketsScreen extends StatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  State<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends State<MyTicketsScreen>
    with TickerProviderStateMixin {
  List<TicketModel> userTickets = [];
  final Map<String, EventModel> _eventCache = {};
  bool isLoading = true;
  int selectedTab = 0; // 0 = All, 1 = Active, 2 = Used

  // Search and Sort
  String _searchQuery = '';
  String _sortBy = 'date_desc'; // date_desc, date_asc, name, location
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isSearching = false;

  // Animation controllers
  late AnimationController _tabAnimationController;
  late AnimationController _searchAnimationController;

  // Stats dashboard
  bool _showStats = true;

  @override
  void initState() {
    super.initState();
    _tabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _searchAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _loadUserTickets();
    _loadSortPreference();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    _tabAnimationController.dispose();
    _searchAnimationController.dispose();
    super.dispose();
  }

  Future<void> _loadSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSort = prefs.getString('tickets_sort_preference') ?? 'date_desc';
    if (mounted) {
      setState(() {
        _sortBy = savedSort;
      });
    }
  }

  Future<void> _saveSortPreference(String sortBy) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tickets_sort_preference', sortBy);
  }

  Future<void> _loadUserTickets() async {
    setState(() {
      isLoading = true;
    });

    try {
      if (CustomerController.logeInCustomer == null) {
        ShowToast().showNormalToast(msg: 'Please log in to view your tickets');
        return;
      }

      final tickets = await FirebaseFirestoreHelper().getUserTickets(
        customerUid: CustomerController.logeInCustomer!.uid,
      );

      // Fetch event data for each unique event
      final uniqueEventIds = tickets.map((t) => t.eventId).toSet();
      for (final eventId in uniqueEventIds) {
        try {
          final event = await FirebaseFirestoreHelper().getSingleEvent(eventId);
          if (event != null) {
            _eventCache[eventId] = event;
          }
        } catch (e) {
          // Continue loading even if one event fails
        }
      }

      if (mounted) {
        setState(() {
          userTickets = tickets;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ShowToast().showNormalToast(msg: 'Failed to load tickets: $e');
      }
    }
  }

  List<TicketModel> get filteredTickets {
    switch (selectedTab) {
      case 1: // Active
        return userTickets.where((ticket) => !ticket.isUsed).toList();
      case 2: // Used
        return userTickets.where((ticket) => ticket.isUsed).toList();
      default: // All
        return userTickets;
    }
  }

  List<TicketModel> get filteredAndSortedTickets {
    var tickets = filteredTickets;

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      tickets = tickets.where((ticket) {
        final query = _searchQuery.toLowerCase();
        return ticket.eventTitle.toLowerCase().contains(query) ||
            ticket.eventLocation.toLowerCase().contains(query) ||
            ticket.ticketCode.toLowerCase().contains(query);
      }).toList();
    }

    // Apply sorting
    switch (_sortBy) {
      case 'date_asc':
        tickets.sort((a, b) => a.eventDateTime.compareTo(b.eventDateTime));
        break;
      case 'date_desc':
        tickets.sort((a, b) => b.eventDateTime.compareTo(a.eventDateTime));
        break;
      case 'name':
        tickets.sort((a, b) => a.eventTitle.compareTo(b.eventTitle));
        break;
      case 'location':
        tickets.sort((a, b) => a.eventLocation.compareTo(b.eventLocation));
        break;
    }

    return tickets;
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchQuery = query;
        });
      }
    });
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
    if (_isSearching) {
      _searchAnimationController.forward();
    } else {
      _searchAnimationController.reverse();
    }
  }

  void _showSortOptions() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Icon(Icons.sort, color: Color(0xFF667EEA)),
                  SizedBox(width: 12),
                  Text(
                    'Sort Tickets',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildSortOption('Newest First', 'date_desc', Icons.arrow_downward),
            _buildSortOption('Oldest First', 'date_asc', Icons.arrow_upward),
            _buildSortOption('Event Name', 'name', Icons.sort_by_alpha),
            _buildSortOption('Location', 'location', Icons.location_on),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOption(String title, String value, IconData icon) {
    final isSelected = _sortBy == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _sortBy = value;
          });
          _saveSortPreference(value);
          Navigator.pop(context);
          HapticFeedback.selectionClick();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF667EEA).withValues(alpha: 0.1)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? const Color(0xFF667EEA) : Colors.grey[600],
                size: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: isSelected ? const Color(0xFF667EEA) : Colors.black,
                  ),
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFF667EEA),
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            AttendUsTopBar(
              title: 'My Tickets',
              subtitle: 'Active passes, used tickets, and QR check-in codes.',
              actions: [
                IconButton(
                  tooltip: _isSearching ? 'Close search' : 'Search tickets',
                  icon: Icon(_isSearching ? Icons.close : Icons.search),
                  onPressed: _toggleSearch,
                ),
                IconButton(
                  tooltip: 'Sort tickets',
                  icon: const Icon(Icons.sort),
                  onPressed: _showSortOptions,
                ),
              ],
            ),
            Expanded(
              child: isLoading
                  ? const AttendUsLoadingState(label: 'Loading tickets')
                  : RefreshIndicator(
                      onRefresh: _loadUserTickets,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: AttendUsTokens.pageMaxWidth,
                          ),
                          child: _buildScrollableContent(),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildNormalHeader() {
    return AttendUsTopBar(
      title: 'My Tickets',
      subtitle: 'Active passes, used tickets, and QR check-in codes.',
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: _toggleSearch,
          tooltip: 'Search',
        ),
        IconButton(
          icon: const Icon(Icons.sort),
          onPressed: _showSortOptions,
          tooltip: 'Sort',
        ),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildSearchHeader() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Back button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggleSearch,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.6 : 0.8,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.arrow_back_rounded,
                  size: 22,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Search field
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(color: Colors.black87, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Search tickets...',
                hintStyle: TextStyle(color: Colors.grey[500], fontSize: 15),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          // Clear button
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.black54),
              onPressed: () {
                _searchController.clear();
                _onSearchChanged('');
              },
              tooltip: 'Clear',
            ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return AttendUsCard(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              title: 'All',
              count: userTickets.length,
              isSelected: selectedTab == 0,
              onTap: () => setState(() => selectedTab = 0),
            ),
          ),
          Expanded(
            child: _buildTabButton(
              title: 'Active',
              count: userTickets.where((t) => !t.isUsed).length,
              isSelected: selectedTab == 1,
              onTap: () => setState(() => selectedTab = 1),
            ),
          ),
          Expanded(
            child: _buildTabButton(
              title: 'Used',
              count: userTickets.where((t) => t.isUsed).length,
              isSelected: selectedTab == 2,
              onTap: () => setState(() => selectedTab = 2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String title,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AttendUsTokens.radiusMd),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollableContent() {
    final tickets = filteredAndSortedTickets;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildTicketControls()),
        // Stats dashboard
        if (_showStats && userTickets.isNotEmpty)
          SliverToBoxAdapter(
            child: TicketStatsDashboard(
              allTickets: userTickets,
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _showStats = !_showStats);
              },
            ),
          ),

        // Tab bar
        SliverToBoxAdapter(child: _buildTabBar()),

        // Tickets list or empty state
        if (tickets.isEmpty)
          SliverFillRemaining(child: _buildEmptyState())
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.crossAxisExtent >= 980
                    ? 2
                    : 1;
                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: crossAxisCount == 1 ? 3.1 : 2.5,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final ticket = tickets[index];
                    return AttendUsTicketPassCard(
                      eventTitle: ticket.eventTitle,
                      dateLabel: _formatTicketDate(ticket.eventDateTime),
                      ticketLabel: ticket.isUsed ? 'Used' : 'Active',
                      onTap: () => _showTicketModal(ticket),
                    );
                  }, childCount: tickets.length),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildTicketControls() {
    return Padding(
      padding: AttendUsTokens.pagePadding,
      child: AttendUsPageSection(
        title: 'Ticket Wallet',
        subtitle: '${userTickets.length} total tickets',
        icon: Icons.confirmation_number_outlined,
        framed: true,
        child: Column(
          children: [
            if (_isSearching)
              AttendUsSearchField(
                controller: _searchController,
                hintText: 'Search tickets',
                onChanged: _onSearchChanged,
                onClear: () => _onSearchChanged(''),
              ),
            if (_isSearching) const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AttendUsStatusBadge(
                  label:
                      '${userTickets.where((ticket) => !ticket.isUsed).length} active',
                  tone: AttendUsStatusTone.success,
                  icon: Icons.verified_outlined,
                ),
                AttendUsStatusBadge(
                  label:
                      '${userTickets.where((ticket) => ticket.isUsed).length} used',
                  tone: AttendUsStatusTone.neutral,
                  icon: Icons.check_circle_outline,
                ),
                AttendUsStatusBadge(
                  label: _sortLabel,
                  tone: AttendUsStatusTone.info,
                  icon: Icons.sort,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String get _sortLabel {
    return switch (_sortBy) {
      'date_asc' => 'Oldest first',
      'name' => 'Event name',
      'location' => 'Location',
      _ => 'Newest first',
    };
  }

  String _formatTicketDate(DateTime dateTime) {
    final local = dateTime.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$month/$day/${local.year}';
  }

  void _showTicketModal(TicketModel ticket) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _TicketModalView(ticket: ticket, event: _eventCache[ticket.eventId]),
    );
  }

  Widget _buildEmptyState() {
    String message;
    String subtitle;
    IconData icon;
    bool showSearchMessage = _searchQuery.isNotEmpty;

    if (showSearchMessage) {
      message = 'No tickets found';
      subtitle = 'Try adjusting your search terms';
      icon = Icons.search_off;
    } else {
      switch (selectedTab) {
        case 1:
          message = 'No active tickets';
          subtitle = 'Active tickets will appear here';
          icon = Icons.confirmation_number_outlined;
          break;
        case 2:
          message = 'No used tickets yet';
          subtitle = 'Used tickets will appear here';
          icon = Icons.check_circle_outline;
          break;
        default:
          message = 'No tickets yet';
          subtitle = 'Start exploring events and get your first ticket!';
          icon = Icons.confirmation_number_outlined;
      }
    }

    return AttendUsEmptyState(
      icon: icon,
      title: message,
      message: subtitle,
      action: !showSearchMessage && selectedTab == 0
          ? AttendUsButton.primary(
              label: 'Explore events',
              icon: Icons.explore_outlined,
              onPressed: () => Navigator.pop(context),
            )
          : null,
    );
  }

  // Old ticket card methods removed - now using RealisticTicketCard widget
  // All ticket display, sharing, and detail functionality is now in RealisticTicketCard
}

/// Full-screen modal view for a single ticket with flip capability
class _TicketModalView extends StatefulWidget {
  final TicketModel ticket;
  final EventModel? event;

  const _TicketModalView({required this.ticket, this.event});

  @override
  State<_TicketModalView> createState() => _TicketModalViewState();
}

class _TicketModalViewState extends State<_TicketModalView> {
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.95,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        final theme = Theme.of(context);
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(AttendUsTokens.radiusLg),
              topRight: Radius.circular(AttendUsTokens.radiusLg),
            ),
          ),
          child: Column(
            children: [
              // Close button
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 16, 16, 0),
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),

              // Ticket card - centered and scrollable
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: RealisticTicketCard(
                        ticket: widget.ticket,
                        event: widget.event,
                        index: 0,
                        enableFlip: true,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
