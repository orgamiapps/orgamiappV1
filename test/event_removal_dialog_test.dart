import 'dart:async';

import 'package:attendus/Services/event_removal_service.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/Events/Widget/delete_event_dialogue.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

EventModel fixture({String? seriesId}) => EventModel.fromJson({
  'id': 'event',
  'title': 'Community breakfast',
  'groupName': '',
  'description': '',
  'location': '',
  'imageUrl': '',
  'customerUid': 'owner',
  'status': 'active',
  'private': false,
  'selectedDateTime': '2030-01-01T12:00:00Z',
  'eventGenerateTime': '2026-01-01T00:00:00Z',
  'seriesId': seriesId,
});

Future<void> openDialog(
  WidgetTester tester,
  EventRemovalService service, {
  String? seriesId,
  void Function(EventRemovalResult?)? onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                final result = await showDialog<EventRemovalResult>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => DeleteEventDialoge(
                    singleEvent: fixture(seriesId: seriesId),
                    service: service,
                  ),
                );
                onResult?.call(result);
              },
              child: const Text('Open removal'),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open removal'));
  await tester.pumpAndSettle();
}

Finder action(String text) => find.widgetWithText(FilledButton, text);

void main() {
  testWidgets(
    'empty event has one named confirmation; busy blocks duplicate and back',
    (tester) async {
      final reply = Completer<Map<String, dynamic>>();
      var mutations = 0;
      var published = false;
      EventRemovalResult? completed;
      final service = EventRemovalService(
        currentUserId: () => 'owner',
        publish: (_) => published = true,
        call: (name, args) async {
          if (name == 'getEventCapabilitiesV1') {
            return {
              'removalEligibility': {'canDelete': true, 'eventRevision': 5},
            };
          }
          mutations++;
          expect(args['expectedEventRevision'], 5);
          return reply.future;
        },
      );
      await openDialog(
        tester,
        service,
        onResult: (result) {
          expect(published, true);
          completed = result;
        },
      );
      expect(find.text('Community breakfast'), findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(action('Delete event'));
      await tester.pump();
      expect(action('Deleting event…'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(action('Deleting event…')).onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(DeleteEventDialoge), findsOneWidget);
      expect(mutations, 1);
      reply.complete({
        'status': 'deleted',
        'affectedEventIds': ['event'],
      });
      await tester.pumpAndSettle();
      expect(find.byType(DeleteEventDialoge), findsNothing);
      expect(completed?.status, EventRemovalStatus.deleted);
    },
  );

  testWidgets(
    'populated event offers cancellation preview with no nonrecurring scope',
    (tester) async {
      var cancelled = false;
      final service = EventRemovalService(
        currentUserId: () => 'owner',
        publish: (_) {},
        call: (name, args) async {
          if (name == 'getEventCapabilitiesV1') {
            return {
              'removalEligibility': {'canDelete': false, 'eventRevision': 5},
            };
          }
          if (name == 'previewEventCancellationV1') {
            expect(args['recurrenceScope'], 'this_occurrence');
            return {'previewToken': 'preview', 'count': 3};
          }
          expect(name, 'cancelEventV1');
          expect(args['previewToken'], 'preview');
          expect(args['reason'], 'Bad weather');
          cancelled = true;
          return {
            'status': 'cancelled',
            'affectedEventIds': ['event'],
          };
        },
      );
      await openDialog(tester, service);
      expect(find.textContaining('Cancel it to preserve'), findsOneWidget);
      expect(action('Delete event'), findsNothing);
      expect(find.byType(DropdownButton<String>), findsNothing);
      await tester.enterText(find.byType(TextField), 'Bad weather');
      await tester.tap(action('Review affected attendees'));
      await tester.pumpAndSettle();
      expect(find.textContaining('3 active registrations'), findsOneWidget);
      await tester.tap(action('Cancel event'));
      await tester.pumpAndSettle();
      expect(cancelled, true);
    },
  );

  testWidgets(
    'registration arriving after confirmation switches to cancellation review',
    (tester) async {
      var preflights = 0;
      final service = EventRemovalService(
        currentUserId: () => 'owner',
        publish: (_) {},
        call: (name, args) async {
          if (name == 'getEventCapabilitiesV1') {
            preflights++;
            return {
              'removalEligibility': {
                'canDelete': preflights == 1,
                'eventRevision': preflights,
              },
            };
          }
          throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'failed-precondition',
          );
        },
      );
      await openDialog(tester, service);
      await tester.tap(action('Delete event'));
      await tester.pumpAndSettle();
      expect(preflights, 2);
      expect(find.textContaining('The event changed.'), findsOneWidget);
      expect(action('Review affected attendees'), findsOneWidget);
      expect(action('Delete event'), findsNothing);
    },
  );

  testWidgets(
    'uncertain mutation locks inputs and reuses original request on manual retry',
    (tester) async {
      final ids = <String>[];
      final service = EventRemovalService(
        currentUserId: () => 'owner',
        publish: (_) {},
        call: (name, args) async {
          if (name == 'getEventCapabilitiesV1') {
            return {
              'removalEligibility': {'canDelete': true, 'eventRevision': 5},
            };
          }
          ids.add(args['requestId'] as String);
          if (ids.length <= 2) throw TimeoutException('lost');
          return {
            'status': 'deleted',
            'affectedEventIds': ['event'],
          };
        },
      );
      await openDialog(tester, service);
      await tester.tap(action('Delete event'));
      await tester.pumpAndSettle();
      expect(action('Retry same request'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Keep event'))
            .onPressed,
        isNull,
      );
      expect(find.text('Cancel instead'), findsNothing);
      await tester.tap(action('Retry same request'));
      await tester.pumpAndSettle();
      expect(ids, hasLength(3));
      expect(ids.toSet(), hasLength(1));
      expect(find.byType(DeleteEventDialoge), findsNothing);
    },
  );

  testWidgets('recurring cancellation exposes occurrence scope', (
    tester,
  ) async {
    final service = EventRemovalService(
      currentUserId: () => 'owner',
      publish: (_) {},
      call: (name, args) async => {
        'removalEligibility': {'canDelete': false, 'eventRevision': 2},
      },
    );
    await openDialog(tester, service, seriesId: 'weekly-breakfast');
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Entire series'), findsWidgets);
  });
}
