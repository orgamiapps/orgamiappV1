import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:attendus/models/ticket_model.dart';
import 'package:attendus/models/event_model.dart';

/// Compact horizontal ticket card for list view
class CompactTicketCard extends StatelessWidget {
  final TicketModel ticket;
  final EventModel? event;
  final int index;
  final VoidCallback? onTap;

  const CompactTicketCard({
    super.key,
    required this.ticket,
    this.event,
    this.index = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUsed = ticket.isUsed;
    final isVIP = ticket.isSkipTheLine;
    final now = DateTime.now();
    final isUpcoming = ticket.eventDateTime.isAfter(now);
    final isWithin24Hours =
        isUpcoming && ticket.eventDateTime.difference(now).inHours < 24;

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
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              onTap?.call();
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: isWithin24Hours && !isUsed
                    ? Border.all(
                        color: const Color(0xFF667EEA).withValues(alpha: 0.4),
                        width: 2,
                      )
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: isWithin24Hours && !isUsed
                        ? const Color(0xFF667EEA).withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.06),
                    blurRadius: isWithin24Hours && !isUsed ? 12 : 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Event image on the left
                  _buildEventImage(isUsed, isVIP, isWithin24Hours),

                  // Ticket details on the right
                  Expanded(
                    child: _buildTicketDetails(isUsed, isVIP, isWithin24Hours),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEventImage(bool isUsed, bool isVIP, bool isWithin24Hours) {
    return Container(
      width: 120,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          bottomLeft: Radius.circular(16),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Event image
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              bottomLeft: Radius.circular(16),
            ),
            child: CachedNetworkImage(
              imageUrl: ticket.eventImageUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(color: Colors.grey[200]),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey[200],
                child: const Icon(Icons.event, size: 40, color: Colors.grey),
              ),
            ),
          ),

          // Gradient overlay
          Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isUsed
                    ? [
                        Colors.black.withValues(alpha: 0.3),
                        Colors.black.withValues(alpha: 0.6),
                      ]
                    : [Colors.transparent, Colors.black.withValues(alpha: 0.3)],
              ),
            ),
          ),

          // Status badge overlay
          if (isVIP || isUsed)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isVIP
                      ? const Color(0xFFFFD700)
                      : const Color(0xFF9CA3AF),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isVIP)
                      const Icon(Icons.star, color: Colors.white, size: 10),
                    if (isVIP) const SizedBox(width: 3),
                    Text(
                      isVIP ? 'VIP' : 'USED',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 9,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Countdown badge
          if (isWithin24Hours && !isUsed)
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      color: Colors.white,
                      size: 10,
                    ),
                    SizedBox(width: 3),
                    Text(
                      'SOON',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTicketDetails(bool isUsed, bool isVIP, bool isWithin24Hours) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Top section: Title and status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ticket.eventTitle,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937),
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isUsed
                            ? const Color(0xFF9CA3AF).withValues(alpha: 0.15)
                            : const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isUsed ? 'USED' : 'ACTIVE',
                        style: TextStyle(
                          color: isUsed
                              ? const Color(0xFF6B7280)
                              : const Color(0xFF059669),
                          fontWeight: FontWeight.bold,
                          fontSize: 9,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Bottom section: Date and location
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date and time
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 12,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      DateFormat(
                        'EEE, MMM dd • h:mm a',
                      ).format(ticket.eventDateTime),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Location
              Row(
                children: [
                  Icon(
                    Icons.location_on_rounded,
                    size: 12,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      ticket.eventLocation,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
