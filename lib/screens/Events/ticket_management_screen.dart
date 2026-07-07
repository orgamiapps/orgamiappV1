import 'package:flutter/material.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/models/ticket_model.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:attendus/screens/Events/ticket_scanner_screen.dart';
import 'package:attendus/Services/ticket_payment_service.dart';
import 'package:attendus/screens/Events/ticket_revenue_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:attendus/Utils/app_app_bar_view.dart';

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
  final TextEditingController _ticketPriceController = TextEditingController();
  final TextEditingController _upgradePriceController = TextEditingController();
  bool isTicketsEnabled = false;
  int maxTickets = 0;
  int issuedTickets = 0;
  double? ticketPrice;
  bool isUpgradeEnabled = false;
  double? upgradePrice;
  final GlobalKey ticketShareKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    isTicketsEnabled = widget.eventModel.ticketsEnabled;
    maxTickets = widget.eventModel.maxTickets;
    issuedTickets = widget.eventModel.issuedTickets;
    ticketPrice = widget.eventModel.ticketPrice;
    isUpgradeEnabled = widget.eventModel.ticketUpgradeEnabled;
    upgradePrice = widget.eventModel.ticketUpgradePrice;
    _maxTicketsController.text = maxTickets.toString();
    if (ticketPrice != null && ticketPrice! > 0) {
      _ticketPriceController.text = ticketPrice!.toStringAsFixed(2);
    }
    if (upgradePrice != null && upgradePrice! > 0) {
      _upgradePriceController.text = upgradePrice!.toStringAsFixed(2);
    }
    _loadEventTickets();
  }

  @override
  void dispose() {
    _maxTicketsController.dispose();
    _ticketPriceController.dispose();
    _upgradePriceController.dispose();
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

    // Parse ticket price if provided
    double? priceInput;
    if (_ticketPriceController.text.isNotEmpty) {
      priceInput = double.tryParse(_ticketPriceController.text);
      if (priceInput != null && priceInput < 0) {
        ShowToast().showNormalToast(msg: 'Please enter a valid ticket price');
        return;
      }
    }

    // Parse upgrade price if upgrade is enabled
    double? upgradePriceInput;
    if (isUpgradeEnabled && _upgradePriceController.text.isNotEmpty) {
      upgradePriceInput = double.tryParse(_upgradePriceController.text);
      if (upgradePriceInput == null || upgradePriceInput < 0) {
        ShowToast().showNormalToast(msg: 'Please enter a valid upgrade price');
        return;
      }
      // Ensure upgrade price is higher than base ticket price
      if (priceInput != null && upgradePriceInput <= priceInput) {
        ShowToast().showNormalToast(
          msg: 'Upgrade price must be higher than base ticket price',
        );
        return;
      }
    }

    setState(() {
      isLoading = true;
    });

    try {
      await FirebaseFirestoreHelper().enableTicketsForEvent(
        eventId: widget.eventModel.id,
        maxTickets: maxTicketsInput,
        ticketPrice: priceInput,
        ticketUpgradeEnabled: isUpgradeEnabled,
        ticketUpgradePrice: upgradePriceInput,
      );

      if (mounted) {
        setState(() {
          isTicketsEnabled = true;
          maxTickets = maxTicketsInput;
          ticketPrice = priceInput;
          upgradePrice = upgradePriceInput;
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

  void _showEditPriceDialog() {
    final TextEditingController newPriceController = TextEditingController();
    final TextEditingController newUpgradePriceController =
        TextEditingController();

    // Pre-fill current values
    if (ticketPrice != null && ticketPrice! > 0) {
      newPriceController.text = ticketPrice!.toStringAsFixed(2);
    }
    if (upgradePrice != null && upgradePrice! > 0) {
      newUpgradePriceController.text = upgradePrice!.toStringAsFixed(2);
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.edit, color: Color(0xFF667EEA), size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Edit Ticket Pricing',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                  fontFamily: 'Roboto',
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFD97706)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning, color: Color(0xFFD97706), size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Price changes will only affect new ticket purchases.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF92400E),
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: newPriceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Ticket Price (USD)',
                  hintText: 'Enter new price or leave empty for free',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.attach_money),
                  helperText:
                      'Current: ${ticketPrice != null && ticketPrice! > 0 ? '\$${ticketPrice!.toStringAsFixed(2)}' : 'Free'}',
                ),
              ),
              if (isUpgradeEnabled) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: newUpgradePriceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'VIP Upgrade Price (USD)',
                    hintText: 'Enter new VIP price',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(
                      Icons.star,
                      color: Color(0xFFFFD700),
                    ),
                    helperText:
                        'Current: ${upgradePrice != null && upgradePrice! > 0 ? '\$${upgradePrice!.toStringAsFixed(2)}' : 'Not set'}',
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              newPriceController.dispose();
              newUpgradePriceController.dispose();
              Navigator.pop(context);
            },
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              _updateTicketPrice(newPriceController, newUpgradePriceController);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF667EEA),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Update Price',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateTicketPrice(
    TextEditingController priceController,
    TextEditingController upgradePriceController,
  ) async {
    // Parse new ticket price
    double? newPrice;
    if (priceController.text.isNotEmpty) {
      newPrice = double.tryParse(priceController.text);
      if (newPrice != null && newPrice < 0) {
        ShowToast().showNormalToast(msg: 'Please enter a valid ticket price');
        return;
      }
    }

    // Parse new upgrade price if upgrade is enabled
    double? newUpgradePrice;
    if (isUpgradeEnabled && upgradePriceController.text.isNotEmpty) {
      newUpgradePrice = double.tryParse(upgradePriceController.text);
      if (newUpgradePrice == null || newUpgradePrice < 0) {
        ShowToast().showNormalToast(msg: 'Please enter a valid upgrade price');
        return;
      }
      // Ensure upgrade price is higher than base ticket price
      if (newPrice != null && newUpgradePrice <= newPrice) {
        ShowToast().showNormalToast(
          msg: 'Upgrade price must be higher than base ticket price',
        );
        return;
      }
    }

    setState(() {
      isLoading = true;
    });

    try {
      await FirebaseFirestoreHelper().updateTicketPrice(
        eventId: widget.eventModel.id,
        ticketPrice: newPrice ?? 0,
        ticketUpgradePrice: newUpgradePrice,
      );

      if (mounted) {
        setState(() {
          ticketPrice = newPrice;
          upgradePrice = newUpgradePrice;
          isLoading = false;
        });

        // Update the text controllers for display
        if (newPrice != null && newPrice > 0) {
          _ticketPriceController.text = newPrice.toStringAsFixed(2);
        } else {
          _ticketPriceController.clear();
        }

        if (newUpgradePrice != null && newUpgradePrice > 0) {
          _upgradePriceController.text = newUpgradePrice.toStringAsFixed(2);
        }

        ShowToast().showNormalToast(
          msg: 'Ticket pricing updated successfully!',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ShowToast().showNormalToast(msg: 'Failed to update pricing: $e');
      }
    } finally {
      priceController.dispose();
      upgradePriceController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      body: SafeArea(
        child: Column(
          children: [
            AppAppBarView.modernHeader(
              context: context,
              title: 'Ticket Management',
              subtitle: 'Manage tickets and settings for your event',
              trailing: widget.onBackPressed != null
                  ? IconButton(
                      icon: const Icon(Icons.settings),
                      onPressed: () {
                        Navigator.pop(context);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          widget.onBackPressed!();
                        });
                      },
                    )
                  : null,
            ),
            Expanded(
              child: isLoading
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
                            if (ticketPrice != null && ticketPrice! > 0) ...[
                              const SizedBox(height: 24),
                              _buildRevenueButton(),
                            ],
                            const SizedBox(height: 24),
                            _buildTicketList(),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
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
            TextField(
              controller: _ticketPriceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Ticket price (USD)',
                hintText: 'Leave empty for free tickets',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.attach_money),
                helperText:
                    'Set a price per ticket or leave empty for free tickets',
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.rocket_launch,
                        color: Color(0xFF764BA2),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: const Text(
                          'VIP Skip-the-Line Upgrades (Optional)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A),
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Checkbox(
                        value: isUpgradeEnabled,
                        onChanged: (value) {
                          setState(() {
                            isUpgradeEnabled = value ?? false;
                          });
                        },
                        activeColor: const Color(0xFF764BA2),
                      ),
                      const Expanded(
                        child: Text(
                          'Allow ticket holders to upgrade to VIP',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF6B7280),
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (isUpgradeEnabled) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _upgradePriceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'VIP Upgrade Price (USD)',
                        hintText: 'Total price for VIP ticket',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(
                          Icons.star,
                          color: Color(0xFFFFD700),
                        ),
                        helperText:
                            'This is the total price (not additional cost)',
                      ),
                    ),
                  ],
                ],
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
                Icon(
                  Icons.check_circle,
                  color: const Color(0xFF667EEA),
                  size: 20,
                ),
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
            if (ticketPrice != null && ticketPrice! > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.attach_money,
                          size: 16,
                          color: Color(0xFF10B981),
                        ),
                        Text(
                          'Ticket Price: \$${ticketPrice!.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF10B981),
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: _showEditPriceDialog,
                    icon: const Icon(
                      Icons.edit,
                      size: 16,
                      color: Color(0xFF667EEA),
                    ),
                    label: const Text(
                      'Edit Price',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF667EEA),
                        fontFamily: 'Roboto',
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      backgroundColor: const Color(
                        0xFF667EEA,
                      ).withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (ticketPrice == null || ticketPrice == 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6B7280).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.local_offer,
                          size: 16,
                          color: Color(0xFF6B7280),
                        ),
                        Text(
                          'Free Tickets',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6B7280),
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: _showEditPriceDialog,
                    icon: const Icon(
                      Icons.attach_money,
                      size: 16,
                      color: Color(0xFF667EEA),
                    ),
                    label: const Text(
                      'Set Price',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF667EEA),
                        fontFamily: 'Roboto',
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      backgroundColor: const Color(
                        0xFF667EEA,
                      ).withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
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

  Widget _buildRevenueButton() {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                TicketRevenueScreen(eventModel: widget.eventModel),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF667EEA).withValues(alpha: 0.3),
              spreadRadius: 0,
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.attach_money,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'View Revenue',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Track your ticket sales and earnings',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 20),
          ],
        ),
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
                  color: const Color(0xFF667EEA),
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
                        : const Color(0xFF667EEA).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    ticket.isUsed ? 'Used' : 'Active',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ticket.isUsed
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF667EEA),
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
            const SizedBox(height: 12),
            if (!ticket.isUsed &&
                !ticket.isSkipTheLine &&
                (ticket.price ?? 0) > 0 &&
                widget.eventModel.ticketUpgradeEnabled &&
                widget.eventModel.ticketUpgradePrice != null) ...[
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: () => _showUpgradeDialog(ticket),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF764BA2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(
                    Icons.rocket_launch,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: Text(
                    'Upgrade to VIP • \$${widget.eventModel.ticketUpgradePrice!.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Roboto',
                    ),
                  ),
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
            'AttendUs Ticket • ${ticket.eventTitle} • Code: ${ticket.ticketCode}',
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
                        bottom: MediaQuery.of(context).padding.bottom + 16,
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
                              'Show this QR code to scan at entry',
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

                    // Upgrade button for eligible tickets
                    if (!ticket.isUsed &&
                        !ticket.isSkipTheLine &&
                        (ticket.price ?? 0) > 0 &&
                        widget.eventModel.ticketUpgradeEnabled &&
                        widget.eventModel.ticketUpgradePrice != null) ...[
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _showUpgradeDialog(ticket);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF667EEA),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.flash_on, color: Colors.white),
                          label: Text(
                            'Upgrade to VIP • \$${widget.eventModel.ticketUpgradePrice!.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Roboto',
                            ),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

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

  Widget _buildInlineUpgradeBanner(TicketModel ticket) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFD700).withValues(alpha: 0.15),
            const Color(0xFFFFA500).withValues(alpha: 0.15),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFFD700).withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: const Row(
        children: [
          Icon(Icons.priority_high, color: Color(0xFFFFA500), size: 22),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'VIP Skip-the-Line Available',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFF8C00),
                    fontFamily: 'Roboto',
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Upgrade now for priority entry at the venue.',
                  style: TextStyle(
                    fontSize: 12,
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

  void _showUpgradeDialog(TicketModel ticket) {
    final upgradePrice = widget.eventModel.ticketUpgradePrice ?? 0;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.flash_on, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Upgrade to VIP Skip-the-Line',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildInlineUpgradeBanner(ticket),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Upgrade Price:',
                  style: TextStyle(color: Color(0xFF6B7280)),
                ),
                const SizedBox(width: 6),
                Text(
                  '\$${upgradePrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _upgradeTicket(ticket);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF667EEA),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Upgrade Now',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _upgradeTicket(TicketModel ticket) async {
    try {
      final paymentData =
          await TicketPaymentService.createTicketUpgradePaymentIntent(
            ticketId: ticket.id,
            originalPrice: ticket.price ?? 0,
            upgradePrice: widget.eventModel.ticketUpgradePrice ?? 0,
            customerUid: ticket.customerUid,
            customerName: ticket.customerName,
            customerEmail:
                'noreply@orgami.app', // Fallback if email not fetched here
            eventTitle: ticket.eventTitle,
          );

      final paid = await TicketPaymentService.processTicketUpgrade(
        clientSecret: paymentData['clientSecret'],
        eventTitle: ticket.eventTitle,
        upgradeAmount: paymentData['upgradeAmount'],
      );

      if (!paid) {
        ShowToast().showNormalToast(msg: 'Upgrade cancelled');
        return;
      }

      await TicketPaymentService.confirmTicketUpgrade(
        ticketId: ticket.id,
        paymentIntentId: paymentData['paymentIntentId'],
      );

      ShowToast().showNormalToast(msg: 'Ticket upgraded to VIP');
      _loadEventTickets();
    } catch (e) {
      ShowToast().showNormalToast(msg: 'Failed to upgrade: $e');
    }
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
}
