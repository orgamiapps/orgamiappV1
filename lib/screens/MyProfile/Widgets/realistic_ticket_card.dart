import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';
import 'package:attendus/models/ticket_model.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/MyProfile/Widgets/ticket_shape_clipper.dart';
import 'package:attendus/screens/MyProfile/Widgets/qr_code_modal.dart';
import 'dart:math' as math;

class RealisticTicketCard extends StatefulWidget {
  final TicketModel ticket;
  final EventModel? event;
  final int index;
  final VoidCallback? onFlip;
  final bool enableFlip;
  final VoidCallback? onTap;

  const RealisticTicketCard({
    super.key,
    required this.ticket,
    this.event,
    this.index = 0,
    this.onFlip,
    this.enableFlip = false,
    this.onTap,
  });

  @override
  State<RealisticTicketCard> createState() => _RealisticTicketCardState();
}

class _RealisticTicketCardState extends State<RealisticTicketCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  bool _isFlipped = false;
  bool _showActions = false;

  @override
  void initState() {
    super.initState();

    // Flip animation
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _flipAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _toggleFlip() {
    if (!widget.enableFlip) {
      // If flip is disabled, call the onTap callback instead
      widget.onTap?.call();
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isFlipped = !_isFlipped;
    });

    if (_isFlipped) {
      _flipController.forward();
    } else {
      _flipController.reverse();
    }

    widget.onFlip?.call();
  }

  void _showQRCode() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) =>
            QRCodeModal(ticket: widget.ticket),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 400 + (widget.index * 50)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: AnimatedBuilder(
        animation: _flipAnimation,
        builder: (context, child) {
          final angle = _flipAnimation.value * math.pi;
          final transform = Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle);

          return Transform(
            transform: transform,
            alignment: Alignment.center,
            child: angle >= math.pi / 2
                ? Transform(
                    transform: Matrix4.identity()..rotateY(math.pi),
                    alignment: Alignment.center,
                    child: _buildTicketBack(),
                  )
                : _buildTicketFront(),
          );
        },
      ),
    );
  }

  Widget _buildTicketFront() {
    final isUsed = widget.ticket.isUsed;
    final isVIP = widget.ticket.isSkipTheLine;
    final now = DateTime.now();
    final isUpcoming = widget.ticket.eventDateTime.isAfter(now);
    final isWithin24Hours =
        isUpcoming && widget.ticket.eventDateTime.difference(now).inHours < 24;

    return GestureDetector(
      onTap: _toggleFlip,
      onLongPress: () {
        HapticFeedback.heavyImpact();
        setState(() => _showActions = !_showActions);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 24),
        child: Stack(
          children: [
            // Shadow layer
            ClipPath(
              clipper: const TicketShapeClipper(),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.1),
                ),
              ),
            ),
            // Main ticket with custom shape
            Transform.translate(
              offset: const Offset(0, -4),
              child: ClipPath(
                clipper: const TicketShapeClipper(),
                child: Container(
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Event Image Section
                      _buildImageSection(isUsed, isVIP, isWithin24Hours),

                      // Ticket Details Section
                      _buildTicketDetails(isUsed, isVIP),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSection(bool isUsed, bool isVIP, bool isWithin24Hours) {
    return Stack(
      children: [
        // Event image with rounded corners
        Container(
          margin: const EdgeInsets.all(16),
          height: 180,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: widget.ticket.eventImageUrl,
              width: double.infinity,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: Colors.grey[200],
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF667EEA),
                  ),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey[200],
                child: const Icon(Icons.event, size: 40, color: Colors.grey),
              ),
            ),
          ),
        ),

        // Status badges
        Positioned(
          top: 12,
          right: 12,
          child: Row(
            children: [
              if (isVIP) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'VIP',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          letterSpacing: 1.0,
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
                  color: isUsed
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  isUsed ? 'USED' : 'ACTIVE',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Countdown badge for upcoming events
        if (isWithin24Hours && !isUsed)
          Positioned(
            bottom: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Starts soon!',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTicketDetails(bool isUsed, bool isVIP) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title and Status Badge Row
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.ticket.eventTitle,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                    letterSpacing: -0.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isUsed
                      ? const Color(0xFFE5E7EB)
                      : const Color(0xFF86EFAC),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isUsed ? 'USED' : 'ACTIVE',
                  style: TextStyle(
                    color: isUsed
                        ? const Color(0xFF6B7280)
                        : const Color(0xFF14532D),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Perforated line divider
          CustomPaint(
            size: const Size(double.infinity, 1),
            painter: const PerforatedLinePainter(
              color: Color(0xFFD1D5DB),
              strokeWidth: 1.5,
              dashWidth: 6,
              dashSpace: 4,
            ),
          ),

          const SizedBox(height: 20),

          // Date and time
          _buildInfoRow(
            Icons.calendar_today_outlined,
            DateFormat(
              'MMMM dd, yyyy - h:mm a',
            ).format(widget.ticket.eventDateTime),
            iconColor: const Color(0xFF667EEA),
          ),

          const SizedBox(height: 14),

          // Location
          _buildInfoRow(
            Icons.location_on_outlined,
            widget.ticket.eventLocation,
            iconColor: const Color(0xFF667EEA),
          ),

          const SizedBox(height: 14),

          // Attendee
          _buildInfoRow(
            Icons.person_outline,
            widget.ticket.customerName,
            iconColor: const Color(0xFF667EEA),
          ),

          const SizedBox(height: 14),

          // Ticket code with special styling
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.confirmation_number_outlined,
                  size: 18,
                  color: Color(0xFF667EEA),
                ),
                const SizedBox(width: 12),
                Text(
                  'Code: ',
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 15,
                  ),
                ),
                Text(
                  widget.ticket.ticketCode,
                  style: const TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Issued date
          _buildInfoRow(
            Icons.schedule_outlined,
            'Issued: ${DateFormat('MMMM dd, yyyy').format(widget.ticket.issuedDateTime)}',
            iconColor: const Color(0xFF667EEA),
          ),

          const SizedBox(height: 28),

          // Perforated line before QR
          CustomPaint(
            size: const Size(double.infinity, 1),
            painter: const PerforatedLinePainter(
              color: Color(0xFFD1D5DB),
              strokeWidth: 1.5,
              dashWidth: 6,
              dashSpace: 4,
            ),
          ),

          const SizedBox(height: 28),

          // QR Code - Centered
          Center(
            child: GestureDetector(
              onTap: _showQRCode,
              child: Container(
                padding: const EdgeInsets.all(8),
                child: QrImageView(
                  data: widget.ticket.qrCodeData,
                  version: QrVersions.auto,
                  size: 180,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF000000),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF000000),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text, {Color? iconColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor ?? const Color(0xFF667EEA)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF6B7280),
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketBack() {
    return GestureDetector(
      onTap: _toggleFlip,
      child: Container(
        margin: const EdgeInsets.only(bottom: 24),
        child: Stack(
          children: [
            // Shadow layer
            ClipPath(
              clipper: const TicketShapeClipper(),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.1),
                ),
              ),
            ),
            // Main ticket with custom shape
            Transform.translate(
              offset: const Offset(0, -4),
              child: ClipPath(
                clipper: const TicketShapeClipper(),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFF9FAFB), Colors.white],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildBackSection(
                        'ORDER DETAILS',
                        Icons.receipt_long_rounded,
                      ),
                      const SizedBox(height: 16),
                      _buildBackRow(
                        'Order ID',
                        widget.ticket.id.substring(0, 12),
                      ),
                      _buildBackRow(
                        'Issued',
                        DateFormat(
                          'MMM dd, yyyy',
                        ).format(widget.ticket.issuedDateTime),
                      ),
                      if (widget.ticket.price != null)
                        _buildBackRow(
                          'Price',
                          '\$${widget.ticket.price!.toStringAsFixed(2)}',
                        ),

                      const SizedBox(height: 24),
                      _buildBackSection(
                        'VENUE INFORMATION',
                        Icons.location_city_rounded,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.ticket.eventLocation,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF374151),
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            // Open maps with location
                          },
                          icon: const Icon(Icons.directions_rounded, size: 18),
                          label: const Text('Get Directions'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: Color(0xFF667EEA)),
                            foregroundColor: const Color(0xFF667EEA),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TERMS & CONDITIONS',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[600],
                                letterSpacing: 1.0,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '• Valid for one entry only\n'
                              '• No refunds or exchanges\n'
                              '• Must present QR code at entry',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),
                      Center(
                        child: Text(
                          'Tap to flip back',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackSection(String title, IconData icon) {
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
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              color: Color(0xFF1F2937),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildBackRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
