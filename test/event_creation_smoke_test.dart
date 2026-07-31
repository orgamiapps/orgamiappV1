import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/screens/Events/create_event_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('create event form shell renders', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AttendUsTheme.light, home: const CreateEventScreen()),
    );

    expect(find.text('Create event'), findsWidgets);
    expect(find.text('Hosting as'), findsOneWidget);
    expect(find.text('Event title'), findsOneWidget);
    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Starts'), findsOneWidget);
    expect(find.text('Ends'), findsOneWidget);
    expect(find.text('In person'), findsOneWidget);
    expect(find.text('Select'), findsOneWidget);
    expect(find.text('More options'), findsOneWidget);
  });

  testWidgets('advanced event options stay collapsed until requested', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AttendUsTheme.light, home: const CreateEventScreen()),
    );

    expect(find.text('Description (optional)'), findsNothing);
    await tester.ensureVisible(find.text('More options'));
    await tester.tap(find.text('More options'));
    await tester.pumpAndSettle();

    expect(find.text('Description (optional)'), findsOneWidget);
    expect(find.text('Regular'), findsOneWidget);
    expect(find.text('Attendee questions'), findsOneWidget);
  });

  testWidgets('in-person quick create requires title and a selected pin', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AttendUsTheme.light, home: const CreateEventScreen()),
    );

    await tester.tap(find.text('Create event').last);
    await tester.pump();

    expect(find.text('Enter an event title'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).first,
      'Community meetup',
    );
    await tester.tap(find.text('Create event').last);
    await tester.pump();

    expect(
      find.text('Select a venue, address, or map pin for this event'),
      findsOneWidget,
    );
  });

  testWidgets('online events require a meeting location instead of a pin', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AttendUsTheme.light, home: const CreateEventScreen()),
    );

    await tester.ensureVisible(find.text('Online'));
    await tester.tap(find.text('Online'));
    await tester.pump();
    expect(find.text('Online location or meeting link'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).first,
      'Remote community meetup',
    );
    await tester.tap(find.text('Create event').last);
    await tester.pump();

    expect(
      find.text('Enter the online event location or meeting link'),
      findsWidgets,
    );
    expect(
      find.text('Select a venue, address, or map pin for this event'),
      findsNothing,
    );
  });

  testWidgets('event date and time pickers open and select values', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AttendUsTheme.light, home: const CreateEventScreen()),
    );

    final dateField = find.text('Date');
    await tester.ensureVisible(dateField);
    await tester.tap(dateField);
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(find.text('Choose event date'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final startTimeField = find.text('Starts');
    await tester.ensureVisible(startTimeField);
    await tester.tap(startTimeField);
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(find.text('Choose start time'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Select'));
    await tester.pumpAndSettle();

    expect(find.text('Starts'), findsOneWidget);
    expect(find.text('Ends'), findsOneWidget);
  });
}
