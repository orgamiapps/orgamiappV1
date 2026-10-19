import 'dart:typed_data';

/// Detect the encoded bytes rather than trusting the picker filename.
String eventCoverContentType(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
    throw const FormatException('Choose an image smaller than 10 MB.');
  }
  bool starts(List<int> signature) =>
      bytes.length >= signature.length &&
      Iterable<int>.generate(
        signature.length,
      ).every((i) => bytes[i] == signature[i]);
  if (starts([255, 216, 255])) return 'image/jpeg';
  if (starts([137, 80, 78, 71, 13, 10, 26, 10])) return 'image/png';
  if (starts([71, 73, 70, 56])) return 'image/gif';
  if (starts([82, 73, 70, 70]) &&
      bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return 'image/webp';
  }
  throw const FormatException('Choose a JPEG, PNG, WebP, or GIF image.');
}
