import 'package:attendus/widgets/attendus_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('event cards use the shared event image renderer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: AttendUsEventSummaryCard(
              title: 'Event',
              imageUrl: 'https://example.com/event.jpg',
              dateLabel: 'Aug 1, 7:00 PM',
              locationLabel: 'Bonita Springs, FL',
            ),
          ),
        ),
      ),
    );

    expect(find.byType(AttendUsEventImage), findsOneWidget);
  });

  testWidgets('Firebase event images receive a stable cache version', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: AttendUsEventSummaryCard(
              title: 'Event',
              imageUrl:
                  'https://firebasestorage.googleapis.com/v0/b/app/o/event.jpg?alt=media&token=abc',
              dateLabel: 'Aug 1, 7:00 PM',
              locationLabel: 'Bonita Springs, FL',
            ),
          ),
        ),
      ),
    );

    final uri = Uri.parse(
      resolveAttendusEventImageUrl(
        'https://firebasestorage.googleapis.com/v0/b/app/o/event.jpg?alt=media&token=abc',
      ),
    );

    expect(uri.queryParameters['alt'], 'media');
    expect(uri.queryParameters['token'], 'abc');
    expect(
      uri.queryParameters['attendus_image_v'],
      attendusEventImageCacheVersion,
    );
  });
}
