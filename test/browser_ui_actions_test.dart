import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rounded_loading_button_plus/rounded_loading_button.dart';
import '../integration_test/ui_actions.dart';

void main() {
  testWidgets('reverse scrolling materializes earlier lazy console controls', (
    tester,
  ) async {
    var pauses = 0;
    var admissions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              TextButton(
                onPressed: () => pauses++,
                child: const Text('Pause check-in'),
              ),
              const SizedBox(height: 1100),
              TextButton(
                onPressed: () => admissions++,
                child: const Text('Check in'),
              ),
              const SizedBox(height: 1100),
            ],
          ),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Check in'),
      400,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(
      (await revealAction(tester, find.text('Check in'))).hitTestable(),
    );
    await tester.pump();
    expect(find.text('Pause check-in'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Pause check-in'),
      -400,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(
      (await revealAction(tester, find.text('Pause check-in'))).hitTestable(),
    );
    expect(admissions, 1);
    expect(pauses, 1);
  });

  testWidgets(
    'input-handler targets work for scrolled loading, segmented and roster buttons',
    (tester) async {
      final loading = RoundedLoadingButtonController();
      var saves = 0;
      var format = 'in_person';
      var admissions = 0;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return SingleChildScrollView(
                  child: Column(
                    children: [
                      const TextField(),
                      const SizedBox(height: 1100),
                      RoundedLoadingButton(
                        controller: loading,
                        onPressed: () {
                          saves++;
                          loading.reset();
                        },
                        child: const Text('Save Changes'),
                      ),
                      const SizedBox(height: 1100),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'in_person',
                            label: Text('In person'),
                          ),
                          ButtonSegment(value: 'online', label: Text('Online')),
                        ],
                        selected: {format},
                        showSelectedIcon: false,
                        onSelectionChanged: (value) =>
                            setState(() => format = value.single),
                      ),
                      const SizedBox(height: 1100),
                      TextButton(
                        onPressed: () => admissions++,
                        child: const Text('Check in'),
                      ),
                      const SizedBox(height: 1100),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      for (final label in ['Save Changes', 'Online', 'Check in']) {
        await tester.ensureVisible(find.byType(TextField));
        await tester.pump();
        await tester.enterText(
          find.byType(TextField),
          'Pending reveal: $label',
        );
        final target = await revealAction(tester, find.text(label));
        rebuild(() {});
        await tester.pump();
        expect(target.hitTestable(), findsOneWidget, reason: label);
        await tester.tap(target.hitTestable());
        await tester.pumpAndSettle();
      }
      expect(saves, 1);
      expect(format, 'online');
      expect(admissions, 1);
    },
  );
}
