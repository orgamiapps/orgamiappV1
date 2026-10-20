import 'package:attendus/Services/guest_mode_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/discovery_fixture.dart';
import 'support/load_discovery_fonts.dart';

Future<void> settle(WidgetTester tester) async {
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
    bool nationwide = false,
    Future<dynamic> Function(String, Map<String, dynamic>)? handler,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = DiscoveryFixture();
    await fixture.install(guest: true);
    if (nationwide) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'discovery_location_v1',
        jsonEncode({
          'latitude': 0,
          'longitude': 0,
          'city': 'United States',
          'regionCode': 'US',
          'source': 'test',
          'nationwide': true,
        }),
      );
    }
    fixture.functions.handler = handler;
    await tester.pumpWidget(fixture.app());
    await settle(tester);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 30));
    });
    return fixture;
  }

  testWidgets(
    'desktop recommendation arrows scroll a single horizontal carousel',
    (tester) async {
      await mount(
        tester,
        width: 1280,
        handler: (name, data) async {
          if (!name.startsWith('searchDiscoveryEvents')) {
            return <String, dynamic>{};
          }
          return {
            'feedVersion': 1,
            'events': List.generate(
              16,
              (i) => {...discoveryEventFixture, 'id': '$i'},
            ),
          };
        },
      );
      final carousel = find.byWidgetPredicate(
        (widget) =>
            widget is ListView && widget.scrollDirection == Axis.horizontal,
      );
      expect(carousel, findsOneWidget);
      final controller = tester.widget<ListView>(carousel).controller!;
      expect(controller.offset, 0);
      await tester.tap(find.byTooltip('Next recommendations'));
      await settle(tester);
      expect(controller.offset, greaterThan(0));
      await tester.tap(find.byTooltip('Previous recommendations'));
      await settle(tester);
      expect(controller.offset, 0);
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'distance Apply saves fixed choice and Cancel preserves it width=$width',
      (tester) async {
        final fixture = await mount(tester, width: width);
        await tester.tap(find.text('Auto'));
        await settle(tester);
        expect(find.text('Event distance'), findsOneWidget);
        expect(
          find.byType(Dialog),
          width < 700 ? findsNothing : findsOneWidget,
        );
        await tester.tap(find.text('10 miles'));
        await tester.tap(find.text('Apply'));
        await settle(tester);
        expect(find.text('Within 10 miles'), findsOneWidget);
        expect(
          (await SharedPreferences.getInstance()).getInt(
            'discovery_fixed_miles',
          ),
          10,
        );
        expect(fixture.functions.requests.last.$2['distanceMode'], 'fixed');
        await tester.tap(find.text('10 mi'));
        await settle(tester);
        await tester.tap(find.text('100 miles'));
        await tester.tap(find.text('Cancel'));
        await settle(tester);
        expect(find.text('10 mi'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'device selection survives reopening and guest creation keeps sign-in flow',
    (tester) async {
      final fixture = await mount(tester);
      await tester.tap(find.text('Auto'));
      await settle(tester);
      await tester.tap(find.text('50 miles'));
      await tester.tap(find.text('Apply'));
      await settle(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.pumpWidget(fixture.app());
      await settle(tester);
      expect(find.text('50 mi'), findsOneWidget);
      await GuestModeService().initialize();
      await tester.ensureVisible(find.text('+ Create event'));
      await tester.tap(find.text('+ Create event'));
      await settle(tester);
      expect(find.text('Create account'), findsOneWidget);
      expect(find.text('Log in'), findsWidgets);
      expect(find.text('Create events with an account'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await settle(tester);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'city can switch to nationwide while dismissal preserves its fixed limit',
    (tester) async {
      final fixture = await mount(tester);
      await tester.tap(find.text('Auto'));
      await settle(tester);
      await tester.tap(find.text('5 miles'));
      await tester.tap(find.text('Apply'));
      await settle(tester);
      await tester.tap(find.text('Bonita Springs, FL'));
      await settle(tester);
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);
      expect(find.text('Within 5 miles'), findsOneWidget);
      await tester.tap(find.text('Bonita Springs, FL'));
      await settle(tester);
      await tester.tap(find.text('Browse online and nationwide'));
      await settle(tester);
      await tester.tap(find.text('Skip for now'));
      await settle(tester);
      expect(find.text('Auto'), findsOneWidget);
      expect(fixture.functions.requests.last.$2['nationwide'], isTrue);
      expect(fixture.functions.requests.last.$2['distanceMode'], 'auto');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('discovery_fixed_miles'), isNull);
      expect(
        jsonDecode(prefs.getString('discovery_location_v1')!)['nationwide'],
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('nationwide blocks fixed Apply and retains distance controls', (
    tester,
  ) async {
    await mount(tester, nationwide: true);
    await tester.tap(find.text('Auto'));
    await settle(tester);
    await tester.tap(find.text('5 miles'));
    await settle(tester);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
          .onPressed,
      isNull,
    );
    expect(find.text('Choose location'), findsOneWidget);
  });
  testWidgets('stale filter response cannot replace current feed', (
    tester,
  ) async {
    final old = Completer<dynamic>();
    await mount(
      tester,
      handler: (name, data) async {
        if (!name.startsWith('searchDiscoveryEvents')) {
          return <String, dynamic>{};
        }
        if (data['query'] == 'old') return old.future;
        return {
          'feedVersion': 1,
          'events': [
            {
              ...discoveryEventFixture,
              'title': data['query'] == 'new' ? 'New result' : 'Initial result',
            },
          ],
        };
      },
    );
    await tester.enterText(find.byType(TextField).first, 'old');
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'new');
    await settle(tester);
    old.complete({
      'feedVersion': 1,
      'events': [
        {...discoveryEventFixture, 'title': 'Stale result'},
      ],
    });
    await settle(tester);
    expect(find.text('New result'), findsWidgets);
    expect(find.text('Stale result'), findsNothing);
  });
  testWidgets('failed next page retains cards and retry deduplicates results', (
    tester,
  ) async {
    var fail = true;
    await mount(
      tester,
      handler: (name, data) async {
        if (!name.startsWith('searchDiscoveryEvents')) {
          return <String, dynamic>{};
        }
        if (data['cursor'] != null) {
          if (fail) throw StateError('offline');
          return {
            'feedVersion': 1,
            'events': [
              {...discoveryEventFixture, 'id': '0'},
              {
                ...discoveryEventFixture,
                'id': 'next',
                'title': 'Next page event',
              },
            ],
          };
        }
        return {
          'feedVersion': 1,
          'nextCursor': 'page2',
          'radiusMiles': 25,
          'events': List.generate(
            20,
            (i) => {...discoveryEventFixture, 'id': '$i', 'title': 'Event $i'},
          ),
        };
      },
    );
    final scroll = find.byKey(const PageStorageKey('discovery-marketplace-v2'));
    for (var i = 0; i < 10 && find.text('Load more').evaluate().isEmpty; i++) {
      await tester.drag(scroll, const Offset(0, -650));
      await settle(tester);
    }
    await tester.ensureVisible(find.text('Load more'));
    await tester.tap(find.text('Load more'));
    await settle(tester);
    expect(
      find.text('Could not load more events. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Event 19'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Load more'));
    await settle(tester);
    await tester.drag(scroll, const Offset(0, -500));
    await settle(tester);
    expect(find.text('Next page event'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
