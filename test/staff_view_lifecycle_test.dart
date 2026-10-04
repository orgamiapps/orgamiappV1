import 'dart:async';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/models/event_feedback_model.dart';
import 'package:attendus/models/ticket_model.dart';
import 'package:attendus/screens/Events/event_feedback_management_screen.dart';
import 'package:attendus/screens/Events/ticket_scanner_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/auth_fakes.dart';

EventModel event() => EventModel(
  id: 'event',
  groupName: '',
  title: 'Event',
  description: '',
  location: '',
  customerUid: 'a',
  imageUrl: '',
  selectedDateTime: DateTime(2027),
  eventGenerateTime: DateTime(2026),
  status: 'scheduled',
  private: false,
  getLocation: false,
  radius: 0,
  latitude: 0,
  longitude: 0,
);

void main() {
  test(
    'feedback analytics accepts Firestore string rating keys and writes string keys',
    () {
      final analytics = EventFeedbackAnalytics.fromFirestore({
        'ratingDistribution': {'1': 2, '5': 7},
      });
      expect(analytics.ratingDistribution, {1: 2, 5: 7});
      expect(analytics.toFirestore()['ratingDistribution'], {'1': 2, '5': 7});
    },
  );
  testWidgets('late feedback results do not appear after account switch', (
    tester,
  ) async {
    final auth = TestFirebaseAuth()..changeUser(TestAuthUser('a'));
    final pending = Completer<List<EventFeedbackModel>>();
    var analyticsReads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EventFeedbackManagementScreen(
          eventModel: event(),
          auth: auth,
          loadFeedback: () => pending.future,
          loadAnalytics: () async {
            analyticsReads++;
            return null;
          },
        ),
      ),
    );
    auth.changeUser(TestAuthUser('b'));
    pending.complete([
      EventFeedbackModel(
        id: 'feedback',
        eventId: 'event',
        rating: 5,
        comment: 'Private staff comment',
        timestamp: DateTime(2026),
        isAnonymous: true,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.textContaining('Your account changed'), findsOneWidget);
    expect(find.text('Private staff comment'), findsNothing);
    expect(analyticsReads, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await auth.changes.close();
  });
  testWidgets(
    'feedback failure has retry instead of a success-looking empty state',
    (tester) async {
      final auth = TestFirebaseAuth()..changeUser(TestAuthUser('a'));
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: EventFeedbackManagementScreen(
            eventModel: event(),
            auth: auth,
            loadFeedback: () async {
              if (++attempts == 1) throw StateError('offline');
              return [];
            },
            loadAnalytics: () async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Could not load feedback. Please retry.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('No feedback available yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.changes.close();
    },
  );
  testWidgets(
    'pending staff ticket lookup cannot open results for another account',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = TestFirebaseAuth()..changeUser(TestAuthUser('a'));
      final pending = Completer<TicketModel?>();
      await tester.pumpWidget(
        MaterialApp(
          home: TicketScannerScreen(
            eventId: 'event',
            eventTitle: 'Event',
            auth: auth,
            lookupTicket: (_) => pending.future,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'CODE');
      await tester.ensureVisible(find.text('Validate Ticket'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Validate Ticket'));
      await tester.pump();
      auth.changeUser(TestAuthUser('b'));
      pending.complete(
        TicketModel(
          id: 'ticket',
          eventId: 'event',
          eventTitle: 'Event',
          eventImageUrl: '',
          eventLocation: '',
          eventDateTime: DateTime(2027),
          customerUid: 'attendee',
          customerName: 'Private Attendee',
          ticketCode: 'CODE',
          issuedDateTime: DateTime(2026),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Your account changed'), findsOneWidget);
      expect(find.text('Private Attendee'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.changes.close();
    },
  );
}
