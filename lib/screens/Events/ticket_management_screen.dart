import 'package:flutter/material.dart';
import 'package:orgami/firebase/firebase_firestore_helper.dart';
import 'package:orgami/models/event_model.dart';
import 'package:orgami/models/ticket_model.dart';
import 'package:orgami/Utils/toast.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:orgami/Screens/Events/ticket_scanner_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';

class TicketManagementScreen extends StatefulWidget {
  final EventModel eventModel;
  final VoidCallback? onBackPressed;

  const TicketManagementScreen({
    super.key,
    required this.eventModel,
    this.onBackPressed,
  });

  @override
  State<TicketManagementScreen> createState() => _TicketManagementScreenState();
}

class _TicketManagementScreenState extends State<TicketManagementScreen> {
  bool isLoading = false;
  List<TicketModel> eventTickets = [];
  final TextEditingController _maxTicketsController = TextEditingController();
  bool isTicketsEnabled = false;
  int maxTickets = 0;
  int issuedTickets = 0;

  @override
  void initState() {
    super.initState();
    isTicketsEnabled = widget.eventModel.ticketsEnabled;
    maxTickets = widget.eventModel.maxTickets;
    issuedTickets = widget.eventModel.issuedTickets;
    _maxTicketsController.text = maxTickets.toString();
    _loadEventTickets();
  }

  @override
  void dispose() {
    _maxTicketsController.dispose();
    super.dispose();
  }

