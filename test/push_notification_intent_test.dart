import 'dart:async';

import 'package:attendus/Services/push_notification_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'event, organization and conversation pushes resolve real destinations',
    () {
      for (final type in [
        'event_reminder',
        'event_changes',
        'ticket_update',
        'organizer_feedback',
        'event_feedback',
        'geofence_checkin',
        'new_event',
      ]) {
        final intent = PushNotificationIntent.parse({
          'type': type,
          'eventId': 'event',
        });
        expect(intent?.destination, PushDestination.event);
        expect(intent?.id, 'event');
      }
      expect(
        PushNotificationIntent.parse({
          'type': 'org_update',
          'organizationId': 'group',
        })?.destination,
        PushDestination.community,
      );
      expect(
        PushNotificationIntent.parse({
          'type': 'group_message',
          'conversationId': 'chat',
        })?.destination,
        PushDestination.conversation,
      );
    },
  );

  test('malformed IDs and a different signed-in recipient fail closed', () {
    for (final value in [null, '', 12, 'a/b', ' padded ', 'a\n']) {
      expect(
        PushNotificationIntent.parse({
          'type': 'event_reminder',
          'eventId': value,
        }),
        isNull,
      );
    }
    expect(
      PushNotificationIntent.parse({
        'type': 'event_reminder',
        'eventId': 'event',
        'recipientUid': 'a',
      }, currentUid: 'b'),
      isNull,
    );
    expect(
      PushNotificationIntent.parse({'type': 'unsupported', 'eventId': 'event'}),
      isNull,
    );
    expect(
      PushNotificationIntent.belongsTo({'recipientUid': 'a'}, null),
      false,
    );
  });

  test(
    'Discovery batches open home while a single event keeps its context',
    () {
      final single = PushNotificationIntent.parse({
        'type': 'discovery_new_events',
        'eventId': 'event-1',
      });
      expect(single?.destination, PushDestination.event);
      expect(single?.id, 'event-1');
      for (final empty in ['', null]) {
        expect(
          PushNotificationIntent.parse({
            'type': 'discovery_new_events',
            'eventId': empty,
          })?.destination,
          PushDestination.discovery,
        );
      }
      for (final invalid in [42, 'a/b', ' padded ']) {
        expect(
          PushNotificationIntent.parse({
            'type': 'discovery_new_events',
            'eventId': invalid,
          }),
          isNull,
        );
      }
      expect(
        PushNotificationIntent.parse({
          'type': 'discovery_new_events',
          'eventId': '',
          'recipientUid': 'a',
        }, currentUid: 'b'),
        isNull,
      );
    },
  );

  test(
    'signed-out Discovery batch retains home continuation until authentication',
    () async {
      final remembered = <PushNotificationIntent>[];
      final coordinator = PushIntentCoordinator(
        currentUid: () => null,
        remember: (intent) async => remembered.add(intent),
        present: (_, _) async => throw StateError('must await login'),
      );
      await coordinator.handle({'type': 'discovery_new_events', 'eventId': ''});
      expect(remembered.single.destination, PushDestination.discovery);
    },
  );

  test(
    'signed-out notification keeps the existing post-auth continuation',
    () async {
      final remembered = <PushNotificationIntent>[];
      final coordinator = PushIntentCoordinator(
        currentUid: () => null,
        remember: (intent) async {
          remembered.add(intent);
        },
        present: (_, _) async => throw StateError('must await login'),
      );
      await coordinator.handle({
        'type': 'org_update',
        'organizationId': 'group',
        'recipientUid': 'a',
      });
      expect(remembered.single.id, 'group');
    },
  );

  test(
    'account switch invalidates a delayed route even if the same account returns',
    () async {
      String? uid = 'a';
      final barrier = Completer<void>();
      final remembered = <PushNotificationIntent>[];
      var opened = false;
      final coordinator = PushIntentCoordinator(
        currentUid: () => uid,
        remember: (intent) async {
          remembered.add(intent);
        },
        present: (_, current) async {
          await barrier.future;
          opened = current();
          return opened;
        },
      );
      final pending = coordinator.handle({
        'type': 'event_reminder',
        'eventId': 'event',
      });
      uid = null;
      coordinator.invalidate();
      uid = 'a';
      barrier.complete();
      await pending;
      expect(opened, false);
      expect(remembered, isEmpty);
    },
  );

  test(
    'only the latest tap may open and absent navigator retains continuation',
    () async {
      final first = Completer<void>();
      final opened = <String>[];
      final remembered = <String>[];
      final coordinator = PushIntentCoordinator(
        currentUid: () => 'a',
        remember: (intent) async {
          remembered.add(intent.id);
        },
        present: (intent, current) async {
          if (intent.id == 'first') await first.future;
          if (intent.id == 'offline') return false;
          if (current()) opened.add(intent.id);
          return current();
        },
      );
      final pending = coordinator.handle({
        'type': 'event_reminder',
        'eventId': 'first',
      });
      await coordinator.handle({'type': 'event_reminder', 'eventId': 'second'});
      first.complete();
      await pending;
      await coordinator.handle({
        'type': 'org_update',
        'organizationId': 'offline',
      });
      expect(opened, ['second']);
      expect(remembered, ['offline']);
    },
  );
}
