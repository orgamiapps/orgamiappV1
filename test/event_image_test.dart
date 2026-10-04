import 'package:attendus/widgets/attendus_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveAttendusEventImageUrl', () {
    test('preserves Firebase media parameters and adds one cache version', () {
      const source =
          'https://firebasestorage.googleapis.com/v0/b/app/o/event.jpg?alt=media&token=abc';

      final once = resolveAttendusEventImageUrl(source);
      final twice = resolveAttendusEventImageUrl(once);
      final uri = Uri.parse(twice);

      expect(uri.queryParameters['alt'], 'media');
      expect(uri.queryParameters['token'], 'abc');
      expect(
        uri.queryParameters['attendus_image_v'],
        attendusEventImageCacheVersion,
      );
      expect(uri.queryParametersAll['attendus_image_v'], hasLength(1));
    });

    test('adds retry token without changing the stored URL', () {
      const source =
          'https://firebasestorage.googleapis.com/v0/b/app/o/event.jpg?alt=media&token=abc';

      final resolved = resolveAttendusEventImageUrl(
        source,
        retryToken: 'retry-1',
      );
      final uri = Uri.parse(resolved);

      expect(uri.queryParameters['attendus_retry'], 'retry-1');
      expect(source, isNot(contains('attendus_retry')));
    });

    test('leaves non-Firebase URLs unchanged', () {
      const source = 'https://images.example.com/event.jpg?size=large';

      expect(resolveAttendusEventImageUrl(source), source);
    });

    test('handles empty and malformed values safely', () {
      expect(resolveAttendusEventImageUrl(null), isEmpty);
      expect(resolveAttendusEventImageUrl('  '), isEmpty);
      expect(
        resolveAttendusEventImageUrl('not a valid url'),
        'not a valid url',
      );
    });
  });

  testWidgets('web renderer prefers an HTML image element', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AttendUsEventImage(
          imageUrl: 'https://example.com/event.jpg',
          useWebRendererForTesting: true,
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as NetworkImage;

    expect(provider.webHtmlElementStrategy, WebHtmlElementStrategy.prefer);
  });

  testWidgets('empty image uses the missing-image state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AttendUsEventImage(imageUrl: '')),
    );

    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
