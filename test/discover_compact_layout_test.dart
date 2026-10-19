import 'dart:async';
import 'dart:convert';
import 'package:attendus/widgets/attendus_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/discovery_fixture.dart';
import 'support/load_discovery_fonts.dart';

Future<void> settleDiscovery(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadDiscoveryFonts);

  Future<DiscoveryFixture> mount(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
    bool guest = false,
    String city = 'Bonita Springs',
    Future<dynamic> Function(String, Map<String, dynamic>)? handler,
  }) async {
    tester.view.physicalSize = Size(width, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = DiscoveryFixture();
    await fixture.install(guest: guest, city: city);
    fixture.functions.handler = handler;
    await tester.pumpWidget(fixture.app(textScale: scale));
    await settleDiscovery(tester);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 30));
    });
    return fixture;
  }

  for (final guest in [false, true]) {
    testWidgets(
      'first event image date and title visible at 390x740 guest=$guest',
      (tester) async {
        await mount(tester, guest: guest);
        final bottom = tester.getTopLeft(find.byType(NavigationBar)).dy;
        final card = find.byType(AttendUsEventSummaryCard).first;
        final title = find.text('Community garden evening').first;
        final image = find.descendant(
          of: card,
          matching: find.byType(AttendUsEventImage),
        );
        expect(tester.getBottomLeft(image).dy, lessThan(bottom));
        expect(tester.getBottomLeft(title).dy, lessThan(bottom));
        final cardWidget = tester.widget<AttendUsEventSummaryCard>(card);
        expect(
          tester.getBottomLeft(find.text(cardWidget.dateLabel).first).dy,
          lessThan(bottom),
        );
        expect(find.text('What are you interested in?'), findsNothing);
        expect(find.text('Registrations and tickets'), findsNothing);
        expect(find.text('Saved events'), findsNothing);
        expect(find.text('Organizer workspace'), findsNothing);
        expect(find.byTooltip('Notifications'), findsOneWidget);
        if (!guest) {
          final map = tester.getRect(find.byTooltip('View events map'));
          final public = tester.getRect(find.text('Public events'));
          final private = tester.getRect(find.text('Private groups'));
          expect(map.size, const Size(48, 48));
          expect(map.center.dy, closeTo(public.center.dy, 1));
          expect(map.center.dy, closeTo(private.center.dy, 1));
          expect(map.right, 370);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [320.0, 360.0, 390.0, 430.0, 768.0, 1280.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'compact controls fit width=$width scale=$scale with long city',
        (tester) async {
          final handle = tester.ensureSemantics();
          try {
            await mount(
              tester,
              width: width,
              scale: scale,
              city: 'A very long coastal community location name',
            );
            final map = tester.getRect(find.byTooltip('View events map'));
            expect(map.left, greaterThanOrEqualTo(0));
            expect(map.right, lessThanOrEqualTo(width));
            expect(map.width, 48);
            expect(
              find.bySemanticsLabel(
                'A very long coastal community location name, FL',
              ),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          } finally {
            handle.dispose();
          }
        },
      );
    }
  }

  testWidgets(
    'category selection clearing quick filters search and location compose',
    (tester) async {
      final fixture = await mount(tester);
      await tester.tap(find.byKey(const ValueKey('discovery-category-filter')));
      await settleDiscovery(tester);
      await tester.tap(find.text('Food & Drink'));
      await settleDiscovery(tester);
      expect(
        fixture.functions.requests
            .where((r) => r.$1 == 'getDiscoveryHomeV2')
            .last
            .$2['selectedCategoryId'],
        'food-drink',
      );
      await tester.ensureVisible(find.text('Today'));
      await tester.tap(find.text('Today'));
      await settleDiscovery(tester);
      await tester.ensureVisible(find.widgetWithText(FilterChip, 'Free'));
      await tester.tap(find.widgetWithText(FilterChip, 'Free'));
      await settleDiscovery(tester);
      var request = fixture.functions.requests
          .where((r) => r.$1 == 'getDiscoveryHomeV2')
          .last
          .$2;
      expect(request['selectedCategoryId'], 'food-drink');
      expect(request['datePreset'], 'today');
      expect(request['freeOnly'], true);
      await tester.enterText(find.byType(TextField).first, 'garden');
      await settleDiscovery(tester);
      request = fixture.functions.requests
          .where((r) => r.$1 == 'searchDiscoveryEventsV2')
          .last
          .$2;
      expect(request['categoryId'], 'food-drink');
      expect(request['datePreset'], 'today');
      expect(request['freeOnly'], true);
      expect(request['query'], 'garden');
      await tester.ensureVisible(find.byTooltip('Clear category'));
      await tester.tap(find.byTooltip('Clear category'));
      await settleDiscovery(tester);
      expect(find.text('Categories'), findsOneWidget);
      request = fixture.functions.requests
          .where((r) => r.$1 == 'searchDiscoveryEventsV2')
          .last
          .$2;
      expect(request.containsKey('categoryId'), false);
      expect(request['freeOnly'], true);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.drag(
        find.byKey(const PageStorageKey('discovery-marketplace-v2')),
        const Offset(0, 600),
      );
      await settleDiscovery(tester);
      await tester.tap(find.byKey(const ValueKey('discovery-location')));
      await settleDiscovery(tester);
      expect(find.text('Choose your location'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('loading empty and error states retain compact controls', (
    tester,
  ) async {
    final response = Completer<dynamic>();
    final fixture = await mount(
      tester,
      handler: (name, data) async {
        if (name.startsWith('getDiscoveryHome')) return response.future;
        return <String, dynamic>{};
      },
    );
    expect(find.text('Categories'), findsOneWidget);
    expect(find.byType(AttendUsEventSummaryCard), findsNothing);
    response.complete(discoveryHomeFixture(empty: true));
    await settleDiscovery(tester);
    expect(find.textContaining('There are no upcoming'), findsOneWidget);
    // A fresh request without a cached response must expose a recoverable error.
    fixture.functions.handler = (name, data) async {
      if (name.startsWith('getDiscoveryHome')) {
        throw StateError('offline fixture');
      }
      return <String, dynamic>{};
    };
    await tester.tap(find.text('Today'));
    await settleDiscovery(tester);
    // With existing home data, a refresh error keeps the previous content.
    expect(find.text('Categories'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale cached results retain status and events', (tester) async {
    tester.view.physicalSize = const Size(390, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = DiscoveryFixture();
    await fixture.install();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'discovery_home_v2_26.34_-81.78_all_any_paid_all-modes_',
      jsonEncode({
        ...discoveryHomeFixture(),
        '_cachedAt': '2000-01-01T00:00:00Z',
      }),
    );
    fixture.functions.handler = (name, data) async {
      if (name.startsWith('getDiscoveryHome')) {
        throw StateError('offline fixture');
      }
      return <String, dynamic>{};
    };
    await tester.pumpWidget(fixture.app());
    await settleDiscovery(tester);
    expect(
      find.text('Showing saved results — reconnect to refresh'),
      findsOneWidget,
    );
    expect(find.text('Community garden evening'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
  });
}
