import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:ndef_record/ndef_record.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io' show Platform;
import '../firebase/firebase_firestore_helper.dart';
import '../models/ticket_model.dart';
import '../models/badge_model.dart';

/// Service for handling NFC badge activation functionality
/// Enables event organizers to activate tickets by tapping user badges
class NFCBadgeService {
  static final NFCBadgeService _instance = NFCBadgeService._internal();
  factory NFCBadgeService() => _instance;
  NFCBadgeService._internal();

  final FirebaseFirestoreHelper _firestore = FirebaseFirestoreHelper();

  /// Check if NFC is available on the device
  Future<bool> isNFCAvailable() async {
    try {
      final availability = await NfcManager.instance.checkAvailability();
      // Check if NFC is available (returns NfcAvailability enum)
      return availability.toString() == 'NfcAvailability.available';
    } catch (e) {
      debugPrint('Error checking NFC availability: $e');
      return false;
    }
  }

  /// Start NFC session for reading badge data
  /// This is used by event organizers to activate tickets
  Future<NFCBadgeReadResult> startNFCBadgeReading({
    required String eventId,
    required String organizerUid,
    required Function(String) onStatusUpdate,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      // Check if NFC is available
      final isAvailable = await isNFCAvailable();
      if (!isAvailable) {
        return NFCBadgeReadResult.error('NFC is not available on this device');
      }

      onStatusUpdate('Ready to scan badge. Hold phone near user\'s badge...');

      // Start NFC session with timeout
      final completer = Completer<NFCBadgeReadResult>();
      Timer? timeoutTimer;

      // Set up timeout
      timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          NfcManager.instance.stopSession(errorMessageIos: 'Scan timeout');
          completer.complete(
            NFCBadgeReadResult.error('Scan timeout. Please try again.'),
          );
        }
      });

      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
        onDiscovered: (NfcTag tag) async {
          try {
            timeoutTimer?.cancel();
            onStatusUpdate('Badge detected, processing...');

            // Process the NFC tag to extract badge data
            final result = await _processNFCTag(tag, eventId, organizerUid);

            if (!completer.isCompleted) {
              completer.complete(result);
            }

            // Stop NFC session with appropriate message
            if (result.isSuccess) {
              await NfcManager.instance.stopSession(
                alertMessageIos: 'Ticket activated successfully!',
              );
            } else {
              await NfcManager.instance.stopSession(
                errorMessageIos: result.error ?? 'Failed to activate ticket',
              );
            }
          } catch (e) {
            debugPrint('Error processing NFC tag: $e');
            if (!completer.isCompleted) {
              completer.complete(
                NFCBadgeReadResult.error('Error processing badge: $e'),
              );
            }
            await NfcManager.instance.stopSession(
              errorMessageIos: 'Error processing badge',
            );
          }
        },
      );

      return await completer.future;
    } catch (e) {
      debugPrint('Error starting NFC session: $e');
      return NFCBadgeReadResult.error('Failed to start NFC scanning: $e');
    }
  }

  /// Process NFC tag to extract badge data and validate ticket
  Future<NFCBadgeReadResult> _processNFCTag(
    NfcTag tag,
    String eventId,
    String organizerUid,
  ) async {
    try {
      // Try to read NDEF records first (platform-specific)
      if (Platform.isAndroid) {
        final ndef = NdefAndroid.from(tag);
        if (ndef != null) {
          final ndefMessage = await ndef.getNdefMessage();
          if (ndefMessage != null && ndefMessage.records.isNotEmpty) {
            final result = await _processNDEFRecords(
              ndefMessage.records,
              eventId,
              organizerUid,
            );
            if (result.isSuccess) {
              return result;
            }
          }
        }
      }

      // If NDEF fails, try to get UID and create badge data from it
      final uid = _extractTagUID(tag);
      if (uid != null) {
        return await _processBadgeUID(uid, eventId, organizerUid);
      }

      return NFCBadgeReadResult.error('Could not read badge data from NFC tag');
    } catch (e) {
      debugPrint('Error processing NFC tag: $e');
      return NFCBadgeReadResult.error('Error reading badge: $e');
    }
  }

  /// Process NDEF records to find badge data
  Future<NFCBadgeReadResult> _processNDEFRecords(
    List<NdefRecord> records,
    String eventId,
    String organizerUid,
  ) async {
    for (final record in records) {
      try {
        // Check if this is a text record with badge data
        if (record.typeNameFormat == TypeNameFormat.wellKnown &&
            record.type.isNotEmpty) {
          final payload = record.payload;
          if (payload.isEmpty) continue;

          // Try to decode as text record
          if (record.type.first == 0x54) {
            // 'T' for text record
            final text = _decodeTextRecord(payload);
            if (text != null) {
              // Check if this looks like badge data
              final userId = UserBadgeModel.parseBadgeQr(text);
              if (userId != null) {
                return await _validateAndActivateTicket(
                  userId,
                  eventId,
                  organizerUid,
                );
              }
            }
          }

          // Try to decode as URI record
          if (record.type.first == 0x55) {
            // 'U' for URI record
            final uri = _decodeUriRecord(payload);
            if (uri != null) {
              final userId = UserBadgeModel.parseBadgeQr(uri);
              if (userId != null) {
                return await _validateAndActivateTicket(
                  userId,
                  eventId,
                  organizerUid,
                );
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error processing NDEF record: $e');
        continue;
      }
    }

    return NFCBadgeReadResult.error('No valid badge data found in NFC tag');
  }

  /// Process badge using UID when NDEF is not available
  Future<NFCBadgeReadResult> _processBadgeUID(
    String uid,
    String eventId,
    String organizerUid,
  ) async {
    try {
      // In a real implementation, you might have a mapping of UIDs to user IDs
      // For now, we'll create a badge identifier from the UID
      final badgeId = 'nfc_$uid';

      // Try to find user by badge UID in Firestore
      // This would require storing NFC UIDs in user badge documents
      final userId = await _findUserByBadgeUID(badgeId);
      if (userId != null) {
        return await _validateAndActivateTicket(userId, eventId, organizerUid);
      }

      return NFCBadgeReadResult.error('Badge not registered in system');
    } catch (e) {
      debugPrint('Error processing badge UID: $e');
      return NFCBadgeReadResult.error('Error processing badge UID: $e');
    }
  }

  /// Extract UID from NFC tag
  String? _extractTagUID(NfcTag tag) {
    try {
      if (Platform.isAndroid) {
        // Get the tag identifier directly from the Android tag
        final androidTag = NfcTagAndroid.from(tag);
        if (androidTag != null) {
          return androidTag.id
              .map((e) => e.toRadixString(16).padLeft(2, '0'))
              .join();
        }
      }

      return null;
    } catch (e) {
      debugPrint('Error extracting tag UID: $e');
      return null;
    }
  }

  /// Decode text record from NDEF payload
  String? _decodeTextRecord(Uint8List payload) {
    try {
      if (payload.isEmpty) return null;

      final statusByte = payload[0];
      final languageCodeLength = statusByte & 0x3F;

      if (payload.length <= 1 + languageCodeLength) return null;

      final textBytes = payload.sublist(1 + languageCodeLength);
      return utf8.decode(textBytes);
    } catch (e) {
      debugPrint('Error decoding text record: $e');
      return null;
    }
  }

  /// Create text record payload for NDEF writing
  Uint8List _createTextRecordPayload(String text, String languageCode) {
    final languageCodeBytes = utf8.encode(languageCode);
    final textBytes = utf8.encode(text);
    final statusByte = languageCodeBytes.length;

    final payload = Uint8List(1 + languageCodeBytes.length + textBytes.length);
    payload[0] = statusByte;
    payload.setRange(1, 1 + languageCodeBytes.length, languageCodeBytes);
    payload.setRange(1 + languageCodeBytes.length, payload.length, textBytes);

    return payload;
  }

  /// Decode URI record from NDEF payload
  String? _decodeUriRecord(Uint8List payload) {
    try {
      if (payload.isEmpty) return null;

      final identifierCode = payload[0];
      final uriBytes = payload.sublist(1);

      // URI identifier prefixes (simplified)
      const prefixes = [
        '',
        'http://www.',
        'https://www.',
        'http://',
        'https://',
        'tel:',
        'mailto:',
        'ftp://anonymous:anonymous@',
        'ftp://ftp.',
        'ftps://',
        'sftp://',
        'smb://',
        'nfs://',
        'ftp://',
        'dav://',
        'news:',
        'telnet://',
        'imap:',
        'rtsp://',
        'urn:',
        'pop:',
        'sip:',
        'sips:',
        'tftp:',
        'btspp://',
        'btl2cap://',
        'btgoep://',
        'tcpobex://',
        'irdaobex://',
        'file://',
        'urn:epc:id:',
        'urn:epc:tag:',
        'urn:epc:pat:',
        'urn:epc:raw:',
        'urn:epc:',
        'urn:nfc:',
      ];

      String prefix = '';
      if (identifierCode < prefixes.length) {
        prefix = prefixes[identifierCode];
      }

      return prefix + utf8.decode(uriBytes);
    } catch (e) {
      debugPrint('Error decoding URI record: $e');
      return null;
    }
  }

  /// Find user by badge UID (this would need to be implemented based on your data structure)
  Future<String?> _findUserByBadgeUID(String badgeUID) async {
    try {
      // This is a placeholder - you would need to implement badge UID storage
      // in your user badge documents and query by it
      debugPrint('Looking for user with badge UID: $badgeUID');
      return null;
    } catch (e) {
      debugPrint('Error finding user by badge UID: $e');
      return null;
    }
  }

  /// Validate and activate ticket for the user
  Future<NFCBadgeReadResult> _validateAndActivateTicket(
    String userId,
    String eventId,
    String organizerUid,
  ) async {
    try {
      // Get user's active ticket for this event
      final ticket = await _firestore.getActiveTicketForUserAndEvent(
        customerUid: userId,
        eventId: eventId,
      );

      if (ticket == null) {
        return NFCBadgeReadResult.error(
          'No valid ticket found for this user and event',
        );
      }

      if (ticket.isUsed) {
        final usedDate = ticket.usedDateTime != null
            ? ticket.usedDateTime!.toLocal().toString().split('.')[0]
            : 'Unknown time';
        return NFCBadgeReadResult.error(
          'Ticket already activated on $usedDate',
        );
      }

      // Activate the ticket
      await _firestore.useTicket(ticketId: ticket.id, usedBy: organizerUid);

      return NFCBadgeReadResult.success(
        ticket: ticket,
        message: 'Ticket activated successfully for ${ticket.customerName}',
      );
    } catch (e) {
      debugPrint('Error validating and activating ticket: $e');
      return NFCBadgeReadResult.error('Error activating ticket: $e');
    }
  }

  /// Stop any active NFC session
  Future<void> stopNFCSession({String? message}) async {
    try {
      await NfcManager.instance.stopSession(
        alertMessageIos: message ?? 'NFC session stopped',
      );
    } catch (e) {
      debugPrint('Error stopping NFC session: $e');
    }
  }

  /// Write badge data to NFC tag (for setting up user badges)
  /// This could be used in the future to write badge data to physical NFC tags
  Future<bool> writeBadgeToNFC(UserBadgeModel badge) async {
    try {
      final isAvailable = await isNFCAvailable();
      if (!isAvailable) {
        return false;
      }

      final completer = Completer<bool>();

      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
        onDiscovered: (NfcTag tag) async {
          try {
            if (Platform.isAndroid) {
              final ndef = NdefAndroid.from(tag);
              if (ndef == null || !ndef.isWritable) {
                await NfcManager.instance.stopSession(
                  errorMessageIos: 'Tag is not writable',
                );
                completer.complete(false);
                return;
              }

              // Create NDEF message with badge data
              final textRecord = NdefRecord(
                typeNameFormat: TypeNameFormat.wellKnown,
                type: Uint8List.fromList([0x54]), // 'T' for text record
                identifier: Uint8List(0),
                payload: _createTextRecordPayload(badge.badgeQrData, 'en'),
              );
              final ndefMessage = NdefMessage(records: [textRecord]);

              await ndef.writeNdefMessage(ndefMessage);
              await NfcManager.instance.stopSession(
                alertMessageIos: 'Badge data written successfully!',
              );
              completer.complete(true);
            } else {
              completer.complete(false);
            }
          } catch (e) {
            debugPrint('Error writing to NFC tag: $e');
            await NfcManager.instance.stopSession(
              errorMessageIos: 'Failed to write badge data',
            );
            completer.complete(false);
          }
        },
      );

      return await completer.future;
    } catch (e) {
      debugPrint('Error writing badge to NFC: $e');
      return false;
    }
  }
}

/// Result class for NFC badge reading operations
class NFCBadgeReadResult {
  final bool isSuccess;
  final String? error;
  final TicketModel? ticket;
  final String? message;

  NFCBadgeReadResult._({
    required this.isSuccess,
    this.error,
    this.ticket,
    this.message,
  });

  factory NFCBadgeReadResult.success({
    required TicketModel ticket,
    String? message,
  }) {
    return NFCBadgeReadResult._(
      isSuccess: true,
      ticket: ticket,
      message: message,
    );
  }

  factory NFCBadgeReadResult.error(String error) {
    return NFCBadgeReadResult._(isSuccess: false, error: error);
  }
}
