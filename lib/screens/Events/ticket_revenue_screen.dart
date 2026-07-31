import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendus/models/ticket_payment_model.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/Services/ticket_payment_service.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:attendus/widgets/attendus_design_system.dart';

class TicketRevenueScreen extends StatefulWidget {
  final EventModel? eventModel; // If provided, show revenue for specific event

  const TicketRevenueScreen({super.key, this.eventModel});

  @override
  State<TicketRevenueScreen> createState() => _TicketRevenueScreenState();
}

class _TicketRevenueScreenState extends State<TicketRevenueScreen> {
  bool isLoading = true;
  List<TicketPaymentModel> payments = [];
  double totalRevenue = 0;
  int totalTicketsSold = 0;
  Map<String, double> eventRevenue = {};
  Map<String, int> eventTicketsSold = {};

  @override
  void initState() {
    super.initState();
    _loadRevenue();
  }

  Future<void> _loadRevenue() async {
    setState(() {
      isLoading = true;
    });

    try {
      if (CustomerController.logeInCustomer == null) {
        ShowToast().showNormalToast(msg: 'Please log in to view revenue');
        return;
      }

      if (widget.eventModel != null) {
        // Load revenue for specific event
        final revenue = await TicketPaymentService.getEventTicketRevenue(
          widget.eventModel!.id,
        );

        // Load payment records for this event
        final querySnapshot = await FirebaseFirestore.instance
            .collection(TicketPaymentModel.firebaseKey)
            .where('eventId', isEqualTo: widget.eventModel!.id)
            .where('status', isEqualTo: 'completed')
            .orderBy('createdAt', descending: true)
            .get();

        if (mounted) {
          setState(() {
            payments = querySnapshot.docs
                .map((doc) => TicketPaymentModel.fromJson(doc.data()))
                .toList();
            totalRevenue = revenue['totalRevenue'];
            totalTicketsSold = revenue['totalTicketsSold'];
            isLoading = false;
          });
        }
      } else {
        // Load revenue for all events created by this user
        final revenue = await TicketPaymentService.getTicketRevenue(
          CustomerController.logeInCustomer!.uid,
        );

        // Load all payment records for this creator
        final querySnapshot = await FirebaseFirestore.instance
            .collection(TicketPaymentModel.firebaseKey)
            .where(
              'creatorUid',
              isEqualTo: CustomerController.logeInCustomer!.uid,
            )
            .where('status', isEqualTo: 'completed')
            .orderBy('createdAt', descending: true)
            .get();

        final paymentList = querySnapshot.docs
            .map((doc) => TicketPaymentModel.fromJson(doc.data()))
            .toList();

        // Calculate revenue per event
        for (var payment in paymentList) {
          eventRevenue[payment.eventId] =
              (eventRevenue[payment.eventId] ?? 0) + payment.amount;
          eventTicketsSold[payment.eventId] =
              (eventTicketsSold[payment.eventId] ?? 0) + 1;
        }

        if (mounted) {
          setState(() {
            payments = paymentList;
            totalRevenue = revenue['totalRevenue'];
            totalTicketsSold = revenue['totalTicketsSold'];
            isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ShowToast().showNormalToast(msg: 'Failed to load revenue: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.eventModel != null ? 'Ticket Revenue' : 'All Ticket Revenue',
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
      ),
      body: isLoading
          ? const AttendUsLoadingState(label: 'Loading revenue...')
          : RefreshIndicator(
              onRefresh: _loadRevenue,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AttendUsPageSection(
                          title: widget.eventModel != null
                              ? widget.eventModel!.title
                              : 'Ticket revenue',
                          subtitle:
                              'Sales summary, paid ticket activity, and event-level revenue.',
                          icon: Icons.payments_outlined,
                          child: const SizedBox.shrink(),
                        ),
                        if (widget.eventModel != null) _buildEventInfo(),
                        _buildRevenueOverview(),
                        const SizedBox(height: 20),
                        if (widget.eventModel == null &&
                            eventRevenue.isNotEmpty) ...[
                          _buildEventBreakdown(),
                          const SizedBox(height: 20),
                        ],
                        _buildTransactionList(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildEventInfo() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
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
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: widget.eventModel!.imageUrl,
              width: 60,
              height: 60,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                width: 60,
                height: 60,
                color: const Color(0xFFF5F7FA),
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
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
                  widget.eventModel!.title,
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
                  ).format(widget.eventModel!.selectedDateTime),
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
    );
  }

  Widget _buildRevenueOverview() {
    final average = totalTicketsSold > 0 ? totalRevenue / totalTicketsSold : 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: isWide ? 3 : 1,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: isWide ? 2.2 : 3.8,
          children: [
            AttendUsMetricTile(
              label: 'Total revenue',
              value: '\$${totalRevenue.toStringAsFixed(2)}',
              icon: Icons.attach_money,
              tone: AttendUsStatusTone.success,
            ),
            AttendUsMetricTile(
              label: 'Tickets sold',
              value: '$totalTicketsSold',
              icon: Icons.confirmation_number_outlined,
              tone: AttendUsStatusTone.info,
            ),
            AttendUsMetricTile(
              label: 'Average ticket',
              value: '\$${average.toStringAsFixed(2)}',
              icon: Icons.trending_up,
              tone: AttendUsStatusTone.warning,
            ),
          ],
        );
      },
    );
  }

  Widget _buildEventBreakdown() {
    return Container(
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
          const Row(
            children: [
              Icon(Icons.analytics, color: Color(0xFF667EEA)),
              SizedBox(width: 8),
              Text(
                'Revenue by Event',
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
          ...eventRevenue.entries.map((entry) {
            final eventId = entry.key;
            final revenue = entry.value;
            final ticketsSold = eventTicketsSold[eventId] ?? 0;
            final eventTitle = payments
                .firstWhere(
                  (p) => p.eventId == eventId,
                  orElse: () => payments.first,
                )
                .eventTitle;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          eventTitle,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A1A),
                            fontFamily: 'Roboto',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$ticketsSold tickets sold',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '\$${revenue.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF667EEA),
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTransactionList() {
    return Container(
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
          const Row(
            children: [
              Icon(Icons.receipt_long, color: Color(0xFF667EEA)),
              SizedBox(width: 8),
              Text(
                'Recent Transactions',
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
          if (payments.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.receipt_outlined,
                      size: 48,
                      color: Color(0xFF9CA3AF),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No transactions yet',
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
            ...payments
                .take(10)
                .map((payment) => _buildTransactionItem(payment)),
        ],
      ),
    );
  }

  Widget _buildTransactionItem(TicketPaymentModel payment) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.customerName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                    fontFamily: 'Roboto',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('MMM dd, yyyy • HH:mm').format(payment.createdAt),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    fontFamily: 'Roboto',
                  ),
                ),
                if (widget.eventModel == null) ...[
                  const SizedBox(height: 2),
                  Text(
                    payment.eventTitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF667EEA),
                      fontFamily: 'Roboto',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Text(
            '\$${payment.amount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF10B981),
              fontFamily: 'Roboto',
            ),
          ),
        ],
      ),
    );
  }
}
