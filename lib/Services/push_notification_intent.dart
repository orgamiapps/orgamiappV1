enum PushDestination { event, community, conversation, discovery }

class PushNotificationIntent {
  const PushNotificationIntent(this.destination, this.id);

  final PushDestination destination;
  final String id;

  static bool belongsTo(Map<String, dynamic> data, String? uid) {
    final recipient = data['recipientUid'];
    return recipient == null || (recipient is String && recipient == uid);
  }

  static PushNotificationIntent? parse(
    Map<String, dynamic> data, {
    String? currentUid,
  }) {
    if (currentUid != null && !belongsTo(data, currentUid)) return null;
    if (data['type'] == 'discovery_new_events' &&
        (data['eventId'] == null || data['eventId'] == '')) {
      return const PushNotificationIntent(PushDestination.discovery, '');
    }
    final (destination, value) = switch (data['type']) {
      'new_message' || 'message' || 'group_message' || 'message_mention' => (
        PushDestination.conversation,
        data['conversationId'],
      ),
      'org_update' => (PushDestination.community, data['organizationId']),
      'event_reminder' ||
      'event_changes' ||
      'event_update' ||
      'geofence_checkin' ||
      'new_event' ||
      'group_event' ||
      'discovery_new_events' ||
      'ticket_update' ||
      'organizer_feedback' ||
      'event_feedback' => (PushDestination.event, data['eventId']),
      _ => (null, null),
    };
    if (destination == null ||
        value is! String ||
        value.isEmpty ||
        value.length > 300 ||
        value.trim() != value ||
        value == '.' ||
        value == '..' ||
        value.contains('/') ||
        value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      return null;
    }
    return PushNotificationIntent(destination, value);
  }
}

/// Keeps delayed route work from opening in another account or superseding a
/// newer tap. Signed-out taps use the existing post-auth continuation store.
class PushIntentCoordinator {
  PushIntentCoordinator({
    required this.currentUid,
    required this.remember,
    required this.present,
  });
  final String? Function() currentUid;
  final Future<void> Function(PushNotificationIntent) remember;
  final Future<bool> Function(PushNotificationIntent, bool Function()) present;
  int _epoch = 0;

  void invalidate() => _epoch++;

  Future<void> handle(Map<String, dynamic> payload) async {
    final uid = currentUid();
    final intent = PushNotificationIntent.parse(payload, currentUid: uid);
    if (intent == null) return;
    final epoch = ++_epoch;
    bool stillCurrent() => _epoch == epoch && currentUid() == uid;
    if (uid == null) {
      await remember(intent);
      return;
    }
    final opened = await present(intent, stillCurrent);
    if (!opened && stillCurrent()) await remember(intent);
  }
}
