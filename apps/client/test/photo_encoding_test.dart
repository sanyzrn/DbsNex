import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nex_client/platform/photo_encoding.dart';

void main() {
  test(
    'edited JPEG retains dimensions and uses smaller high quality encoding',
    () {
      final image = img.Image(width: 640, height: 480);
      final random = Random(42);
      for (final pixel in image) {
        pixel.setRgb(
          (pixel.x ~/ 3 + random.nextInt(32)).clamp(0, 255),
          (pixel.y ~/ 2 + random.nextInt(32)).clamp(0, 255),
          120 + random.nextInt(32),
        );
      }
      final png = Uint8List.fromList(img.encodePng(image));
      final output = encodeEditedPhoto((bytes: png, wasJpeg: true));
      expect(output.length, lessThan(png.length));
      expect(photoExtension(output), '.jpg');
      final decoded = img.decodeImage(output)!;
      expect((decoded.width, decoded.height), (640, 480));
      expect(encodeEditedPhoto((bytes: png, wasJpeg: false)), same(png));
    },
  );

  test('transparent edits never become opaque JPEG', () {
    final image = img.Image(width: 400, height: 400, numChannels: 4);
    final random = Random(8);
    for (final pixel in image) {
      pixel.setRgba(
        random.nextInt(256),
        random.nextInt(256),
        random.nextInt(256),
        128,
      );
    }
    final png = Uint8List.fromList(img.encodePng(image));
    expect(encodeEditedPhoto((bytes: png, wasJpeg: true)), same(png));
  });
}
