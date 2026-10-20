import 'package:attendus/Services/event_removal_navigation.dart';
import 'package:attendus/Services/event_removal_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const result = EventRemovalResult(
  status: EventRemovalStatus.deleted,
  affectedEventIds: ['event'],
);

class EventPage extends StatefulWidget {
  const EventPage({super.key, this.editor = false});
  final bool editor;
  @override
  State<EventPage> createState() => EventPageState();
}

class EventPageState extends State<EventPage> {
  Route<dynamic>? route;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    route = ModalRoute.of(context);
    EventRemovalNavigation.register(route, 'event');
  }

  @override
  void dispose() {
    EventRemovalNavigation.unregister(route);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Text(widget.editor ? 'Event editor' : 'Event details'),
        TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const EventPage(editor: true),
            ),
          ),
          child: const Text('Edit'),
        ),
        TextButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            builder: (_) => TextButton(
              onPressed: () => EventRemovalNavigation.complete(context, result),
              child: const Text('Delete in tools'),
            ),
          ),
          child: const Text('Organizer tools'),
        ),
        TextButton(
          onPressed: () => EventRemovalNavigation.complete(context, result),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
}

void main() {
  testWidgets(
    'removal unwinds editor, organizer sheet and detail to same list',
    (tester) async {
      final key = GlobalKey<NavigatorState>();
      var filter = 'Upcoming';
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: Column(
                  children: [
                    Text('List filter: $filter'),
                    TextButton(
                      onPressed: () => setState(() => filter = 'My city'),
                      child: const Text('Choose filter'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const EventPage(),
                        ),
                      ),
                      child: const Text('Open event'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Choose filter'));
      await tester.pump();
      await tester.tap(find.text('Open event'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Organizer tools'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete in tools'));
      await tester.pumpAndSettle();
      expect(find.text('List filter: My city'), findsOneWidget);
      expect(find.text('Event deleted'), findsOneWidget);
      expect(find.text('Event editor'), findsNothing);
      expect(find.text('Event details'), findsNothing);
      expect(key.currentState!.canPop(), false);
    },
  );

  testWidgets(
    'direct event root falls back to Discover and removes stale route',
    (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          home: const EventPage(),
          routes: {
            '/app/discover': (_) => const Scaffold(body: Text('Discover list')),
          },
        ),
      );
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Discover list'), findsOneWidget);
      expect(find.text('Event deleted'), findsOneWidget);
      expect(key.currentState!.canPop(), false);
    },
  );
}
