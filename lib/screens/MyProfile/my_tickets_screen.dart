import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/ticket_model.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/Services/ticket_payment_service.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/Utils/calendar_helper.dart';
import 'package:attendus/Utils/router.dart';
import 'package:attendus/Utils/app_app_bar_view.dart';
import 'package:attendus/screens/Events/single_event_screen.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
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
  final GlobalKey ticketShareKey = GlobalKey();
  bool _isUpgrading = false;

  // Search and Sort
  String _searchQuery = '';
  String _sortBy = 'date_desc'; // date_desc, date_asc, name, location
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isSearching = false;

  // Animation controllers
  late AnimationController _tabAnimationController;
  late AnimationController _searchAnimationController;

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
          // Content
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
                    child: Column(
                      children: [
                        _buildTabBar(),
                        Expanded(child: _buildTicketList()),
                      ],
                    ),
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

  Widget _buildTicketList() {
    final tickets = filteredAndSortedTickets;

    if (tickets.isEmpty) {
      return _buildEmptyState();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: ListView.builder(
        key: ValueKey('$selectedTab-${tickets.length}'),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        itemCount: tickets.length,
        itemBuilder: (context, index) {
          final ticket = tickets[index];
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 300 + (index * 50)),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: Opacity(opacity: value, child: child),
              );
            },
            child: _buildTicketCard(ticket),
          );
        },
      ),
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

  Widget _buildTicketCard(TicketModel ticket) {
    final bool isUsed = ticket.isUsed;
    final Color statusColor = isUsed
        ? const Color(0xFF9CA3AF)
        : const Color(0xFF10B981);
    final String statusText = isUsed ? 'Used' : 'Active';

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            _showTicketDetail(ticket);
          },
          borderRadius: BorderRadius.circular(24),
          child: AnimatedScale(
            scale: 1.0,
            duration: const Duration(milliseconds: 150),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey[200]!, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Event Image with gradient overlay
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                        ),
                        child: CachedNetworkImage(
                          imageUrl: ticket.eventImageUrl,
                          width: double.infinity,
                          height: 160,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            width: double.infinity,
                            height: 160,
                            color: Colors.grey[200],
                          ),
                          errorWidget: (context, url, error) => Container(
                            width: double.infinity,
                            height: 160,
                            color: Colors.grey[200],
                            child: const Icon(Icons.error, size: 40),
                          ),
                        ),
                      ),
                      // Gradient overlay
                      Container(
                        height: 160,
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(24),
                            topRight: Radius.circular(24),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.6),
                            ],
                          ),
                        ),
                      ),
                      // Status badges on image
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Row(
                          children: [
                            if (ticket.isSkipTheLine) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFFFD700),
                                      Color(0xFFFFA500),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.2,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.flash_on,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'VIP',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                statusText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Ticket details
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ticket.eventTitle,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 16),
                        _buildInfoRow(
                          Icons.calendar_today_rounded,
                          DateFormat(
                            'EEE, MMM dd • h:mm a',
                          ).format(ticket.eventDateTime),
                        ),
                        const SizedBox(height: 10),
                        _buildInfoRow(
                          Icons.location_on_rounded,
                          ticket.eventLocation,
                        ),
                        const SizedBox(height: 10),
                        _buildInfoRow(
                          Icons.qr_code_rounded,
                          'Code: ${ticket.ticketCode}',
                          isBold: true,
                        ),
                        const SizedBox(height: 20),
                        // Action buttons row
                        Row(
                          children: [
                            Expanded(
                              child: _buildActionButton(
                                icon: Icons.event_available_rounded,
                                label: 'Add to Calendar',
                                onPressed: () => _addToCalendar(ticket),
                                isPrimary: false,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildActionButton(
                                icon: Icons.arrow_forward_rounded,
                                label: 'View Event',
                                onPressed: () =>
                                    _navigateToEvent(ticket.eventId),
                                isPrimary: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text, {bool isBold = false}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF667EEA).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: const Color(0xFF667EEA)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: const Color(0xFF4B5563),
              fontSize: 14,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required bool isPrimary,
  }) {
    return Material(
      color: isPrimary
          ? const Color(0xFF667EEA)
          : const Color(0xFF667EEA).withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isPrimary ? Colors.white : const Color(0xFF667EEA),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isPrimary ? Colors.white : const Color(0xFF667EEA),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addToCalendar(TicketModel ticket) {
    final event = _eventCache[ticket.eventId];
    final endTime =
        event?.eventEndTime ??
        ticket.eventDateTime.add(const Duration(hours: 2));

    CalendarHelper.showCalendarOptions(
      context,
      title: ticket.eventTitle,
      startTime: ticket.eventDateTime,
      endTime: endTime,
      description: event?.description ?? 'Event ticket from AttendUs',
      location: ticket.eventLocation,
    );
  }

  Future<void> _navigateToEvent(String eventId) async {
    HapticFeedback.lightImpact();

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667EEA)),
        ),
      ),
    );

    try {
      // Try to get from cache first
      EventModel? event = _eventCache[eventId];

      // If not in cache, fetch from Firebase
      if (event == null) {
        event = await FirebaseFirestoreHelper().getSingleEvent(eventId);
      }

      if (!mounted) return;

      // Close loading dialog
      Navigator.pop(context);

      if (event != null) {
        // Navigate to event screen
        RouterClass.nextScreenNormal(
          context,
          SingleEventScreen(eventModel: event),
        );
      } else {
        ShowToast().showNormalToast(
          msg: 'Event not found. It may have been deleted.',
        );
      }
    } catch (e) {
      if (!mounted) return;

      // Close loading dialog
      Navigator.pop(context);

      ShowToast().showNormalToast(msg: 'Failed to load event: ${e.toString()}');
    }
  }

  void _showTicketDetail(TicketModel ticket) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _buildTicketDetailDialog(ticket),
    );
  }

  Future<void> _shareTicket(TicketModel ticket) async {
    try {
      // Ensure the event image is cached before rendering
      await precacheImage(
        CachedNetworkImageProvider(ticket.eventImageUrl),
        context,
      );

      if (!mounted) return;
      final overlay = Overlay.maybeOf(context);
      if (overlay == null) throw Exception('Overlay not available');

      late OverlayEntry entry;
      entry = OverlayEntry(
        builder: (context) => Material(
          type: MaterialType.transparency,
          child: Center(
            child: RepaintBoundary(
              key: ticketShareKey,
              child: _buildShareableTicketCard(ticket),
            ),
          ),
        ),
      );

      overlay.insert(entry);
      // Wait for the frame to paint
      await Future.delayed(const Duration(milliseconds: 200));

      final boundary =
          ticketShareKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Share boundary not found');

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to encode image');
      final bytes = byteData.buffer.asUint8List();

      // Remove the overlay entry as soon as we have the bytes
      entry.remove();

      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/orgami_ticket_${ticket.ticketCode}.png',
      );
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text:
            'My AttendUs Ticket • ${ticket.eventTitle} • Code: ${ticket.ticketCode}',
      );
    } catch (e) {
      debugPrint('Error sharing ticket: $e');
      ShowToast().showNormalToast(msg: 'Failed to share ticket');
    }
  }

  Widget _buildShareableTicketCard(TicketModel ticket) {
    // Fixed width for consistent image output
    const double cardWidth = 360; // logical pixels before pixelRatio scaling
    return Container(
      width: cardWidth,
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header image
            CachedNetworkImage(
              imageUrl: ticket.eventImageUrl,
              height: 160,
              fit: BoxFit.cover,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          ticket.eventTitle,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (ticket.isUsed
                                      ? Colors.red
                                      : const Color(0xFF667EEA))
                                  .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          ticket.isUsed ? 'USED' : 'ACTIVE',
                          style: TextStyle(
                            color: ticket.isUsed
                                ? Colors.red
                                : const Color(0xFF667EEA),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: Color(0xFF6B7280),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat(
                          'EEE, MMM dd • h:mm a',
                        ).format(ticket.eventDateTime),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF374151),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 16,
                        color: Color(0xFF6B7280),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          ticket.eventLocation,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF374151),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Ticket Code',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            Text(
                              ticket.ticketCode,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: Color(0xFF111827),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.white,
                        ),
                        padding: const EdgeInsets.all(6),
                        child: QrImageView(
                          data: ticket.qrCodeData,
                          version: QrVersions.auto,
                          size: 88,
                          gapless: false,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 20),
                  const Center(
                    child: Text(
                      'Powered by AttendUs',
                      style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
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

  Widget _buildTicketDetailDialog(TicketModel ticket) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Elegant header with image and gradient overlay
            Stack(
              children: [
                // Event image with gradient overlay
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(28),
                    topRight: Radius.circular(28),
                  ),
                  child: Stack(
                    children: [
                      CachedNetworkImage(
                        imageUrl: ticket.eventImageUrl,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                      // Dark gradient overlay for better text readability
                      Container(
                        height: 160,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.3),
                              Colors.black.withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                      ),
                      // Title and status overlay on image
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ticket.eventTitle,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: Colors.black45,
                                    offset: Offset(0, 2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if (ticket.isSkipTheLine) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFFFD700),
                                          Color(0xFFFFA500),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.flash_on,
                                          color: Colors.white,
                                          size: 14,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'VIP',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: ticket.isUsed
                                        ? const Color(0xFFEF4444)
                                        : const Color(0xFF10B981),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    ticket.isUsed ? 'USED' : 'ACTIVE',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      letterSpacing: 0.5,
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
                ),
                // Action buttons with better visibility
                Positioned(
                  right: 12,
                  top: 12,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.ios_share,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            _shareTicket(ticket);
                          },
                          tooltip: 'Share',
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Close',
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Ticket details section
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Event details with modern icons
                    _buildModernDetailRow(
                      Icons.calendar_month_rounded,
                      'Date & Time',
                      DateFormat(
                        'EEE, MMM dd, yyyy • h:mm a',
                      ).format(ticket.eventDateTime),
                    ),
                    const SizedBox(height: 14),
                    _buildModernDetailRow(
                      Icons.location_on_rounded,
                      'Location',
                      ticket.eventLocation,
                    ),
                    const SizedBox(height: 14),
                    _buildModernDetailRow(
                      Icons.person_rounded,
                      'Attendee',
                      ticket.customerName,
                    ),

                    // Divider
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Divider(height: 1, thickness: 1),
                    ),

                    // QR Code section
                    if (!ticket.isUsed) ...[
                      Center(
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF9FAFB),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFE5E7EB),
                                  width: 1,
                                ),
                              ),
                              child: QrImageView(
                                data: ticket.qrCodeData,
                                version: QrVersions.auto,
                                size: 180,
                                backgroundColor: const Color(0xFFF9FAFB),
                                eyeStyle: const QrEyeStyle(
                                  eyeShape: QrEyeShape.square,
                                  color: Color(0xFF1F2937),
                                ),
                                dataModuleStyle: const QrDataModuleStyle(
                                  dataModuleShape: QrDataModuleShape.square,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Ticket Code: ${ticket.ticketCode}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1F2937),
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Show this QR code to the event organizer',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF6B7280),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Center(
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(
                                    0xFFEF4444,
                                  ).withValues(alpha: 0.3),
                                  width: 2,
                                ),
                              ),
                              child: const Column(
                                children: [
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 64,
                                    color: Color(0xFFEF4444),
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'Ticket Already Used',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Color(0xFFEF4444),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (ticket.usedDateTime != null)
                              Text(
                                'Used on ${DateFormat('MMM dd, yyyy • h:mm a').format(ticket.usedDateTime!)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],

                    // Action buttons
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDialogActionButton(
                            icon: Icons.event_available_rounded,
                            label: 'Add to Calendar',
                            onPressed: () {
                              Navigator.pop(context);
                              _addToCalendar(ticket);
                            },
                            color: const Color(0xFF10B981),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildDialogActionButton(
                            icon: Icons.arrow_forward_rounded,
                            label: 'View Event',
                            onPressed: () {
                              Navigator.pop(context);
                              _navigateToEvent(ticket.eventId);
                            },
                            color: const Color(0xFF667EEA),
                          ),
                        ),
                      ],
                    ),

                    // Upgrade button for eligible tickets
                    if (!ticket.isUsed &&
                        !ticket.isSkipTheLine &&
                        ticket.price != null &&
                        ticket.price! > 0 &&
                        _eventCache[ticket.eventId]?.ticketUpgradeEnabled ==
                            true &&
                        _eventCache[ticket.eventId]?.ticketUpgradePrice !=
                            null) ...[
                      const SizedBox(height: 16),
                      _buildUpgradeButton(ticket),
                    ],

                    const SizedBox(height: 20),

                    // Footer
                    Center(
                      child: Text(
                        'Issued: ${DateFormat('MMMM dd, yyyy').format(ticket.issuedDateTime)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF667EEA).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF667EEA)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF1F2937),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDialogActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpgradeButton(TicketModel ticket) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667EEA).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isUpgrading ? null : () => _showUpgradeDialog(ticket),
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: _isUpgrading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.rocket_launch,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Upgrade to Skip-the-Line',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Priority entry • \$${(_eventCache[ticket.eventId]?.ticketUpgradePrice ?? 0).toStringAsFixed(2)}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  void _showUpgradeDialog(TicketModel ticket) {
    final upgradePrice = _eventCache[ticket.eventId]?.ticketUpgradePrice ?? 0;

    showDialog(
      context: context,
      barrierDismissible: !_isUpgrading,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            children: [
              Icon(Icons.flash_on, color: Colors.white, size: 48),
              SizedBox(height: 8),
              Text(
                'Upgrade to VIP Skip-the-Line',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF667EEA), size: 32),
            const SizedBox(height: 16),
            const Text(
              'Skip the line benefits:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildBenefitRow('Priority entry - no waiting in line'),
            _buildBenefitRow('VIP treatment at the venue'),
            _buildBenefitRow('Exclusive skip-the-line QR code'),
            _buildBenefitRow('Same ticket, upgraded experience'),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text(
                    'Upgrade Price',
                    style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\$${upgradePrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Original ticket: \$${ticket.price!.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _isUpgrading ? null : () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isUpgrading ? null : () => _upgradeTicket(ticket),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  child: const Text(
                    'Upgrade Now',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.check, color: Color(0xFF667EEA), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, color: Color(0xFF1F2937)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _upgradeTicket(TicketModel ticket) async {
    setState(() {
      _isUpgrading = true;
    });

    try {
      // Create upgrade payment intent
      final paymentData =
          await TicketPaymentService.createTicketUpgradePaymentIntent(
            ticketId: ticket.id,
            originalPrice: ticket.price!,
            upgradePrice: _eventCache[ticket.eventId]?.ticketUpgradePrice ?? 0,
            customerUid: CustomerController.logeInCustomer!.uid,
            customerName: CustomerController.logeInCustomer!.name,
            customerEmail: CustomerController.logeInCustomer!.email,
            eventTitle: ticket.eventTitle,
          );

      // Process payment
      final paymentSuccess = await TicketPaymentService.processTicketUpgrade(
        clientSecret: paymentData['clientSecret'],
        eventTitle: ticket.eventTitle,
        upgradeAmount: paymentData['upgradeAmount'],
      );

      if (paymentSuccess) {
        // Confirm upgrade
        await TicketPaymentService.confirmTicketUpgrade(
          ticketId: ticket.id,
          paymentIntentId: paymentData['paymentIntentId'],
        );

        if (mounted) {
          Navigator.pop(context); // Close dialog
          ShowToast().showNormalToast(
            msg: '🎉 Ticket upgraded to VIP Skip-the-Line!',
          );
          // Reload tickets to show updated status
          await _loadUserTickets();
        }
      } else {
        if (mounted) {
          setState(() {
            _isUpgrading = false;
          });
          ShowToast().showNormalToast(msg: 'Upgrade cancelled');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUpgrading = false;
        });
        ShowToast().showNormalToast(
          msg: 'Failed to upgrade ticket: ${e.toString()}',
        );
      }
    }
  }

  // Removed unused _buildCompactChip helper
}
