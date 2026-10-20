import 'dart:async';
import 'package:attendus/Services/event_qr_image.dart';
import 'package:attendus/screens/Events/Widget/qr_dialogue.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/qr_share_fixture.dart';
import 'support/load_discovery_fonts.dart';

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  final images = <EventQrFormat, Uint8List>{};
  setUpAll(() async {
    await loadDiscoveryFonts();
    for (final format in EventQrFormat.values) {
      images[format] = await EventQrImage.render(qrShareFixture(), format);
    }
  });
  for (final size in [
    const Size(390, 844),
    const Size(740, 320),
    const Size(320, 640),
  ]) {
    testWidgets('QR sharing lays out and scrolls at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(size.width == 320 ? 2 : 1),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: ShareQRDialog(
              singleEvent: qrShareFixture(),
              imageRenderer: (_, format) async => images[format]!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Share event'), findsOneWidget);
      expect(find.text('Retry image preparation'), findsNothing);
      await tester.ensureVisible(find.text('Copy image'));
      await tester.tap(find.text('Copy image'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Image copying is unavailable'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('QR only'));
      await tester.tap(find.text('QR only'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Image copying is unavailable'), findsNothing);
      await tester.ensureVisible(find.text('Copy link'));
      await tester.tap(find.text('Copy link'));
      await tester.pumpAndSettle();
      expect(find.text('Event link copied.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('preparation failure offers a working retry', (tester) async {
    var fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShareQRDialog(
            singleEvent: qrShareFixture(),
            imageRenderer: (_, format) async {
              if (fail) throw StateError('render failure');
              return images[format]!;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry image preparation'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Retry image preparation'));
    await tester.pumpAndSettle();
    expect(find.text('Retry image preparation'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });
  testWidgets('closing during preparation does not update disposed state', (
    tester,
  ) async {
    final pending = Completer<Uint8List>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShareQRDialog(
            singleEvent: qrShareFixture(),
            imageRenderer: (_, format) => pending.future,
          ),
        ),
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.complete(images[EventQrFormat.card]!);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
