import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/ticket_model.dart';
import 'package:attendus/models/attendance_model.dart';
import 'package:attendus/Utils/toast.dart';
import 'package:attendus/Utils/qr_debug_helper.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:attendus/models/badge_model.dart';
import 'package:attendus/Permissions/permissions_helper.dart';
import 'package:attendus/Services/nfc_badge_service.dart';
import 'package:attendus/controller/customer_controller.dart';

class TicketScannerScreen extends StatefulWidget {
  final String eventId;
  final String eventTitle;

  const TicketScannerScreen({
    super.key,
    required this.eventId,
    required this.eventTitle,
  });

  @override
  State<TicketScannerScreen> createState() => _TicketScannerScreenState();
}

class _TicketScannerScreenState extends State<TicketScannerScreen> {
  final TextEditingController _ticketCodeController = TextEditingController();
  final NFCBadgeService _nfcService = NFCBadgeService();

  bool isLoading = false;
  TicketModel? scannedTicket;
  bool isScanning = false;
  bool isNFCScanning = false;
  bool isNFCAvailable = false;
  String nfcStatus = 'Ready to scan';

  @override
  void initState() {
    super.initState();
    _ticketCodeController.addListener(_onTicketCodeChanged);
    _initializeNFC();
  }

  Future<void> _initializeNFC() async {
    final available = await _nfcService.isNFCAvailable();
    if (mounted) {
      setState(() {
        isNFCAvailable = available;
      });
    }
  }

  void _onTicketCodeChanged() {
    setState(() {
      // This will trigger a rebuild when the text changes
    });
  }

  @override
  void dispose() {
    _ticketCodeController.removeListener(_onTicketCodeChanged);
    _ticketCodeController.dispose();
    _stopNFCScanning();
    super.dispose();
  }

  Future<void> _scanTicket() async {
    final ticketCode = _ticketCodeController.text.trim();
    if (ticketCode.isEmpty) {
      ShowToast().showNormalToast(msg: 'Please enter a ticket code');
      return;
    }

    await _processTicketCode(ticketCode);
  }

  Future<void> _startNFCScanning() async {
    if (!isNFCAvailable) {
      _showScanResult(
        success: false,
        title: 'NFC Not Available',
        message: 'NFC is not available on this device or is disabled.',
      );
      return;
    }

    if (isNFCScanning) {
      await _stopNFCScanning();
      return;
    }

    setState(() {
      isNFCScanning = true;
      nfcStatus = 'Starting NFC scan...';
    });

    try {
      final organizerUid = CustomerController.logeInCustomer?.uid ?? '';

      final result = await _nfcService.startNFCBadgeReading(
        eventId: widget.eventId,
        organizerUid: organizerUid,
        onStatusUpdate: (status) {
          if (mounted) {
            setState(() {
              nfcStatus = status;
            });
          }
        },
        timeout: const Duration(seconds: 30),
      );

      if (mounted) {
        setState(() {
          isNFCScanning = false;
          nfcStatus = 'Ready to scan';
        });

        if (result.isSuccess && result.ticket != null) {
          setState(() {
            scannedTicket = result.ticket;
          });

          _showScanResult(
            success: true,
            title: 'Ticket Activated!',
            message: result.message ?? 'Ticket activated successfully via NFC',
          );
        } else {
          _showScanResult(
            success: false,
            title: 'NFC Scan Failed',
            message: result.error ?? 'Failed to activate ticket via NFC',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isNFCScanning = false;
          nfcStatus = 'Ready to scan';
        });

        _showScanResult(
          success: false,
          title: 'NFC Error',
          message: 'Error during NFC scan: $e',
        );
      }
    }
  }

  Future<void> _stopNFCScanning() async {
    if (isNFCScanning) {
      await _nfcService.stopNFCSession(message: 'NFC scanning stopped');
      if (mounted) {
        setState(() {
          isNFCScanning = false;
          nfcStatus = 'Ready to scan';
        });
      }
    }
  }

