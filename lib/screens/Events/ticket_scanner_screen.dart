import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orgami/firebase/firebase_firestore_helper.dart';
import 'package:orgami/models/ticket_model.dart';
import 'package:orgami/models/attendance_model.dart';
import 'package:orgami/Utils/toast.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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
  bool isLoading = false;
  TicketModel? scannedTicket;
  bool isScanning = false;

  @override
  void initState() {
    super.initState();
    _ticketCodeController.addListener(_onTicketCodeChanged);
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
          ShowToast().showNormalToast(msg: 'Invalid ticket code');
        } else if (ticket.eventId != widget.eventId) {
          ShowToast().showNormalToast(
            msg: 'This ticket is for a different event',
          );
        } else if (ticket.isUsed) {
          ShowToast().showNormalToast(msg: 'This ticket has already been used');
        } else {
          _showTicketValidationDialog(ticket);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ShowToast().showNormalToast(msg: 'Error scanning ticket: $e');
      }
    }
  }

  void _showTicketValidationDialog(TicketModel ticket) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Validate Ticket',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Roboto',
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
              backgroundColor: const Color(0xFF10B981),
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

        final message = existingAttendance == null
            ? 'Ticket validated and attendee signed in successfully!'
            : 'Ticket validated successfully!';
        ShowToast().showNormalToast(msg: message);

        _ticketCodeController.clear();
        setState(() {
          scannedTicket = null;
        });

        // Return to previous screen with success result
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ShowToast().showNormalToast(msg: 'Failed to validate ticket: $e');
      }
    }
  }

  void _toggleScanning() {
    setState(() {
      isScanning = !isScanning;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
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
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildEventInfo(),
            const SizedBox(height: 24),
            _buildScannerSection(),
            const SizedBox(height: 24),
            if (scannedTicket != null) _buildTicketInfo(),
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
              height: 300,
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
                        final qrData = TicketModel.parseQRCodeData(
                          barcode.rawValue!,
                        );
                        if (qrData != null) {
                          final ticketCode = qrData['ticketCode'];
                          if (ticketCode != null) {
                            _processTicketCode(ticketCode);
                          }
                        } else {
                          ShowToast().showNormalToast(
                            msg: 'Invalid QR code format',
                          );
                        }
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
            const SizedBox(height: 20),
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
                      : const Color(0xFF10B981).withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  scannedTicket!.isUsed
                      ? Icons.check_circle
                      : Icons.confirmation_number,
                  color: scannedTicket!.isUsed
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF10B981),
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
                      : const Color(0xFF10B981),
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
