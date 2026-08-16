import 'package:attendus/Services/guest_mode_service.dart';
import 'package:attendus/widgets/attendus_design_system.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:attendus/Services/product_funnel_service.dart';

class GuestAttendanceService {
  GuestAttendanceService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _functions;

  Future<String?> promptForFullName(BuildContext context) async {
    final controller = TextEditingController(
      text: GuestModeService().guestDisplayName ?? '',
    );
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AttendUsDialog(
        title: 'Your name for check-in',
        message:
            'Enter the full name the event organizer should see on the attendance list.',
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: const Text('Continue'),
          ),
        ],
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AttendUsFormTextField(
                controller: controller,
                labelText: 'Full name',
                hintText: 'e.g., Jordan Lee',
                prefixIcon: Icons.person_outline,
                textCapitalization: TextCapitalization.words,
                validator: validateFullName,
              ),
              if (GuestModeService().guestDisplayName != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () async {
                      await GuestModeService().clearGuestDisplayName();
                      controller.clear();
                    },
                    child: const Text('Forget saved name'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  static String? validateFullName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Enter your full name.';
    if (name.length < 2 || name.length > 100) {
      return 'Use between 2 and 100 characters.';
    }
    if (!RegExp(
      r"^[\p{L}\p{M}][\p{L}\p{M}\s.'-]*$",
      unicode: true,
    ).hasMatch(name)) {
      return 'Use letters, spaces, apostrophes, periods, or hyphens.';
    }
    return null;
  }

  Future<String> submit({
    required String eventId,
    required String method,
    required String fullName,
    List<String> answers = const [],
    double? latitude,
    double? longitude,
    double? accuracyMeters,
  }) async {
    ProductFunnelService().record(
      'guest_checkin_started',
      dimensions: {'checkInMethod': method},
    );
    try {
      final result = await _functions
          .httpsCallable('submitGuestAttendance')
          .call({
            'eventId': eventId.trim(),
            'method': method,
            'fullName': fullName.trim(),
            'answers': answers,
            'latitude': ?latitude,
            'longitude': ?longitude,
            'accuracyMeters': ?accuracyMeters,
          });
      final data = Map<String, dynamic>.from(result.data as Map);
      final attendanceId = data['attendanceId']?.toString();
      if (attendanceId == null || attendanceId.isEmpty) {
        throw const GuestAttendanceException(
          'server-error',
          'Attendus could not confirm this check-in.',
        );
      }
      await GuestModeService().saveGuestDisplayName(fullName);
      ProductFunnelService().record(
        'guest_checkin_completed',
        dimensions: {'checkInMethod': method, 'result': 'success'},
      );
      return attendanceId;
    } on FirebaseFunctionsException catch (error) {
      ProductFunnelService().record(
        'guest_checkin_failed',
        dimensions: {
          'checkInMethod': method,
          'result': 'failure',
          'errorCategory': error.code,
        },
      );
      throw GuestAttendanceException(
        error.code,
        _friendlyMessage(error.code, error.message),
      );
    }
  }

  static String _friendlyMessage(
    String code,
    String? fallback,
  ) => switch (code) {
    'already-exists' => 'You are already checked in to this event.',
    'not-found' => 'That event code was not found.',
    'permission-denied' =>
      'This event or check-in method is not available to guests.',
    'failed-precondition' =>
      fallback ?? 'The check-in requirements were not met.',
    'resource-exhausted' =>
      'Too many attempts were made. Please wait a moment and try again.',
    'unavailable' =>
      'Check-in is temporarily unavailable. Check your connection and retry.',
    _ => fallback ?? 'Check-in could not be completed. Please try again.',
  };
}

class GuestAttendanceException implements Exception {
  final String code;
  final String message;
  const GuestAttendanceException(this.code, this.message);
  @override
  String toString() => message;
}
