import 'package:attendus/Services/event_removal_service.dart';
import 'package:cloud_functions/cloud_functions.dart';

class EventBulkRemovalResult {
  const EventBulkRemovalResult({
    required this.deletedIds,
    required this.keptErrors,
    required this.unconfirmedIds,
    required this.unattemptedIds,
    this.accountChanged = false,
  });

  final List<String> deletedIds;
  final Map<String, Object> keptErrors;
  final List<String> unconfirmedIds;
  final List<String> unattemptedIds;
  final bool accountChanged;

  String get summary {
    final parts = [
      '${deletedIds.length} event${deletedIds.length == 1 ? '' : 's'} deleted.',
      if (keptErrors.isNotEmpty)
        '${keptErrors.length} event${keptErrors.length == 1 ? '' : 's'} could not be deleted and need${keptErrors.length == 1 ? 's' : ''} review.',
      if (unconfirmedIds.isNotEmpty)
        '${unconfirmedIds.length} deletion${unconfirmedIds.length == 1 ? ' is' : 's are'} unconfirmed. Retry to check the same request safely.',
      if (unattemptedIds.isNotEmpty)
        '${unattemptedIds.length} event${unattemptedIds.length == 1 ? ' was' : 's were'} not attempted.',
    ];
    return parts.join(' ');
  }
}

/// Coordinates individual receipt-backed deletions. A transport failure can
/// mean the server committed, so it stops the batch without claiming rollback.
class EventBulkRemovalService {
  const EventBulkRemovalService({required this.deleteEvent});

  final Future<void> Function(String eventId) deleteEvent;

  Future<EventBulkRemovalResult> remove({
    required Iterable<String> eventIds,
    required bool Function() isCurrentAccount,
    void Function(String eventId)? onDeleted,
  }) async {
    final pending = eventIds.toSet().toList();
    final deleted = <String>[];
    final kept = <String, Object>{};
    final unconfirmed = <String>[];
    var accountChanged = false;
    while (pending.isNotEmpty) {
      if (!isCurrentAccount()) {
        accountChanged = true;
        break;
      }
      final eventId = pending.removeAt(0);
      try {
        await deleteEvent(eventId);
        if (!isCurrentAccount()) {
          accountChanged = true;
          break;
        }
        deleted.add(eventId);
        onDeleted?.call(eventId);
      } catch (error) {
        if (!isCurrentAccount()) {
          accountChanged = true;
          break;
        }
        final definiteFailure =
            error is FirebaseFunctionsException &&
            !EventRemovalService.isUncertain(error) &&
            const [
              'aborted',
              'failed-precondition',
              'permission-denied',
              'unauthenticated',
              'invalid-argument',
              'not-found',
            ].contains(error.code);
        if (definiteFailure) {
          kept[eventId] = error;
          continue;
        }
        unconfirmed.add(eventId);
        break;
      }
    }
    return EventBulkRemovalResult(
      deletedIds: List.unmodifiable(deleted),
      keptErrors: Map.unmodifiable(kept),
      unconfirmedIds: List.unmodifiable(unconfirmed),
      unattemptedIds: List.unmodifiable(pending),
      accountChanged: accountChanged,
    );
  }
}
