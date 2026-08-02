import 'dart:typed_data';

import 'package:attendus/firebase/firebase_storage_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

void main() {
  group('SelectedImageData', () {
    test('loads valid image bytes from an XFile', () async {
      final encoded = Uint8List.fromList(
        img.encodePng(img.Image(width: 2, height: 2)),
      );
      final file = XFile.fromData(
        encoded,
        name: 'avatar.png',
        mimeType: 'image/png',
      );

      final selected = await SelectedImageData.fromXFile(file);

      expect(selected.bytes, encoded);
      expect(selected.mimeType, 'image/png');
      expect(selected.imageProvider, isNotNull);
    });

    test('rejects empty selections', () async {
      final file = XFile.fromData(Uint8List(0), name: 'empty.png');

      expect(
        () => SelectedImageData.fromXFile(file),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects bytes that are not an image', () async {
      final file = XFile.fromData(
        Uint8List.fromList('not an image'.codeUnits),
        name: 'fake.jpg',
      );

      expect(
        () => SelectedImageData.fromXFile(file),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
