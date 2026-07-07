import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/ticket_model.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/Utils/app_app_bar_view.dart';
import 'package:attendus/screens/MyProfile/Widgets/realistic_ticket_card.dart';
import 'package:attendus/screens/MyProfile/Widgets/compact_ticket_card.dart';
import 'package:attendus/screens/MyProfile/Widgets/ticket_stats_dashboard.dart';
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
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          // Modern header with white background
          _isSearching ? _buildSearchHeader() : _buildNormalHeader(),
          // Content - Fully scrollable
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF667EEA),
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadUserTickets,
                    color: const Color(0xFF667EEA),
                    child: _buildScrollableContent(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalHeader() {
    return AppAppBarView.modernHeader(
      context: context,
      title: 'My Tickets',
      showBackButton: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black87),
            onPressed: _toggleSearch,
            tooltip: 'Search',
          ),
          IconButton(
            icon: RotationTransition(
              turns: Tween(begin: 0.0, end: 0.5).animate(
                CurvedAnimation(
                  parent: _tabAnimationController,
                  curve: Curves.easeInOut,
                ),
              ),
              child: const Icon(Icons.sort, color: Colors.black87),
            ),
            onPressed: _showSortOptions,
            tooltip: 'Sort',
          ),
        ],
      ),
    );
  }

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
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
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
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF667EEA) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF667EEA).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF6B7280),
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : const Color(0xFF1A1A1A),
                fontFamily: 'Roboto',
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
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final ticket = tickets[index];
                return CompactTicketCard(
                  ticket: ticket,
                  event: _eventCache[ticket.eventId],
                  index: index,
                  onTap: () => _showTicketModal(ticket),
                );
              }, childCount: tickets.length),
            ),
          ),
      ],
    );
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

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Center(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 72, color: const Color(0xFF667EEA)),
                ),
                const SizedBox(height: 24),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                    fontFamily: 'Roboto',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF6B7280),
                    fontFamily: 'Roboto',
                  ),
                  textAlign: TextAlign.center,
                ),
                if (!showSearchMessage && selectedTab == 0) ...[
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.explore_outlined),
                    label: const Text('Explore Events'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF667EEA),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                      shadowColor: const Color(
                        0xFF667EEA,
                      ).withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
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
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF818CF8), // Purplish color from screenshot
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
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
                    icon: CircleAvatar(
                      backgroundColor: Colors.black.withOpacity(0.2),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
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
