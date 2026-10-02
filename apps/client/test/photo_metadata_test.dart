import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/photo_metadata.dart';

/// A shared photo carries no location, and still stands the right way up
/// (SEC-08).
void main() {
  /// An APP1 EXIF segment with an orientation entry and a GPS pointer, the
  /// bytes "GPSDATA" standing in for the coordinates.
  List<int> exif(int orientation) {
    final tiff = ByteData(38)
      ..setUint8(0, 0x49)
      ..setUint8(1, 0x49)
      ..setUint16(2, 42, Endian.little)
      ..setUint32(4, 8, Endian.little)
      ..setUint16(8, 2, Endian.little)
      ..setUint16(10, 0x0112, Endian.little)
      ..setUint16(12, 3, Endian.little)
      ..setUint32(14, 1, Endian.little)
      ..setUint16(18, orientation, Endian.little)
      ..setUint16(22, 0x8825, Endian.little)
      ..setUint16(24, 4, Endian.little)
      ..setUint32(26, 1, Endian.little)
      ..setUint32(30, 0, Endian.little)
      ..setUint32(34, 0, Endian.little);
    final payload = [
      ...'Exif'.codeUnits, 0, 0, //
      ...tiff.buffer.asUint8List(),
      ...'GPSDATA'.codeUnits,
    ];
    final length = payload.length + 2;
    return [0xFF, 0xE1, length >> 8, length & 0xFF, ...payload];
  }

  const jfif = [0xFF, 0xE0, 0x00, 0x04, 0x4A, 0x46];
  const quant = [0xFF, 0xDB, 0x00, 0x04, 0x01, 0x02];
  const scan = [0xFF, 0xDA, 0x00, 0x04, 0x00, 0x00, 0x11, 0x22, 0xFF, 0xD9];

  String text(List<int> bytes) => String.fromCharCodes(bytes);

  test('drops the EXIF block and keeps the orientation', () {
    final photo = Uint8List.fromList([
      0xFF, 0xD8, ...jfif, ...exif(6), ...quant, ...scan, //
    ]);
    final clean = jpegWithoutMetadata(photo);
    expect(text(clean), isNot(contains('GPSDATA')));
    expect(clean.sublist(0, 2), [0xFF, 0xD8]);
    // JFIF stays first, the image data stays byte for byte.
    expect(clean.sublist(2, 2 + jfif.length), jfif);
    expect(clean.sublist(clean.length - scan.length), scan);
    // The orientation is written back, big-endian, as the only tag.
    final at = text(clean).indexOf('Exif');
    expect(at, greaterThan(0));
    final tiff = ByteData.sublistView(clean, at + 6);
    expect(tiff.getUint16(10), 0x0112);
    expect(tiff.getUint16(18), 6);
  });

  test('a photo with no EXIF loses nothing', () {
    final photo = Uint8List.fromList([0xFF, 0xD8, ...jfif, ...quant, ...scan]);
    expect(jpegWithoutMetadata(photo), photo);
  });

  test('anything that is not a JPEG is returned as it is', () {
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
    expect(identical(jpegWithoutMetadata(png), png), isTrue);
  });
}
