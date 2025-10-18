import 'package:flutter/foundation.dart';
// NFC functionality temporarily disabled due to plugin registration issues
// import 'package:nfc_manager/nfc_manager.dart';
// import 'package:nfc_manager/nfc_manager_android.dart';
// import 'package:ndef_record/ndef_record.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io' show Platform;
import '../firebase/firebase_firestore_helper.dart';
import '../models/ticket_model.dart';
import '../models/badge_model.dart';

/// Service for handling NFC badge activation functionality
/// Enables event organizers to activate tickets by tapping user badges
/// TEMPORARILY DISABLED due to plugin registration issues
class NFCBadgeService {
  static final NFCBadgeService _instance = NFCBadgeService._internal();
  factory NFCBadgeService() => _instance;
  NFCBadgeService._internal();

  final FirebaseFirestoreHelper _firestore = FirebaseFirestoreHelper();

  /// Check if NFC is available on the device
  /// Temporarily disabled due to plugin registration issues
  Future<bool> isNFCAvailable() async {
    try {
      debugPrint('NFC functionality temporarily disabled');
      return false; // Always return false until plugin issues are resolved
    } catch (e) {
      debugPrint('Error checking NFC availability: $e');
      return false;
    }
  }

  /// Start NFC session for reading badge data
  /// This is used by event organizers to activate tickets
  /// Temporarily disabled due to plugin registration issues
  Future<NFCBadgeReadResult> startNFCBadgeReading({
    required String eventId,
    required String organizerUid,
    required Function(String) onStatusUpdate,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      // NFC functionality temporarily disabled
      onStatusUpdate('NFC functionality is temporarily disabled. Please use QR codes instead.');
      return NFCBadgeReadResult.error('NFC functionality temporarily disabled due to plugin issues. Please use QR code scanning instead.');
    } catch (e) {
      debugPrint('Error in NFC service: $e');
      return NFCBadgeReadResult.error('NFC functionality disabled: $e');
    }
  }

  /// Stop NFC session - temporarily disabled
  Future<void> stopNFCSession() async {
    try {
      debugPrint('NFC stop session requested but NFC is disabled');
    } catch (e) {
      debugPrint('Error stopping NFC session: $e');
    }
  }

  /// Write badge to NFC - temporarily disabled
  Future<NFCBadgeWriteResult> writeBadgeToNFC() async {
    return NFCBadgeWriteResult.error('NFC functionality temporarily disabled');
  }
}

// Result classes for NFC operations
class NFCBadgeReadResult {
  final bool isSuccess;
  final String? ticketId;
  final String? userId;
  final String? error;

  NFCBadgeReadResult._({
    required this.isSuccess,
    this.ticketId,
    this.userId,
    this.error,
  });

  factory NFCBadgeReadResult.success({
    required String ticketId,
    required String userId,
  }) {
    return NFCBadgeReadResult._(
      isSuccess: true,
      ticketId: ticketId,
      userId: userId,
    );
  }

  factory NFCBadgeReadResult.error(String error) {
    return NFCBadgeReadResult._(
      isSuccess: false,
      error: error,
    );
  }
}

class NFCBadgeWriteResult {
  final bool isSuccess;
  final String? error;

  NFCBadgeWriteResult._({
    required this.isSuccess,
    this.error,
  });

  factory NFCBadgeWriteResult.success() {
    return NFCBadgeWriteResult._(isSuccess: true);
  }

  factory NFCBadgeWriteResult.error(String error) {
    return NFCBadgeWriteResult._(
      isSuccess: false,
      error: error,
    );
  }
}