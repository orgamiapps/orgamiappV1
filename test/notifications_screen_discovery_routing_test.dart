import 'dart:async';

import 'package:attendus/firebase/firebase_messaging_helper.dart';
import 'package:attendus/models/notification_model.dart';
import 'package:attendus/screens/Home/notifications_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Inbox extends Fake implements FirebaseMessagingHelper {
  _Inbox(this.notification);

  final NotificationModel notification;
  final readIds = <String>[];

  @override
  Future<NotificationPage> fetchUserNotificationsPage({
    DocumentSnapshot? startAfter,
    int pageSize = 20,
  }) async => NotificationPage(items: [notification], lastDoc: null);

  @override
  Future<void> markNotificationAsRead(String notificationId) async {
    readIds.add(notificationId);
  }
}

class _PendingInbox extends Fake implements FirebaseMessagingHelper {
  final first = Completer<NotificationPage>();
  final next = Completer<NotificationPage>();
  int pageCalls = 0;

  @override
  Future<NotificationPage> fetchUserNotificationsPage({
    DocumentSnapshot? startAfter,
    int pageSize = 20,
  }) => ++pageCalls == 1 ? first.future : next.future;
}

// Firestore has no public snapshot constructor; this double tests its parser boundary.
// ignore: subtype_of_sealed_class
class _Snapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.fields);

  final Map<String, dynamic> fields;

  @override
  String get id => 'owned-notification';

  @override
  Map<String, dynamic> data() => fields;
}

class _RetryInbox extends Fake implements FirebaseMessagingHelper {
  _RetryInbox(this.loads);
  final List<Future<NotificationPage> Function()> loads;
  int pageCalls = 0;

  @override
  Future<NotificationPage> fetchUserNotificationsPage({
    DocumentSnapshot? startAfter,
    int pageSize = 20,
  }) => loads[pageCalls++]();
}

NotificationPage _page(int start, int count) => NotificationPage(
  items: List.generate(
    count,
    (index) => NotificationModel(
      id: 'notification-${start + index}',
      title: 'Notice ${start + index}',
      body: 'Controlled inbox entry',
      type: 'general',
      createdAt: DateTime(2026, 10, 4),
    ),
  ),
  lastDoc: null,
);

Future<void> _showInbox(WidgetTester tester, FirebaseMessagingHelper inbox) =>
    tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          messagingHelper: inbox,
          notificationChanges: const Stream<QuerySnapshot>.empty(),
        ),
      ),
    );

Future<({List<String> events, _Inbox inbox})> tapNotification(
  WidgetTester tester, {
  String type = 'discovery_new_events',
  String? eventId,
  Map<String, dynamic>? storedFields,
}) async {
  final inbox = _Inbox(
    storedFields != null
        ? NotificationModel.fromFirestore(
            _Snapshot({
              'title': 'A new event for you',
              'body': 'Controlled inbox entry',
              'createdAt': Timestamp.fromDate(DateTime(2026, 10, 4)),
              ...storedFields,
            }),
          )
        : NotificationModel(
            id: 'owned-notification',
            title: 'A new event for you',
            body: 'Controlled inbox entry',
            type: type,
            eventId: eventId,
            createdAt: DateTime(2026, 10, 4),
          ),
  );
  final events = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      routes: {
        '/app/discover': (_) => const Scaffold(body: Text('Explicit Discover')),
      },
      home: NotificationsScreen(
        messagingHelper: inbox,
        notificationChanges: const Stream<QuerySnapshot>.empty(),
        openEvent: (id) async => events.add(id),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('A new event for you'));
  await tester.pumpAndSettle();
  expect(inbox.readIds, ['owned-notification']);
  return (events: events, inbox: inbox);
}

