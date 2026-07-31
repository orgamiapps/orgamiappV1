import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/widgets/attendus_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {ThemeData? theme}) {
  return MaterialApp(
    theme: theme ?? AttendUsTheme.light,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('page section, rows, and cards render in the light theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ListView(
          children: const [
            AttendUsPageSection(
              title: 'Operations',
              subtitle: 'Manage attendance workflows',
              icon: Icons.dashboard_outlined,
              child: AttendUsListTile(
                leadingIcon: Icons.event_outlined,
                title: 'Upcoming events',
                subtitle: '3 events need review',
              ),
            ),
            AttendUsGroupCard(
              name: 'Campus Ambassadors',
              description: 'Internal event team',
              memberCountLabel: '42 members',
              eventCountLabel: '8 events',
              statusLabel: 'Active',
            ),
            AttendUsUserRow(
              name: 'Alex Rivera',
              subtitle: 'Organizer',
              statusLabel: 'Owner',
            ),
            AttendUsNotificationRow(
              title: 'Ticket sale',
              message: 'A ticket was purchased',
              timeLabel: '2m ago',
              unread: true,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Operations'), findsOneWidget);
    expect(find.text('Upcoming events'), findsOneWidget);
    expect(find.text('Campus Ambassadors'), findsOneWidget);
    expect(find.text('Alex Rivera'), findsOneWidget);
    expect(find.text('Ticket sale'), findsOneWidget);
  });

  testWidgets('search field clears text and reports changes', (tester) async {
    final controller = TextEditingController();
    final changes = <String>[];

    await tester.pumpWidget(
      _wrap(
        Padding(
          padding: const EdgeInsets.all(16),
          child: AttendUsSearchField(
            controller: controller,
            hintText: 'Search events',
            onChanged: changes.add,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'conference');
    await tester.pump();
    expect(controller.text, 'conference');
    expect(find.byTooltip('Clear search'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(changes.last, isEmpty);
  });

  testWidgets('filter chip group reports selected values', (tester) async {
    Set<String> selected = {'upcoming'};

    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) {
            return AttendUsFilterChipGroup<String>(
              selectedValues: selected,
              onChanged: (next) => setState(() => selected = next),
              options: const [
                AttendUsFilterOption(value: 'upcoming', label: 'Upcoming'),
                AttendUsFilterOption(value: 'past', label: 'Past'),
              ],
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Past'));
    await tester.pump();
    expect(selected, {'past'});
  });

  testWidgets('avatar fallback and data table render in the dark theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ListView(
          children: [
            const AttendUsAvatar(name: 'Jordan Lee'),
            AttendUsDataTable(
              columns: const [
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Role')),
              ],
              rows: const [
                DataRow(
                  cells: [
                    DataCell(Text('Jordan Lee')),
                    DataCell(Text('Admin')),
                  ],
                ),
              ],
            ),
          ],
        ),
        theme: AttendUsTheme.dark,
      ),
    );

    expect(find.text('JL'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
  });

  testWidgets('event summary card constrains long event text', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SizedBox(
          width: 320,
          child: AttendUsEventSummaryCard(
            title:
                'Annual Community Operations Summit With A Very Long Event Name',
            subtitle:
                'A concise professional card should not overflow with long supporting copy.',
            dateLabel: 'Aug 12, 2026',
            locationLabel: 'Downtown Conference Center',
            statusLabel: 'Public',
          ),
        ),
      ),
    );

    expect(find.textContaining('Annual Community'), findsOneWidget);
    expect(find.text('Public'), findsOneWidget);
    expect(find.byIcon(Icons.event), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ticket pass card renders stable ticket information', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const SizedBox(
          width: 360,
          child: AttendUsTicketPassCard(
            eventTitle: 'Founder Demo Night',
            dateLabel: 'Sep 4, 2026',
            ticketLabel: 'Active ticket',
          ),
        ),
      ),
    );

    expect(find.text('Founder Demo Night'), findsOneWidget);
    expect(find.text('Active ticket'), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_2), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty and loading states render accessible copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const Column(
          children: [
            AttendUsEmptyState(
              icon: Icons.inbox_outlined,
              title: 'Nothing here yet',
              message: 'New items will appear here when they are available.',
            ),
            AttendUsLoadingState(label: 'Loading records...'),
          ],
        ),
      ),
    );

    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(
      find.text('New items will appear here when they are available.'),
      findsOneWidget,
    );
    expect(find.text('Loading records...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('camera overlay panel renders guided secure status', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const SizedBox(
          width: 360,
          child: AttendUsCameraOverlayPanel(
            icon: Icons.face,
            title: 'Face recognized',
            message: 'Keep your face centered while Attendus confirms access.',
            tone: AttendUsStatusTone.success,
          ),
        ),
      ),
    );

    expect(find.text('Face recognized'), findsOneWidget);
    expect(find.textContaining('Keep your face centered'), findsOneWidget);
    expect(find.byIcon(Icons.face), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('map control panel renders controls and primary action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AttendUsMapControlPanel(
          title: 'Check-in zone',
          subtitle: 'Set the allowed event radius.',
          controls: const [Text('Radius: 100 ft')],
          primaryAction: AttendUsButton.primary(
            label: 'Save Zone',
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(find.text('Check-in zone'), findsOneWidget);
    expect(find.text('Radius: 100 ft'), findsOneWidget);
    expect(find.text('Save Zone'), findsOneWidget);
  });

  testWidgets('quiz panel and action bar render dense host controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AttendUsQuizPanel(
          title: 'Live quiz host',
          subtitle: 'Control the active round.',
          actions: [
            AttendUsButton.secondary(label: 'Preview', onPressed: () {}),
          ],
          child: AttendUsQuizActionBar(
            children: [
              AttendUsButton.primary(label: 'Start', onPressed: () {}),
              AttendUsButton.secondary(label: 'Pause', onPressed: () {}),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Live quiz host'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
  });
}
