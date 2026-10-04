import 'dart:async';

import 'package:attendus/models/event_model.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/screens/Home/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/auth_fakes.dart';

EventModel event(String title) => EventModel(
  id: title,
  title: title,
  groupName: 'Group',
  description: 'Description',
  location: 'Location',
  customerUid: 'owner',
  imageUrl: '',
  selectedDateTime: DateTime(2027),
  eventGenerateTime: DateTime(2026),
  status: 'active',
  private: false,
  getLocation: false,
  radius: 0,
  latitude: 0,
  longitude: 0,
);

void main() {
  testWidgets(
    'private events clear immediately on account switch and reject stale results',
    (tester) async {
      final auth = TestFirebaseAuth()..user = TestAuthUser('a');
      final first = Completer<List<EventModel>>();
      final second = Completer<List<EventModel>>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrgEventsList(
              searchQuery: '',
              auth: auth,
              loadEvents: (uid) => uid == 'a' ? first.future : second.future,
            ),
          ),
        ),
      );
      auth.changeUser(TestAuthUser('b'));
      second.complete([event('Account B private event')]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Account B private event'), findsOneWidget);
      first.complete([event('Account A private event')]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Account A private event'), findsNothing);
      auth.changeUser(null);
      await tester.pump();
      expect(find.text('Account B private event'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await auth.changes.close();
    },
  );

  testWidgets('user search ignores old responses as soon as query changes', (
    tester,
  ) async {
    final first = Completer<List<CustomerModel>>();
    final second = Completer<List<CustomerModel>>();
    CustomerModel user(String name) => CustomerModel(
      uid: name,
      name: name,
      email: '',
      createdAt: DateTime(2026),
    );
    Widget widget(String query) => MaterialApp(
      home: Scaffold(
        body: UsersList(
          searchQuery: query,
          searchUsers: (value) =>
              value == 'first' ? first.future : second.future,
        ),
      ),
    );
    await tester.pumpWidget(widget('first'));
    await tester.pumpWidget(widget('second'));
    first.complete([user('Stale person')]);
    await tester.pump();
    expect(find.text('Stale person'), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
    second.complete([user('Current person')]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Current person'), findsOneWidget);
  });

  testWidgets('older public search cannot replace a newer completed query', (
    tester,
  ) async {
    final first = Completer<List<EventModel>>();
    final second = Completer<List<EventModel>>();
    Future<List<EventModel>> initial() async => [event('Available')];
    Future<List<EventModel>> search(String query) =>
        query == 'first' ? first.future : second.future;
    Widget widget(String query) => MaterialApp(
      home: Scaffold(
        body: EventsList(
          searchQuery: query,
          loadInitialEvents: initial,
          searchEvents: search,
        ),
      ),
    );

    await tester.pumpWidget(widget('first'));
    await tester.pump();
    await tester.pumpWidget(widget('second'));
    second.complete([event('Newest result')]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Newest result'), findsOneWidget);
    first.complete([event('Stale result')]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Newest result'), findsOneWidget);
    expect(find.text('Stale result'), findsNothing);
  });

  testWidgets(
    'clearing a query invalidates pending search and restores browsing',
    (tester) async {
      final pending = Completer<List<EventModel>>();
      Future<List<EventModel>> initial() async => [event('Available')];
      Widget widget(String query) => MaterialApp(
        home: Scaffold(
          body: EventsList(
            searchQuery: query,
            loadInitialEvents: initial,
            searchEvents: (_) => pending.future,
          ),
        ),
      );
      await tester.pumpWidget(widget('missing'));
      await tester.pump();
      await tester.pumpWidget(widget(''));
      expect(find.text('Available'), findsOneWidget);
      pending.complete([event('Stale result')]);
      await tester.pump();
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('Stale result'), findsNothing);
    },
  );

  testWidgets('initial search query applies after delayed inventory arrives', (
    tester,
  ) async {
    final inventory = Completer<List<EventModel>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventsList(
            searchQuery: 'Target',
            loadInitialEvents: () => inventory.future,
            searchEvents: (_) async => [],
          ),
        ),
      ),
    );
    inventory.complete([event('Unrelated'), event('Target')]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Target'), findsOneWidget);
    expect(find.text('Unrelated'), findsNothing);
  });

  testWidgets(
    'inventory failures show retry and recover instead of empty success',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventsList(
              searchQuery: '',
              loadInitialEvents: () async {
                if (++calls == 1) throw StateError('offline');
                return [event('Recovered')];
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('No Events Found'), findsNothing);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(find.text('Recovered'), findsOneWidget);
    },
  );
}