void main() {
  testWidgets('refresh invalidates an older next-page response', (
    tester,
  ) async {
    final pending = Completer<NotificationPage>();
    final inbox = _RetryInbox([
      () async => _page(0, 20),
      () => pending.future,
      () async => _page(100, 1),
    ]);
    await _showInbox(tester, inbox);
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(inbox.pageCalls, 2);
    position.jumpTo(0);
    await tester.pump();
    final refresh = tester
        .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
        .show();
    await tester.pumpAndSettle();
    await refresh;
    expect(find.text('Notice 100'), findsOneWidget);
    pending.complete(_page(20, 1));
    await tester.pumpAndSettle();
    expect(find.text('Notice 100'), findsOneWidget);
    expect(find.text('Notice 20'), findsNothing);
    expect(inbox.pageCalls, 3);
  });

  testWidgets(
    'a failed realtime stream preserves notices and retries only on request',
    (tester) async {
      var subscriptions = 0;
      final changes = StreamController<QuerySnapshot>.broadcast(
        onListen: () => subscriptions++,
      );
      addTearDown(changes.close);
      final inbox = _RetryInbox([() async => _page(0, 1)]);
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsScreen(
            messagingHelper: inbox,
            notificationChanges: changes.stream,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(subscriptions, 1);
      changes.addError(StateError('permission-denied'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Live updates unavailable.'), findsOneWidget);
      expect(find.text('Notice 0'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(subscriptions, 1);
      await tester.tap(find.text('Retry live updates'));
      await tester.pump();
      expect(subscriptions, 2);
      expect(inbox.pageCalls, 1);
      expect(find.text('Live updates unavailable.'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      changes.addError(StateError('late error'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(subscriptions, 2);
    },
  );

  testWidgets('initial inbox read failure shows a working read-only retry', (
    tester,
  ) async {
    final inbox = _RetryInbox([
      () => Future.error(StateError('permission-denied')),
      () async => _page(0, 1),
    ]);
    await _showInbox(tester, inbox);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Notifications unavailable'), findsOneWidget);
    expect(find.text('All caught up'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(inbox.pageCalls, 2);
    expect(find.text('Notice 0'), findsOneWidget);
  });

  testWidgets(
    'next-page read failure preserves loaded notices and retries only the read',
    (tester) async {
      final inbox = _RetryInbox([
        () async => _page(0, 20),
        () => Future.error(StateError('unavailable')),
        () async => _page(20, 1),
      ]);
      await _showInbox(tester, inbox);
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(inbox.pageCalls, 2);
      expect(
        find.text('More notifications could not be loaded.'),
        findsOneWidget,
      );
      position.jumpTo(0);
      await tester.pump();
      expect(find.text('Notice 0'), findsOneWidget);
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      expect(inbox.pageCalls, 2);
      await tester.ensureVisible(find.widgetWithText(TextButton, 'Retry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(inbox.pageCalls, 3);
      expect(find.text('Notice 20'), findsOneWidget);
      expect(
        find.text('More notifications could not be loaded.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'a hanging initial read times out and its late result cannot replace a retry',
    (tester) async {
      final pending = Completer<NotificationPage>();
      final inbox = _RetryInbox([
        () => pending.future,
        () async => _page(2, 1),
      ]);
      await _showInbox(tester, inbox);
      await tester.pump(const Duration(seconds: 21));
      expect(find.text('Notifications unavailable'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Notice 2'), findsOneWidget);
      pending.complete(_page(1, 1));
      await tester.pump();
      expect(find.text('Notice 2'), findsOneWidget);
      expect(find.text('Notice 1'), findsNothing);
    },
  );

  testWidgets('leaving the inbox while its initial page loads is safe', (
    tester,
  ) async {
    final inbox = _PendingInbox();
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          messagingHelper: inbox,
          notificationChanges: const Stream<QuerySnapshot>.empty(),
        ),
      ),
    );
    expect(inbox.pageCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    inbox.first.complete(NotificationPage(items: const [], lastDoc: null));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving the inbox while the next page loads is safe', (
    tester,
  ) async {
    final inbox = _PendingInbox();
    inbox.first.complete(
      NotificationPage(
        items: List.generate(
          20,
          (index) => NotificationModel(
            id: 'notification-$index',
            title: 'Notice $index',
            body: 'Controlled inbox entry',
            type: 'general',
            createdAt: DateTime(2026, 10, 4),
          ),
        ),
        lastDoc: null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          messagingHelper: inbox,
          notificationChanges: const Stream<QuerySnapshot>.empty(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(inbox.pageCalls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    inbox.next.complete(NotificationPage(items: const [], lastDoc: null));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single discovery inbox tap opens its event', (tester) async {
    final result = await tapNotification(tester, eventId: 'owned-event');
    expect(result.events, ['owned-event']);
    expect(find.text('Explicit Discover'), findsNothing);
  });

  testWidgets('an admin stored payload opens its nested event from the inbox', (
    tester,
  ) async {
    final result = await tapNotification(
      tester,
      storedFields: {
        'type': 'event_reminder',
        'data': {'eventId': 'owned-event'},
      },
    );
    expect(result.events, ['owned-event']);
  });

  for (final fields in <Map<String, dynamic>>[
    {'eventId': 42},
    {'eventId': 'a/b'},
    {
      'data': {'eventId': 42},
    },
  ]) {
    testWidgets(
      'a malformed stored discovery ID cannot become a batch: $fields',
      (tester) async {
        final result = await tapNotification(
          tester,
          storedFields: {'type': 'discovery_new_events', ...fields},
        );
        expect(result.events, isEmpty);
        expect(find.text('Explicit Discover'), findsNothing);
        expect(find.text('Notifications'), findsOneWidget);
      },
    );
  }

  for (final eventId in <String?>[null, '']) {
    testWidgets(
      'a stored discovery batch with eventId=$eventId opens Discover',
      (tester) async {
        final result = await tapNotification(
          tester,
          storedFields: {'type': 'discovery_new_events', 'eventId': eventId},
        );
        expect(result.events, isEmpty);
        expect(find.text('Explicit Discover'), findsOneWidget);
      },
    );
  }

  for (final eventId in <String?>[null, '']) {
    testWidgets('a discovery batch with eventId=$eventId opens Discover', (
      tester,
    ) async {
      final result = await tapNotification(tester, eventId: eventId);
      expect(result.events, isEmpty);
      expect(find.text('Explicit Discover'), findsOneWidget);
      expect(
        ModalRoute.of(
          tester.element(find.text('Explicit Discover')),
        )?.settings.name,
        '/app/discover',
      );
    });
  }

  for (final eventId in ['a/b', ' padded ', 'a\n', 'x' * 301]) {
    testWidgets('a malformed discovery event ID does not navigate: $eventId', (
      tester,
    ) async {
      final result = await tapNotification(tester, eventId: eventId);
      expect(result.events, isEmpty);
      expect(find.text('Explicit Discover'), findsNothing);
      expect(find.text('Notifications'), findsOneWidget);
    });
  }

  for (final type in [
    'event_reminder',
    'event_changes',
    'event_update',
    'event_feedback',
    'geofence_checkin',
    'group_event',
    'new_event',
    'ticket_update',
  ]) {
    testWidgets('existing $type inbox taps still open the event', (
      tester,
    ) async {
      final result = await tapNotification(
        tester,
        type: type,
        eventId: 'owned-event',
      );
      expect(result.events, ['owned-event']);
      expect(find.text('Explicit Discover'), findsNothing);
    });
  }
}