  Future<void> _loadEventTickets() async {
    setState(() {
      isLoading = true;
    });

    try {
      final tickets = await FirebaseFirestoreHelper().getEventTickets(
        eventId: widget.eventModel.id,
      );

      if (mounted) {
        setState(() {
          eventTickets = tickets;
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

  Future<void> _enableTickets() async {
    final maxTicketsInput = int.tryParse(_maxTicketsController.text);
    if (maxTicketsInput == null || maxTicketsInput <= 0) {
      ShowToast().showNormalToast(
        msg: 'Please enter a valid number of tickets',
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      await FirebaseFirestoreHelper().enableTicketsForEvent(
        eventId: widget.eventModel.id,
        maxTickets: maxTicketsInput,
      );

      if (mounted) {
        setState(() {
          isTicketsEnabled = true;
          maxTickets = maxTicketsInput;
          issuedTickets = 0;
          isLoading = false;
        });
        ShowToast().showNormalToast(msg: 'Tickets enabled successfully!');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ShowToast().showNormalToast(msg: 'Failed to enable tickets: $e');
      }
    }
  }

  Future<void> _disableTickets() async {
    setState(() {
      isLoading = true;
    });

    try {
      await FirebaseFirestoreHelper().disableTicketsForEvent(
        eventId: widget.eventModel.id,
      );

      if (mounted) {
        setState(() {
          isTicketsEnabled = false;
          maxTickets = 0;
          issuedTickets = 0;
          isLoading = false;
        });
        ShowToast().showNormalToast(msg: 'Tickets disabled successfully!');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ShowToast().showNormalToast(msg: 'Failed to disable tickets: $e');
      }
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
          'Ticket Management',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontFamily: 'Roboto',
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
            // Call the callback to show Event Management popup again
            if (widget.onBackPressed != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                widget.onBackPressed!();
              });
            }
          },
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadEventTickets,
              color: const Color(0xFF667EEA),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildEventInfo(),
                    const SizedBox(height: 24),
                    _buildTicketSettings(),
                    const SizedBox(height: 24),
                    _buildTicketStats(),
                    const SizedBox(height: 24),
                    _buildTicketList(),
                  ],
                ),
              ),
            ),
      floatingActionButton: eventTickets.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TicketScannerScreen(
                      eventId: widget.eventModel.id,
                      eventTitle: widget.eventModel.title,
                    ),
                  ),
                );

                // Refresh ticket list if a ticket was validated
                if (result == true) {
                  _loadEventTickets();
                  ShowToast().showNormalToast(msg: 'Ticket list updated!');
                }
              },
              backgroundColor: const Color(0xFFFF9800),
              icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
              label: const Text(
                'Scan Tickets',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Roboto',
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildEventInfo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: widget.eventModel.imageUrl,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    width: 60,
                    height: 60,
                    color: const Color(0xFFF5F7FA),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF667EEA),
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: 60,
                    height: 60,
                    color: const Color(0xFFF5F7FA),
                    child: const Icon(
                      Icons.image_not_supported,
                      color: Color(0xFF667EEA),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.eventModel.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                        fontFamily: 'Roboto',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat(
                        'EEEE, MMMM dd, yyyy',
                      ).format(widget.eventModel.selectedDateTime),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTicketSettings() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.confirmation_number,
                  color: Color(0xFF667EEA),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                'Ticket Settings',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (!isTicketsEnabled) ...[
            const Text(
              'Enable tickets for your event to allow attendees to get tickets with QR codes.',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF6B7280),
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _maxTicketsController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Maximum number of tickets',
                hintText: 'Enter number of tickets',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.confirmation_number),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _enableTickets,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF667EEA),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Enable Tickets',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green[600], size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Tickets are enabled',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                    fontFamily: 'Roboto',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Attendees can get tickets with QR codes that you can scan to validate.',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF6B7280),
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: _disableTickets,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Disable Tickets',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTicketStats() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.analytics,
                  color: Color(0xFF667EEA),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                'Ticket Statistics',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  title: 'Total Tickets',
                  value: maxTickets.toString(),
                  icon: Icons.confirmation_number,
                  color: const Color(0xFF667EEA),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  title: 'Issued Tickets',
                  value: issuedTickets.toString(),
                  icon: Icons.person_add,
                  color: const Color(0xFF10B981),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  title: 'Available',
                  value: (maxTickets - issuedTickets).toString(),
                  icon: Icons.event_available,
                  color: const Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  title: 'Used Tickets',
                  value: eventTickets.where((t) => t.isUsed).length.toString(),
                  icon: Icons.check_circle,
                  color: const Color(0xFFEF4444),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'Roboto',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
              fontFamily: 'Roboto',
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTicketList() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.list_alt,
                  color: Color(0xFF667EEA),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                'Issued Tickets',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (eventTickets.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.confirmation_number_outlined,
                      size: 48,
                      color: Color(0xFF9CA3AF),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No tickets issued yet',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF9CA3AF),
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: eventTickets.length,
              itemBuilder: (context, index) {
                final ticket = eventTickets[index];
                return _buildTicketItem(ticket);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTicketItem(TicketModel ticket) {
    return GestureDetector(
      onTap: () => _showTicketDetail(ticket),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ticket.isUsed ? const Color(0xFFF3F4F6) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: ticket.isUsed
                ? const Color(0xFFE5E7EB)
                : const Color(0xFF667EEA).withValues(alpha: 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              spreadRadius: 0,
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: ticket.isUsed
                        ? const Color(0xFF9CA3AF)
                        : const Color(0xFF667EEA).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    ticket.isUsed
                        ? Icons.check_circle
                        : Icons.confirmation_number,
                    color: ticket.isUsed
                        ? const Color(0xFF6B7280)
                        : const Color(0xFF667EEA),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ticket.customerName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: ticket.isUsed
                              ? const Color(0xFF6B7280)
                              : const Color(0xFF1A1A1A),
                          fontFamily: 'Roboto',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Code: ${ticket.ticketCode}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                          fontFamily: 'Roboto',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Issued: ${DateFormat('MMM dd, yyyy').format(ticket.issuedDateTime)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                          fontFamily: 'Roboto',
                        ),
                      ),
                      if (ticket.isUsed) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Used: ${DateFormat('MMM dd, yyyy').format(ticket.usedDateTime!)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFEF4444),
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: ticket.isUsed
                        ? const Color(0xFFEF4444).withValues(alpha: 0.1)
                        : const Color(0xFF10B981).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    ticket.isUsed ? 'Used' : 'Active',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ticket.isUsed
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF10B981),
                      fontFamily: 'Roboto',
                    ),
                  ),
                ),
              ],
            ),
            // QR Code section for active tickets
            if (!ticket.isUsed) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF667EEA).withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF667EEA).withValues(alpha: 0.3),
                        ),
                      ),
                      child: QrImageView(
                        data: ticket.qrCodeData,
                        version: QrVersions.auto,
                        size: 50,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Color(0xFF1A1A1A),
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'QR Code for scanning',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A1A1A),
                              fontFamily: 'Roboto',
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tap to view full QR code',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                              fontFamily: 'Roboto',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: const Color(0xFF6B7280),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ],
          ],
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

  Widget _buildTicketDetailDialog(TicketModel ticket) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              spreadRadius: 0,
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with close button
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF667EEA),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.confirmation_number,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Event Ticket',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),

            // Ticket content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Event image and title
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CachedNetworkImage(
                        imageUrl: ticket.eventImageUrl,
                        height: 120,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          height: 120,
                          color: const Color(0xFFF5F7FA),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF667EEA),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          height: 120,
                          color: const Color(0xFFF5F7FA),
                          child: const Center(
                            child: Icon(
                              Icons.image_not_supported,
                              color: Color(0xFF667EEA),
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Event title
                    Text(
                      ticket.eventTitle,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                        fontFamily: 'Roboto',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),

                    // Event details
                    _buildTicketDetailRow(
                      icon: Icons.location_on,
                      label: 'Location',
                      value: ticket.eventLocation,
                    ),
                    _buildTicketDetailRow(
                      icon: Icons.calendar_today,
                      label: 'Date & Time',
                      value: DateFormat(
                        'EEEE, MMMM dd, yyyy\nh:mm a',
                      ).format(ticket.eventDateTime),
                    ),
                    _buildTicketDetailRow(
                      icon: Icons.person,
                      label: 'Attendee',
                      value: ticket.customerName,
                    ),
                    _buildTicketDetailRow(
                      icon: Icons.confirmation_number,
                      label: 'Ticket Code',
                      value: ticket.ticketCode,
                    ),
                    _buildTicketDetailRow(
                      icon: Icons.schedule,
                      label: 'Issued',
                      value: DateFormat(
                        'MMM dd, yyyy',
                      ).format(ticket.issuedDateTime),
                    ),

                    if (ticket.isUsed) ...[
                      _buildTicketDetailRow(
                        icon: Icons.check_circle,
                        label: 'Used',
                        value: DateFormat(
                          'MMM dd, yyyy',
                        ).format(ticket.usedDateTime!),
                        color: const Color(0xFFEF4444),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // QR Code section (only for active tickets)
                    if (!ticket.isUsed) ...[
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF667EEA,
                          ).withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(
                              0xFF667EEA,
                            ).withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Show this QR code to the event host',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF6B7280),
                                fontFamily: 'Roboto',
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(
                                    0xFF667EEA,
                                  ).withValues(alpha: 0.3),
                                ),
                              ),
                              child: QrImageView(
                                data: ticket.qrCodeData,
                                version: QrVersions.auto,
                                size: 150,
                                backgroundColor: Colors.white,
                                eyeStyle: const QrEyeStyle(
                                  eyeShape: QrEyeShape.square,
                                  color: Color(0xFF1A1A1A),
                                ),
                                dataModuleStyle: const QrDataModuleStyle(
                                  dataModuleShape: QrDataModuleShape.square,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Status indicator
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: ticket.isUsed
                            ? const Color(0xFFEF4444).withValues(alpha: 0.1)
                            : const Color(0xFF10B981).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: ticket.isUsed
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF10B981),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            ticket.isUsed
                                ? Icons.check_circle
                                : Icons.confirmation_number,
                            color: ticket.isUsed
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF10B981),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            ticket.isUsed ? 'Ticket Used' : 'Active Ticket',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: ticket.isUsed
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFF10B981),
                              fontFamily: 'Roboto',
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
    );
  }

  Widget _buildTicketDetailRow({
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: (color ?? const Color(0xFF667EEA)).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: color ?? const Color(0xFF667EEA),
              size: 16,
            ),
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
                    fontFamily: 'Roboto',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color ?? const Color(0xFF1A1A1A),
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
}
