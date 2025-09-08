import 'package:flutter/foundation.dart';
import 'package:attendus/models/ticket_model.dart';
import 'package:attendus/models/badge_model.dart';

class QRDebugHelper {
  static void logQRScanResult(String qrData) {
    if (kDebugMode) {
      debugPrint('=== QR Code Scan Debug ===');
      debugPrint('Raw QR Data: $qrData');
      debugPrint('Data Length: ${qrData.length}');
      
      // Test different QR formats
      _testEventQRFormat(qrData);
      _testTicketQRFormat(qrData);
      _testBadgeQRFormat(qrData);
      
      debugPrint('=== End QR Debug ===');
    }
  }
  
  static void _testEventQRFormat(String qrData) {
    if (qrData.contains('orgami_app_code_')) {
      final eventCode = qrData.split('orgami_app_code_').last;
      debugPrint('✅ Event QR Format Detected');
      debugPrint('   Event Code: $eventCode');
    } else {
      debugPrint('❌ Not Event QR Format');
    }
  }
  
  static void _testTicketQRFormat(String qrData) {
    final ticketData = TicketModel.parseQRCodeData(qrData);
    if (ticketData != null) {
      debugPrint('✅ Ticket QR Format Detected');
      debugPrint('   Ticket ID: ${ticketData['ticketId']}');
      debugPrint('   Event ID: ${ticketData['eventId']}');
      debugPrint('   Ticket Code: ${ticketData['ticketCode']}');
    } else {
      debugPrint('❌ Not Ticket QR Format');
    }
  }
  
  static void _testBadgeQRFormat(String qrData) {
    final userId = UserBadgeModel.parseBadgeQr(qrData);
    if (userId != null) {
      debugPrint('✅ Badge QR Format Detected');
      debugPrint('   User ID: $userId');
    } else {
      debugPrint('❌ Not Badge QR Format');
    }
  }
  
  static String generateTestEventQR(String eventId) {
    return 'orgami_app_code_$eventId';
  }
  
  static String generateTestTicketQR(String ticketId, String eventId, String ticketCode) {
    return 'orgami_ticket_${ticketId}_${eventId}_$ticketCode';
  }
  
  static String generateTestBadgeQR(String userId) {
    return 'attendus_user_$userId';
  }
  
  static void logCameraPermissionStatus(bool hasPermission) {
    if (kDebugMode) {
      debugPrint('=== Camera Permission Debug ===');
      debugPrint('Has Camera Permission: $hasPermission');
      debugPrint('=== End Permission Debug ===');
    }
  }
  
  static void logScannerInitialization(bool success, String? error) {
    if (kDebugMode) {
      debugPrint('=== Scanner Initialization Debug ===');
      debugPrint('Initialization Success: $success');
      if (error != null) {
        debugPrint('Error: $error');
      }
      debugPrint('=== End Scanner Debug ===');
    }
  }
}