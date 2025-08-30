import 'package:flutter/material.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/ticket_model.dart';
import 'package:attendus/Services/ticket_payment_service.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

class MyTicketsScreen extends StatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  State<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends State<MyTicketsScreen> {
  List<TicketModel> userTickets = [];
  bool isLoading = true;
  int selectedTab = 0; // 0 = All, 1 = Active, 2 = Used
  final GlobalKey ticketShareKey = GlobalKey();
  bool _isUpgrading = false;

  @override
  void initState() {
    super.initState();
    _loadUserTickets();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF667EEA),
        elevation: 0,
        title: const Text(
          'My Tickets',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontFamily: 'Roboto',
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
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
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF667EEA) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
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
            const SizedBox(height: 4),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 16,
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
    if (filteredTickets.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: filteredTickets.length,
      itemBuilder: (context, index) {
        final ticket = filteredTickets[index];
        return _buildTicketCard(ticket);
      },
    );
  }

  Widget _buildEmptyState() {
    String message;
    IconData icon;

    switch (selectedTab) {
      case 1:
        message = 'No active tickets';
        icon = Icons.confirmation_number_outlined;
        break;
      case 2:
        message = 'No used tickets';
        icon = Icons.check_circle_outline;
        break;
      default:
        message = 'No tickets yet';
        icon = Icons.confirmation_number_outlined;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: const Color(0xFF9CA3AF)),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(
                fontSize: 18,
                color: Color(0xFF9CA3AF),
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              selectedTab == 0
                  ? 'Get tickets from events to see them here'
                  : 'Tickets will appear here when you get them',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF9CA3AF),
                fontFamily: 'Roboto',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTicketCard(TicketModel ticket) {
    final bool isUsed = ticket.isUsed;
    final Color statusColor = isUsed
        ? const Color(0xFF6B7280)
        : const Color(0xFF10B981);
    final String statusText = isUsed ? 'Used' : 'Active';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () => _showTicketDetail(ticket),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: ticket.eventImageUrl,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  placeholder: (context, url) =>
                      Container(width: 80, height: 80, color: Colors.grey[200]),
                  errorWidget: (context, url, error) => Icon(Icons.error),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            ticket.eventTitle,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (ticket.isSkipTheLine) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                margin: const EdgeInsets.only(bottom: 4),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFFFD700),
                                      Color(0xFFFFA500),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFFFFD700,
                                      ).withValues(alpha: 0.3),
                                      blurRadius: 4,
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
                                      size: 12,
                                    ),
                                    SizedBox(width: 3),
                                    Text(
                                      'VIP',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: statusColor.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat(
                            'MMM dd - h:mm a',
                          ).format(ticket.eventDateTime),
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            ticket.eventLocation,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.qr_code, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          'Ticket Code: ${ticket.ticketCode}',
                          style: TextStyle(
                            color: Colors.grey[800],
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => _shareTicket(ticket),
                          icon: const Icon(Icons.ios_share, size: 20),
                          color: const Color(0xFF667EEA),
                          tooltip: 'Share',
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
    );
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

      await SharePlus.instance.share(
        ShareParams(
          text:
              'My AttendUs Ticket • ${ticket.eventTitle} • Code: ${ticket.ticketCode}',
          files: [XFile(file.path)],
        ),
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
                                      : const Color(0xFF10B981))
                                  .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          ticket.isUsed ? 'USED' : 'ACTIVE',
                          style: TextStyle(
                            color: ticket.isUsed
                                ? Colors.red
                                : const Color(0xFF10B981),
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
      insetPadding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxHeight = constraints.maxHeight;
          final imageHeight = maxHeight * 0.25;
          final qrSize = maxHeight * 0.3;

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  // Premium gradient background
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                      ),
                    ),
                  ),
                  // White ticket area with shape
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 32,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: LayoutBuilder(
                          builder: (context, ticketConstraints) {
                            final notchTop =
                                imageHeight +
                                16; // Position notches below image
                            return Stack(
                              children: [
                                // Notches
                                Positioned(
                                  left: -12,
                                  top: notchTop,
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF667EEA),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: -12,
                                  top: notchTop,
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF667EEA),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                // Content
                                SingleChildScrollView(
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Event Image
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: CachedNetworkImage(
                                            imageUrl: ticket.eventImageUrl,
                                            height: imageHeight,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        // Title and Status
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                ticket.eventTitle,
                                                style: const TextStyle(
                                                  fontSize: 24,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF1F2937),
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 8,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: ticket.isUsed
                                                    ? Colors.red[100]
                                                    : Colors.green[100],
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                ticket.isUsed
                                                    ? 'USED'
                                                    : 'ACTIVE',
                                                style: TextStyle(
                                                  color: ticket.isUsed
                                                      ? Colors.red
                                                      : Colors.green,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (ticket.isSkipTheLine) ...[
                                          const SizedBox(height: 12),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 12,
                                            ),
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [
                                                  Color(0xFFFFD700),
                                                  Color(0xFFFFA500),
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(
                                                    0xFFFFD700,
                                                  ).withValues(alpha: 0.3),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: const Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.flash_on,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                                SizedBox(width: 8),
                                                Text(
                                                  'VIP Skip-the-Line Ticket',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 16),
                                        // Details
                                        _buildDetailRow(
                                          Icons.calendar_today,
                                          DateFormat(
                                            'MMMM dd, yyyy - h:mm a',
                                          ).format(ticket.eventDateTime),
                                        ),
                                        _buildDetailRow(
                                          Icons.location_on,
                                          ticket.eventLocation,
                                        ),
                                        _buildDetailRow(
                                          Icons.person,
                                          ticket.customerName,
                                        ),
                                        _buildDetailRow(
                                          Icons.confirmation_number,
                                          'Code: ${ticket.ticketCode}',
                                        ),
                                        _buildDetailRow(
                                          Icons.access_time,
                                          'Issued: ${DateFormat('MMMM dd, yyyy').format(ticket.issuedDateTime)}',
                                        ),
                                        // Upgrade button for eligible tickets
                                        if (!ticket.isUsed &&
                                            !ticket.isSkipTheLine &&
                                            ticket.price != null &&
                                            ticket.price! > 0) ...[
                                          const SizedBox(height: 16),
                                          _buildUpgradeButton(ticket),
                                        ],
                                        const SizedBox(height: 24),
                                        // QR Code
                                        Center(
                                          child: ticket.isUsed
                                              ? const Column(
                                                  children: [
                                                    Icon(
                                                      Icons.check_circle,
                                                      size: 80,
                                                      color: Colors.red,
                                                    ),
                                                    SizedBox(height: 8),
                                                    Text(
                                                      'Ticket Already Used',
                                                      style: TextStyle(
                                                        fontSize: 18,
                                                        color: Colors.red,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              : QrImageView(
                                                  data: ticket.qrCodeData,
                                                  version: QrVersions.auto,
                                                  size: qrSize,
                                                  gapless: false,
                                                  backgroundColor: Colors.white,
                                                ),
                                        ),
                                        const SizedBox(height: 16),
                                        // Footer
                                        const Center(
                                          child: Text(
                                            'Show QR to event organizer\nPowered by AttendUs',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.grey,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  // Close button
                  Positioned(
                    right: 16,
                    top: 16,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF667EEA), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 16, color: Color(0xFF4B5563)),
            ),
          ),
        ],
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
                            'Priority entry • \$${(ticket.price! * 5).toStringAsFixed(2)}',
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
    final upgradePrice = ticket.price! * 5;

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
            const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 32),
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
          const Icon(Icons.check, color: Color(0xFF10B981), size: 20),
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
