import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/Utils/logger.dart';

/// Diagnostic utility to help debug My Profile screen event loading issues
class ProfileDiagnostics {
  static Future<void> runFullDiagnostics() async {
    await runDiagnostics();
    await testEventModelParsing();
  }

  static Future<void> runDiagnostics() async {
    if (CustomerController.logeInCustomer == null) {
      Logger.error('No logged in user found', null);
      return;
    }

    final userId = CustomerController.logeInCustomer!.uid;
    Logger.info('========================================');
    Logger.info('PROFILE DIAGNOSTICS');
    Logger.info('========================================');
    Logger.info('User ID: $userId');
    Logger.info('User Email: ${CustomerController.logeInCustomer!.email}');
    Logger.info('User Name: ${CustomerController.logeInCustomer!.name}');
    Logger.info('========================================');

    try {
      // Test created events query
      Logger.info('Testing created events query...');
      final startCreated = DateTime.now();
      final createdResult = await FirebaseFirestoreHelper()
          .getEventsCreatedByUser(userId);
      final createdEvents = createdResult['events'] as List;
      final createdDuration = DateTime.now().difference(startCreated);
      Logger.info(
        '✅ Created events: ${createdEvents.length} (${createdDuration.inMilliseconds}ms)',
      );
      if (createdEvents.isNotEmpty) {
        for (var event in createdEvents) {
          Logger.info('  - ${event.title} (ID: ${event.id})');
        }
      }

      // Test attended events query
      Logger.info('Testing attended events query...');
      final startAttended = DateTime.now();
      final attendedResult = await FirebaseFirestoreHelper()
          .getEventsAttendedByUser(userId);
      final attendedEvents = attendedResult['events'] as List;
      final attendedDuration = DateTime.now().difference(startAttended);
      Logger.info(
        '✅ Attended events: ${attendedEvents.length} (${attendedDuration.inMilliseconds}ms)',
      );
      if (attendedEvents.isNotEmpty) {
        for (var event in attendedEvents) {
          Logger.info('  - ${event.title} (ID: ${event.id})');
        }
      }

      // Test saved events query
      Logger.info('Testing saved events query...');
      final startSaved = DateTime.now();
      final savedResult = await FirebaseFirestoreHelper().getFavoritedEvents(
        userId: userId,
      );
      final savedEvents = savedResult['events'] as List;
      final savedDuration = DateTime.now().difference(startSaved);
      Logger.info(
        '✅ Saved events: ${savedEvents.length} (${savedDuration.inMilliseconds}ms)',
      );
      if (savedEvents.isNotEmpty) {
        for (var event in savedEvents) {
          Logger.info('  - ${event.title} (ID: ${event.id})');
        }
      }

      Logger.info('========================================');
      Logger.info('DIAGNOSTICS COMPLETE');
      Logger.info(
        'Total time: ${createdDuration.inMilliseconds + attendedDuration.inMilliseconds + savedDuration.inMilliseconds}ms',
      );
      Logger.info('========================================');
    } catch (e, stackTrace) {
      Logger.error('Diagnostics failed: $e', e);
      Logger.debug('Stack trace: $stackTrace');
    }
  }

  static Future<void> testEventModelParsing() async {
    Logger.info('========================================');
    Logger.info('EVENT MODEL PARSING TEST');
    Logger.info('========================================');

    try {
      // Test Firebase queries directly
      final userId = CustomerController.logeInCustomer!.uid;

      Logger.info('Testing EventModel parsing with new fixes...');

      // Test created events parsing
      final createdResult = await FirebaseFirestoreHelper()
          .getEventsCreatedByUser(userId, limit: 5);
      final createdEvents = createdResult['events'] as List;
      Logger.info(
        '✅ Created events parsed successfully: ${createdEvents.length}',
      );

      // Test attended events parsing
      final attendedResult = await FirebaseFirestoreHelper()
          .getEventsAttendedByUser(userId, limit: 5);
      final attendedEvents = attendedResult['events'] as List;
      Logger.info(
        '✅ Attended events parsed successfully: ${attendedEvents.length}',
      );

      // Test favorited events parsing
      final favoritedResult = await FirebaseFirestoreHelper()
          .getFavoritedEvents(userId: userId, limit: 5);
      final favoritedEvents = favoritedResult['events'] as List;
      Logger.info(
        '✅ Favorited events parsed successfully: ${favoritedEvents.length}',
      );

      Logger.info('========================================');
      Logger.info('ALL EVENT MODEL TESTS PASSED');
      Logger.info('========================================');
    } catch (e, stackTrace) {
      Logger.error('Event model parsing test failed: $e', e);
      Logger.debug('Stack trace: $stackTrace');
    }
  }
}
