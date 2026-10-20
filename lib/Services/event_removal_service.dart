import 'dart:async';

import 'package:attendus/Services/event_lifecycle_store.dart';
import 'package:attendus/Services/discovery_marketplace_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

typedef EventRemovalCall =
    Future<Map<String, dynamic>> Function(
      String name,
      Map<String, dynamic> arguments,
    );

enum EventRemovalStatus { deleted, cancelled }

class EventRemovalResult {
  const EventRemovalResult({
    required this.status,
    required this.affectedEventIds,
  });

  final EventRemovalStatus status;
  final List<String> affectedEventIds;
  String get message => status == EventRemovalStatus.deleted
      ? 'Event deleted'
      : 'Event cancelled';

  factory EventRemovalResult.fromJson(Map<String, dynamic> data) {
    final status = switch (data['status']) {
      'deleted' => EventRemovalStatus.deleted,
      'cancelled' => EventRemovalStatus.cancelled,
      _ => throw const FormatException('Invalid event removal result'),
    };
    final ids = (data['affectedEventIds'] as List?)
        ?.whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids == null || ids.isEmpty) {
      throw const FormatException('Missing affected events');
    }
    return EventRemovalResult(status: status, affectedEventIds: ids);
  }
}

class EventRemovalEligibility {
  const EventRemovalEligibility({
    required this.canDelete,
    required this.eventRevision,
  });
  final bool canDelete;
  final int eventRevision;
}

class EventCancellationPreview {
  const EventCancellationPreview({
    required this.token,
    required this.registrationCount,
  });
  final String token;
  final int registrationCount;
}

/// Keeps operation identity stable across a lost response and publishes
/// authoritative changes before callers close their dialog or event routes.
class EventRemovalService {
  EventRemovalService({
    EventRemovalCall? call,
    void Function(EventRemovalResult)? publish,
    String? Function()? currentUserId,
    int Function()? sessionGeneration,
    this.timeout = const Duration(seconds: 30),
  }) : _call = call ?? _firebaseCall,
       _publish = publish ?? _publishToStore,
       _sessionGeneration =
           sessionGeneration ??
           (() => EventLifecycleStore.instance.sessionGeneration),
       _currentUserId =
           currentUserId ?? (() => FirebaseAuth.instance.currentUser?.uid);

  final EventRemovalCall _call;
  final void Function(EventRemovalResult) _publish;
  final String? Function() _currentUserId;
  final int Function() _sessionGeneration;
  final Map<String, ({String uid, int generation})> _requestActors = {};
  final Map<String, ({String uid, int generation})> _eligibilityActors = {};
  final Duration timeout;

  static String newRequestId() => const Uuid().v4();

  static Future<Map<String, dynamic>> _firebaseCall(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable(name)
        .call(arguments);
    return Map<String, dynamic>.from(result.data as Map);
  }

  static void _publishToStore(EventRemovalResult result) {
    EventLifecycleStore.instance.applyConfirmed(
      eventIds: result.affectedEventIds,
      status: result.status == EventRemovalStatus.deleted
          ? EventLifecycleStatus.deleted
          : EventLifecycleStatus.cancelled,
    );
    unawaited(DiscoveryMarketplaceService.invalidateCachedHome());
  }

  Future<EventRemovalEligibility> eligibility(String eventId) async {
    final actor = _actor();
    final data = await _call('getEventCapabilitiesV1', {
      'eventId': eventId,
      'includeRemovalEligibility': true,
    }).timeout(timeout);
    _checkActor(actor);
    _eligibilityActors[eventId] = actor;
    final eligibility = data['removalEligibility'];
    if (eligibility is! Map ||
        eligibility['canDelete'] is! bool ||
        eligibility['eventRevision'] is! num) {
      throw FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'You no longer have permission to remove this event.',
      );
    }
    return EventRemovalEligibility(
      canDelete: eligibility['canDelete'] as bool,
      eventRevision: (eligibility['eventRevision'] as num).toInt(),
    );
  }

  Future<EventCancellationPreview> preview(
    String eventId,
    String recurrenceScope,
  ) async {
    final actor = _actor();
    _checkActor(_eligibilityActors[eventId] ?? actor);
    final data = await _call('previewEventCancellationV1', {
      'eventId': eventId,
      'recurrenceScope': recurrenceScope,
    }).timeout(const Duration(seconds: 120));
    _checkActor(actor);
    return EventCancellationPreview(
      token: data['previewToken'] as String,
      registrationCount: (data['count'] as num?)?.toInt() ?? 0,
    );
  }

  Future<EventRemovalResult> delete({
    required String eventId,
    required int expectedEventRevision,
    required String requestId,
  }) => _mutate('deleteEmptyEventV1', {
    'eventId': eventId,
    'expectedEventRevision': expectedEventRevision,
    'requestId': requestId,
  });

  Future<EventRemovalResult> cancel({
    required String eventId,
    required int expectedEventRevision,
    required String requestId,
    required String previewToken,
    required String reason,
  }) => _mutate('cancelEventV1', {
    'eventId': eventId,
    'expectedEventRevision': expectedEventRevision,
    'requestId': requestId,
    'previewToken': previewToken,
    'reason': reason,
  });

  Future<EventRemovalResult> _mutate(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final actor = _requestActors.putIfAbsent(
      arguments['requestId'] as String,
      _actor,
    );
    _checkActor(actor);
    _checkActor(_eligibilityActors[arguments['eventId']] ?? actor);
    Map<String, dynamic> data;
    try {
      data = await _call(name, arguments).timeout(timeout);
    } catch (error) {
      _checkActor(actor);
      if (!isUncertain(error)) rethrow;
      // Deletion receipts and cancellation preview tokens make this retry safe.
      data = await _call(name, arguments).timeout(timeout);
    }
    _checkActor(actor);
    final result = EventRemovalResult.fromJson(data);
    _publish(result);
    return result;
  }

  ({String uid, int generation}) _actor() {
    final actor = _currentUserId();
    if (actor == null) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Sign in again to manage this event.',
      );
    }
    return (uid: actor, generation: _sessionGeneration());
  }

  void _checkActor(({String uid, int generation}) actor) {
    if (_currentUserId() != actor.uid ||
        _sessionGeneration() != actor.generation) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Your account changed. Reopen this event to continue.',
      );
    }
  }

  static bool isUncertain(Object error) =>
      error is TimeoutException ||
      error is FormatException ||
      error is FirebaseFunctionsException &&
          const [
            'unavailable',
            'deadline-exceeded',
            'internal',
            'unknown',
          ].contains(error.code);
}
