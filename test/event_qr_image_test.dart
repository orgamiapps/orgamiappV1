import 'dart:io';
import 'package:attendus/Services/event_qr_image.dart';
import 'package:attendus/Services/event_share_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'support/qr_share_fixture.dart';
import 'support/load_discovery_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('exports opaque 1080px PNG artwork and safe filenames', () async {
    await loadDiscoveryFonts();
    final event = qrShareFixture();
    final output = Directory('build/qr-share-evidence')
      ..createSync(recursive: true);
    for (final format in EventQrFormat.values) {
      final bytes = await EventQrImage.render(event, format);
      final image = img.decodePng(bytes)!;
      expect(image.width, 1080);
      expect(image.height, format == EventQrFormat.card ? 1420 : 1080);
      expect(image.getPixel(0, 0).r, 255);
      expect(image.getPixel(0, 0).a, 255);
      File('${output.path}/${format.name}.png').writeAsBytesSync(bytes);
    }
    event.title = '../../Hello / summer?';
    expect(
      EventQrImage.filename(event, EventQrFormat.card),
      'hello-summer-event-card.png',
    );
    event.title = '🌱';
    expect(EventQrImage.filename(event, EventQrFormat.qrOnly), 'event-qr.png');
  });
  test('website QR maps to details-only flow and rejects foreign URLs', () {
    expect(
      EventShareService.scannerCodeFromUrl(
        EventShareService.eventUri('qr-share-fixture').toString(),
      ),
      'attendus_event:v1:qr-share-fixture',
    );
    for (final value in [
      'https://evil.test/event/id',
      '/event/id',
      'https://attendus.app/event/one/extra',
      'https://attendus.app@evil.test/event/id',
      'attendus_checkin:v1:credential',
    ]) {
      expect(EventShareService.scannerCodeFromUrl(value), isNull);
    }
  });
}