  Future<void> _processTicketCode(String ticketCode) async {
    setState(() {
      isLoading = true;
    });

    try {
      final ticket = await FirebaseFirestoreHelper().getTicketByCode(
        ticketCode: ticketCode,
      );

      if (mounted) {
        setState(() {
          scannedTicket = ticket;
          isLoading = false;
        });

        if (ticket == null) {
          _showScanResult(
            success: false,
            title: 'Invalid Ticket',
            message: 'No ticket found for the scanned code.',
          );
        } else if (ticket.eventId != widget.eventId) {
          _showScanResult(
            success: false,
            title: 'Wrong Event',
            message:
                'This ticket belongs to "${ticket.eventTitle}" and is not valid for this event.',
          );
        } else if (ticket.isUsed) {
          final usedDate = ticket.usedDateTime != null
              ? DateFormat('MMM dd, yyyy – h:mm a').format(ticket.usedDateTime!)
              : 'Unknown time';
          _showScanResult(
            success: false,
            title: 'Already Used',
            message:
                'This ticket was already used${ticket.usedBy != null ? ' by ${ticket.usedBy}' : ''} on $usedDate.',
          );
        } else {
          _showTicketValidationDialog(ticket);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        _showScanResult(
          success: false,
          title: 'Scan Error',
          message: 'Error scanning ticket. Please try again. ($e)',
        );
      }
    }
  }

  Future<void> _processUserBadge(String userId) async {
    setState(() {
      isLoading = true;
    });

    try {
      final ticket = await FirebaseFirestoreHelper()
          .getActiveTicketForUserAndEvent(
            customerUid: userId,
            eventId: widget.eventId,
          );

      if (mounted) {
        setState(() {
          scannedTicket = ticket;
          isLoading = false;
        });

        if (ticket == null) {
          _showScanResult(
            success: false,
            title: 'No Ticket Found',
            message: 'This badge has no active ticket for this event.',
          );
        } else {
          _showTicketValidationDialog(ticket);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        _showScanResult(
          success: false,
          title: 'Scan Error',
          message: 'Error scanning badge. Please try again. ($e)',
        );
      }
    }
  }

  void _showTicketValidationDialog(TicketModel ticket) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Expanded(
              child: Text(
                'Validate Ticket',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Roboto',
                ),
              ),
            ),
            if (ticket.isSkipTheLine) ...[
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
                      color: const Color(0xFFFFD700).withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flash_on, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'VIP',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ticket.isSkipTheLine) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
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
                    width: 2,
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.priority_high,
                      color: Color(0xFFFFA500),
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SKIP THE LINE - VIP TICKET',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFF8C00),
                              fontFamily: 'Roboto',
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Priority entry - Let them skip the queue!',
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
              ),
            ],
            Text(
              'Ticket Code: ${ticket.ticketCode}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Customer: ${ticket.customerName}',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF6B7280),
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Issued: ${DateFormat('MMM dd, yyyy').format(ticket.issuedDateTime)}',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF6B7280),
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Do you want to validate this ticket?',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF6B7280),
                fontFamily: 'Roboto',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF6B7280), fontFamily: 'Roboto'),
            ),
          ),
          ElevatedButton(
            onPressed: () => _validateTicket(ticket),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF667EEA),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Validate',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontFamily: 'Roboto',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Present a clear success/failure result after scanning/activation
  void _showScanResult({
    required bool success,
    required String title,
    String? message,
  }) {
    // Pause scanning so we don't immediately scan again under the sheet
    if (mounted) {
      setState(() {
        isScanning = false;
      });
    }

    showModalBottomSheet(
      context: context,
      isDismissible: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color:
                      (success
                              ? const Color(0xFF667EEA)
                              : const Color(0xFFEF4444))
                          .withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  success ? Icons.check_circle : Icons.error_outline,
                  color: success
                      ? const Color(0xFF667EEA)
                      : const Color(0xFFEF4444),
                  size: 36,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: success
                      ? const Color(0xFF065F46)
                      : const Color(0xFF991B1B),
                  fontFamily: 'Roboto',
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                    fontFamily: 'Roboto',
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    if (mounted) {
                      setState(() {
                        // Clear any previous ticket info and resume scanning
                        scannedTicket = null;
                        _ticketCodeController.clear();
                        isScanning = true;
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF667EEA),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Scan Next',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      fontFamily: 'Roboto',
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

  Future<void> _validateTicket(TicketModel ticket) async {
    Navigator.pop(context); // Close dialog

    setState(() {
      isLoading = true;
    });

    try {
      // First, check if user is already signed in to attendance
      final existingAttendance = await FirebaseFirestoreHelper()
          .getAttendanceByUserAndEvent(
            customerUid: ticket.customerUid,
            eventId: ticket.eventId,
          );

      // Validate the ticket
      await FirebaseFirestoreHelper().useTicket(
        ticketId: ticket.id,
        usedBy: 'Event Host',
      );

      // If user is not already signed in to attendance, add them
      if (existingAttendance == null) {
        final attendanceId = '${ticket.eventId}-${ticket.customerUid}';
        final attendanceModel = AttendanceModel(
          id: attendanceId,
          eventId: ticket.eventId,
          userName: ticket.customerName,
          customerUid: ticket.customerUid,
          attendanceDateTime: DateTime.now(),
          answers: [],
        );

        await FirebaseFirestoreHelper().addAttendance(attendanceModel);
      }

      if (mounted) {
        setState(() {
          isLoading = false;
        });
        _showScanResult(
          success: true,
          title: 'Ticket Activated',
          message: existingAttendance == null
              ? 'Ticket validated and attendee signed in successfully.'
              : 'Ticket validated successfully.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        _showScanResult(
          success: false,
          title: 'Activation Failed',
          message: 'Failed to validate ticket. Please try again. ($e)',
        );
      }
    }
  }

  Future<void> _toggleScanning() async {
    if (!isScanning) {
      // Check camera permission before starting scanner
      final hasPermission = await PermissionsHelperClass.checkCameraPermission(
        context: context,
      );

      if (!hasPermission) {
        ShowToast().showNormalToast(
          msg: 'Camera permission is required to scan QR codes',
        );
        return;
      }
    }

    setState(() {
      isScanning = !isScanning;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: const Color(0xFF667EEA),
        elevation: 0,
        title: const Text(
          'Ticket Scanner',
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
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            _buildEventInfo(),
            const SizedBox(height: 24),
            _buildScannerSection(),
            const SizedBox(height: 24),
            if (scannedTicket != null) _buildTicketInfo(),
            // Add extra space equal to keyboard inset to avoid overflow
            SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 12),
          ],
        ),
      ),
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
            color: Colors.black.withAlpha(20),
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
                  color: const Color(0xFF667EEA).withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.event,
                  color: Color(0xFF667EEA),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                'Event',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.eventTitle,
            style: const TextStyle(
              fontSize: 16,
              color: Color(0xFF1A1A1A),
              fontFamily: 'Roboto',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerSection() {
    final mediaQuery = MediaQuery.of(context);
    final isPortrait = mediaQuery.orientation == Orientation.portrait;
    final screenHeight = mediaQuery.size.height;
    // Responsive camera viewport: comfortable slice of screen, clamped for extremes
    final double suggested = isPortrait
        ? screenHeight * 0.28
        : screenHeight * 0.5;
    final double scannerHeight = suggested < 240
        ? 240
        : (suggested > 420 ? 420 : suggested);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
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
                  color: const Color(0xFFFF9800).withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.qr_code_scanner,
                  color: Color(0xFFFF9800),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                'Manual Entry',
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
          const Text(
            'Scan the QR code or enter the ticket code manually to validate tickets.',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
              fontFamily: 'Roboto',
            ),
          ),
          const SizedBox(height: 20),

          // QR Scanner Section
          if (isScanning) ...[
            Container(
              height: scannerHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF667EEA)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: MobileScanner(
                  onDetect: (capture) {
                    final List<Barcode> barcodes = capture.barcodes;
                    for (final barcode in barcodes) {
                      if (barcode.rawValue != null) {
                        final raw = barcode.rawValue!;

                        // Use debug helper to log scan results
                        QRDebugHelper.logQRScanResult(raw);

                        // Try ticket QR first
                        final qrData = TicketModel.parseQRCodeData(raw);
                        if (qrData != null) {
                          final ticketCode = qrData['ticketCode'];
                          if (ticketCode != null) {
                            debugPrint('Processing ticket code: $ticketCode');
                            _processTicketCode(ticketCode);
                            return;
                          }
                        }

                        // Then try user badge QR
                        final userId = UserBadgeModel.parseBadgeQr(raw);
                        if (userId != null) {
                          debugPrint('Processing user badge: $userId');
                          _processUserBadge(userId);
                          return;
                        }

                        // Try event QR code format as fallback
                        if (raw.contains('orgami_app_code_')) {
                          final eventCode = raw.split('orgami_app_code_').last;
                          if (eventCode == widget.eventId) {
                            ShowToast().showNormalToast(
                              msg:
                                  'This is an event QR code, not a ticket QR code.',
                            );
                            return;
                          }
                        }

                        ShowToast().showNormalToast(
                          msg: 'Invalid QR code format for ticket scanning',
                        );
                      }
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _toggleScanning,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Stop Scanning',
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
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _toggleScanning,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF667EEA),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
                label: const Text(
                  'Start QR Scanner',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    fontFamily: 'Roboto',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // NFC Badge Scanner Section
            if (isNFCAvailable) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isNFCScanning
                        ? const Color(0xFF667EEA)
                        : const Color(0xFFE5E7EB),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.nfc,
                          color: isNFCScanning
                              ? const Color(0xFF667EEA)
                              : const Color(0xFF6B7280),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'NFC Badge Activation',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isNFCScanning
                                ? const Color(0xFF667EEA)
                                : const Color(0xFF374151),
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isNFCScanning
                          ? nfcStatus
                          : 'Tap to activate tickets via NFC badge',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                        fontFamily: 'Roboto',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isLoading ? null : _startNFCScanning,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isNFCScanning
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF667EEA),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: Icon(
                          isNFCScanning ? Icons.stop : Icons.nfc,
                          size: 18,
                        ),
                        label: Text(
                          isNFCScanning ? 'Stop NFC Scan' : 'Start NFC Scan',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            const Text(
              'Or enter ticket code manually:',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF6B7280),
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Manual Entry Section
          TextField(
            controller: _ticketCodeController,
            decoration: InputDecoration(
              labelText: 'Ticket Code',
              hintText: 'Enter ticket code',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.confirmation_number),
              suffixIcon: IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Clipboard.getData('text/plain').then((data) {
                    if (data?.text != null) {
                      _ticketCodeController.text = data!.text!;
                    }
                  });
                },
                icon: const Icon(Icons.paste),
              ),
            ),
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(
              fontSize: 16,
              fontFamily: 'Roboto',
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: isLoading || _ticketCodeController.text.trim().isEmpty
                  ? null
                  : _scanTicket,
              style: ElevatedButton.styleFrom(
                backgroundColor: _ticketCodeController.text.trim().isEmpty
                    ? const Color(0xFFE5E7EB)
                    : const Color(0xFFFF9800),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Colors.white, size: 24),
                        SizedBox(width: 12),
                        Text(
                          'Validate Ticket',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            fontFamily: 'Roboto',
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

  Widget _buildTicketInfo() {
    if (scannedTicket == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
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
                  color: scannedTicket!.isUsed
                      ? const Color(0xFFEF4444).withAlpha(25)
                      : const Color(0xFF667EEA).withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  scannedTicket!.isUsed
                      ? Icons.check_circle
                      : Icons.confirmation_number,
                  color: scannedTicket!.isUsed
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF667EEA),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                scannedTicket!.isUsed ? 'Ticket Used' : 'Valid Ticket',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: scannedTicket!.isUsed
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF667EEA),
                  fontFamily: 'Roboto',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow('Customer', scannedTicket!.customerName),
          _buildInfoRow('Ticket Code', scannedTicket!.ticketCode),
          _buildInfoRow(
            'Issued Date',
            DateFormat('MMM dd, yyyy').format(scannedTicket!.issuedDateTime),
          ),
          if (scannedTicket!.isUsed) ...[
            _buildInfoRow(
              'Used Date',
              DateFormat('MMM dd, yyyy').format(scannedTicket!.usedDateTime!),
            ),
            _buildInfoRow('Used By', scannedTicket!.usedBy ?? 'Unknown'),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
                fontFamily: 'Roboto',
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF1A1A1A),
                fontFamily: 'Roboto',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
