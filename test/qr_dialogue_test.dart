import 'package:attendus/models/event_model.dart';
import 'package:attendus/screens/Events/Widget/qr_dialogue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(740, 320)]) {
    testWidgets('QR dialog lays out and scrolls at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime(2027, 6, 1);
      await tester.pumpWidget(
        MaterialApp(
          home: ShareQRDialog(
            singleEvent: EventModel(
              id: 'event',
              groupName: '',
              title: 'Community event',
              description: '',
              location: 'Online',
              customerUid: 'owner',
              imageUrl: '',
              selectedDateTime: now,
              eventGenerateTime: now,
              status: 'scheduled',
              private: false,
              getLocation: false,
              radius: 0,
              latitude: 0,
              longitude: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Event Share QR'), findsOneWidget);
      await tester.ensureVisible(find.text('Copy ID'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
