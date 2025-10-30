import 'package:firebase_auth/firebase_auth.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/Utils/logger.dart';

/// Result object containing user identity information
class UserIdentityResult {
  final String userId;
  final String userName;
  final UserIdentitySource source;
  final bool isGuest;

  UserIdentityResult({
    required this.userId,
    required this.userName,
    required this.source,
    this.isGuest = false,
  });

  @override
  String toString() {
    return 'UserIdentityResult(userId: $userId, userName: $userName, source: ${source.name}, isGuest: $isGuest)';
  }
}

/// Source of user identity information
enum UserIdentitySource { customerController, firebaseAuth, guest }

/// Service for consistent user identity resolution across facial recognition components
class UserIdentityService {
  static final UserIdentityService _instance = UserIdentityService._internal();
  factory UserIdentityService() => _instance;
  UserIdentityService._internal();

  /// Get the current user identity with fallback logic
  /// Priority order:
  /// 1. Guest user (if provided)
  /// 2. CustomerController (if available)
  /// 3. Firebase Auth (fallback)
  static Future<UserIdentityResult?> getCurrentUserIdentity({
    String? guestUserId,
    String? guestUserName,
  }) async {
    try {
      // Priority 1: Guest user if provided
      if (guestUserId != null) {
        Logger.info(
          'UserIdentityService: Using guest identity - $guestUserName (ID: $guestUserId)',
        );
        return UserIdentityResult(
          userId: guestUserId,
          userName: guestUserName ?? 'Guest User',
          source: UserIdentitySource.guest,
          isGuest: true,
        );
      }

      // Priority 2: CustomerController (preferred for logged-in users)
      final customerControllerUser = CustomerController.logeInCustomer;
      if (customerControllerUser != null) {
        Logger.info(
          'UserIdentityService: Using CustomerController identity - ${customerControllerUser.name} (ID: ${customerControllerUser.uid})',
        );
        return UserIdentityResult(
          userId: customerControllerUser.uid,
          userName: customerControllerUser.name.isNotEmpty
              ? customerControllerUser.name
              : customerControllerUser.email.split('@')[0],
          source: UserIdentitySource.customerController,
          isGuest: false,
        );
      }

      // Priority 3: Firebase Auth fallback
      Logger.warning(
        'UserIdentityService: CustomerController.logeInCustomer is null, checking Firebase Auth...',
      );
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        final userName =
            firebaseUser.displayName ??
            firebaseUser.email?.split('@')[0] ??
            'User';
        Logger.success(
          'UserIdentityService: Using Firebase Auth identity - $userName (ID: ${firebaseUser.uid})',
        );
        return UserIdentityResult(
          userId: firebaseUser.uid,
          userName: userName,
          source: UserIdentitySource.firebaseAuth,
          isGuest: false,
        );
      }

      // No user identity available
      Logger.error(
        'UserIdentityService: No user identity available - user not logged in',
      );
      return null;
    } catch (e) {
      Logger.error('UserIdentityService: Error resolving user identity: $e');
      return null;
    }
  }

  /// Verify that user identities match (for debugging enrollment/scanner mismatches)
  static bool verifyIdentityMatch(
    UserIdentityResult? identity1,
    UserIdentityResult? identity2,
  ) {
    if (identity1 == null || identity2 == null) return false;

    final matches = identity1.userId == identity2.userId;
    if (!matches) {
      Logger.warning('UserIdentityService: Identity mismatch detected!');
      Logger.warning('  Identity 1: ${identity1.toString()}');
      Logger.warning('  Identity 2: ${identity2.toString()}');
    }
    return matches;
  }

  /// Get a display-friendly description of the identity source
  static String getSourceDescription(UserIdentitySource source) {
    switch (source) {
      case UserIdentitySource.customerController:
        return 'User Profile';
      case UserIdentitySource.firebaseAuth:
        return 'Authentication Service';
      case UserIdentitySource.guest:
        return 'Guest Mode';
    }
  }

  /// Log detailed identity information for debugging
  static void logIdentityDetails(UserIdentityResult identity, String context) {
    Logger.debug('===== User Identity Details ($context) =====');
    Logger.debug('User ID: ${identity.userId}');
    Logger.debug('User Name: ${identity.userName}');
    Logger.debug(
      'Source: ${getSourceDescription(identity.source)} (${identity.source.name})',
    );
    Logger.debug('Is Guest: ${identity.isGuest}');
    Logger.debug('=========================================');
  }

  /// Generate enrollment document ID consistently
  static String generateEnrollmentDocumentId(String eventId, String userId) {
    return '$eventId-$userId';
  }

  /// Parse enrollment document ID to extract components
  static Map<String, String>? parseEnrollmentDocumentId(String documentId) {
    try {
      final parts = documentId.split('-');
      if (parts.length < 2) return null;

      // Find the last hyphen to split eventId and userId
      final lastHyphenIndex = documentId.lastIndexOf('-');
      if (lastHyphenIndex == -1) return null;

      return {
        'eventId': documentId.substring(0, lastHyphenIndex),
        'userId': documentId.substring(lastHyphenIndex + 1),
      };
    } catch (e) {
      Logger.error(
        'UserIdentityService: Error parsing enrollment document ID: $e',
      );
      return null;
    }
  }
}
