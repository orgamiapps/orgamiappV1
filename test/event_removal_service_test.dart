import 'dart:async';

import 'package:attendus/Services/event_availability_service.dart';
import 'package:attendus/Services/event_removal_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'missing callable and callable security failure do not imply removed or private',
    () async {
      for (final code in ['not-found', 'permission-denied']) {
        expect(
          await resolveDeniedEventRead(
            'event',
            checkCapabilities: (_) async {
              throw FirebaseFunctionsException(
                code: code,
                message: 'Request failed',
              );
            },
          ),
          DeniedEventRead.connectionError,
        );
      }
    },
  );

  test(
    'preflight cannot authorize mutation after account session changes',
    () async {
      var generation = 1;
      var calls = 0;
      final service = EventRemovalService(
        currentUserId: () => 'owner',
        sessionGeneration: () => generation,
        publish: (_) => fail('Stale authorization must not publish'),
        call: (_, args) async {
          calls++;
          return {
            'removalEligibility': {'canDelete': true, 'eventRevision': 7},
          };
        },
      );
      await service.eligibility('event');
      generation++;
      await expectLater(
        service.delete(
          eventId: 'event',
          expectedEventRevision: 7,
          requestId: 'stable-request',
        ),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      expect(calls, 1);
    },
  );

  test(
    'eligibility is explicitly requested and uses current server revision',
    () async {
      final service = EventRemovalService(
        currentUserId: () => 'owner',
        call: (name, args) async {
          expect(name, 'getEventCapabilitiesV1');
          expect(args, {'eventId': 'event', 'includeRemovalEligibility': true});
          return {
            'removalEligibility': {'canDelete': false, 'eventRevision': 9},
          };
        },
      );
      final result = await service.eligibility('event');
      expect(result.canDelete, false);
      expect(result.eventRevision, 9);
    },
  );

  test(
    'lost delete response retries identical request then publishes before return',
    () async {
      final requests = <Map<String, dynamic>>[];
      final published = <EventRemovalResult>[];
      final service = EventRemovalService(
        currentUserId: () => 'owner',
        publish: published.add,
        call: (name, args) async {
          expect(name, 'deleteEmptyEventV1');
          requests.add(Map.of(args));
          if (requests.length == 1) throw TimeoutException('response lost');
          return {
            'status': 'deleted',
            'affectedEventIds': ['event'],
          };
        },
      );
      final result = await service.delete(
        eventId: 'event',
        expectedEventRevision: 4,
        requestId: 'stable-request',
      );
      expect(requests, hasLength(2));
      expect(requests[0], requests[1]);
      expect(requests[1]['requestId'], 'stable-request');
      expect(published, [result]);
      expect(result.message, 'Event deleted');
    },
  );

  test(
    'cancellation publishes every recurrence and safely reuses preview',
    () async {
      final requests = <Map<String, dynamic>>[];
      final published = <EventRemovalResult>[];
      final service = EventRemovalService(
        currentUserId: () => 'owner',
        publish: published.add,
        call: (name, args) async {
          requests.add(Map.of(args));
          if (requests.length == 1) {
            throw FirebaseFunctionsException(
              code: 'unavailable',
              message: 'unavailable',
            );
          }
          return {
            'status': 'cancelled',
            'affectedEventIds': ['a', 'b', 'c'],
          };
        },
      );
      final result = await service.cancel(
        eventId: 'a',
        expectedEventRevision: 2,
        requestId: 'cancel-request',
        previewToken: 'review-token',
        reason: 'Weather',
      );
      expect(requests[0], requests[1]);
      expect(result.affectedEventIds, ['a', 'b', 'c']);
      expect(published.single.status, EventRemovalStatus.cancelled);
    },
  );

  test('business conflict never retries or publishes', () async {
    var calls = 0;
    final service = EventRemovalService(
      currentUserId: () => 'owner',
      publish: (_) => fail('Must not publish failed mutation'),
      call: (_, args) async {
        calls++;
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'failed-precondition',
        );
      },
    );
    await expectLater(
      service.delete(
        eventId: 'event',
        expectedEventRevision: 1,
        requestId: 'stable-request',
      ),
      throwsA(isA<FirebaseFunctionsException>()),
    );
    expect(calls, 1);
  });

  test('account switch prevents retry under another actor', () async {
    var actor = 'owner';
    var calls = 0;
    final service = EventRemovalService(
      currentUserId: () => actor,
      publish: (_) =>
          fail('Previous account must not change new account state'),
      call: (_, args) async {
        calls++;
        actor = 'other';
        throw TimeoutException('response lost');
      },
    );
    await expectLater(
      service.delete(
        eventId: 'event',
        expectedEventRevision: 1,
        requestId: 'stable-request',
      ),
      throwsA(
        isA<FirebaseFunctionsException>().having(
          (e) => e.code,
          'code',
          'unauthenticated',
        ),
      ),
    );
    expect(calls, 1);
  });

  test(
    'account switch after success prevents publication to new account',
    () async {
      var actor = 'owner';
      final service = EventRemovalService(
        currentUserId: () => actor,
        publish: (_) =>
            fail('Previous account must not change new account state'),
        call: (_, args) async {
          actor = 'other';
          return {
            'status': 'deleted',
            'affectedEventIds': ['event'],
          };
        },
      );
      await expectLater(
        service.delete(
          eventId: 'event',
          expectedEventRevision: 1,
          requestId: 'stable-request',
        ),
        throwsA(isA<FirebaseFunctionsException>()),
      );
    },
  );

  test(
    'malformed success cannot report or publish successful removal',
    () async {
      final service = EventRemovalService(
        currentUserId: () => 'owner',
        publish: (_) => fail('No authoritative event IDs'),
        call: (_, args) async => {'status': 'cancelled'},
      );
      await expectLater(
        service.delete(
          eventId: 'event',
          expectedEventRevision: 1,
          requestId: 'stable-request',
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'denied missing document resolves unavailable, never access request',
    () async {
      final result = await resolveDeniedEventRead(
        'missing',
        checkCapabilities: (_) async {
          throw FirebaseFunctionsException(
            code: 'not-found',
            message: 'Event not found.',
          );
        },
      );
      expect(result, DeniedEventRead.notFound);
    },
  );

  test(
    'existing denied document remains restricted; network errors offer retry',
    () async {
      expect(
        await resolveDeniedEventRead(
          'private',
          checkCapabilities: (_) async {},
        ),
        DeniedEventRead.restricted,
      );
      expect(
        await resolveDeniedEventRead(
          'private',
          checkCapabilities: (_) async {
            throw FirebaseFunctionsException(
              code: 'unavailable',
              message: 'unavailable',
            );
          },
        ),
        DeniedEventRead.connectionError,
      );
    },
  );
}
