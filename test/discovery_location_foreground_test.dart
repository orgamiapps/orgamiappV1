import 'dart:async';

import 'package:attendus/Services/discovery_location_service.dart';
import 'package:attendus/screens/Home/discovery_marketplace_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class PendingLocation extends DiscoveryLocationService {
  final result = Completer<DiscoveryLocation?>();
  @override
  Future<List<String>> loadInterests() async => [];
  @override
  Future<DiscoveryLocation?> load() => result.future;
}

void main() {
  for (final covered in [true, false]) {
    testWidgets(
      'location onboarding waits for visible Discover (covered=$covered)',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final locations = PendingLocation();
        final navigator = GlobalKey<NavigatorState>();
        var active = covered;
        late StateSetter rebuild;
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return TickerMode(
                  enabled: active,
                  child: Scaffold(
                    body: DiscoveryMarketplaceView(locationService: locations),
                  ),
                );
              },
            ),
          ),
        );
        if (covered) {
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Owned event')),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
        }
        locations.result.complete(null);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Find events near you'), findsNothing);
        if (covered) {
          expect(find.text('Owned event'), findsOneWidget);
          navigator.currentState!.pop();
        } else {
          rebuild(() => active = true);
        }
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(find.text('Find events near you'), findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Find events near you'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }
}
