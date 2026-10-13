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

  // A camera photo is saved the way the sensor lay, with a tag saying how to
  // turn it. The cropper ignored the tag; the editor now turns it first.
  test('a tagged photo comes out upright, an untagged one untouched', () {
    final sideways = img.Image(width: 40, height: 20);
    sideways.exif.imageIfd.orientation = 6;
    final tagged = Uint8List.fromList(img.encodeJpg(sideways));
    expect(photoNeedsUpright(tagged), isTrue);
    final upright = uprightPhoto(tagged);
    expect(photoNeedsUpright(upright), isFalse);
    final decoded = img.decodeJpg(upright)!;
    expect((decoded.width, decoded.height), (20, 40));

    final plain = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 40, height: 20)),
    );
    expect(photoNeedsUpright(plain), isFalse);
    expect(identical(uprightPhoto(plain), plain), isTrue);
  });

  test('turns and flips start from the same picture, JPEG staying JPEG', () {
    final jpeg = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 40, height: 20)),
    );
    final once = transformPhoto((bytes: jpeg, turns: 1, flip: false));
    expect(once.sublist(0, 2), [0xff, 0xd8]);
    final decoded = img.decodeJpg(once)!;
    expect((decoded.width, decoded.height), (20, 40));
    // A full turn, unflipped, is the picture itself: nothing re-encoded.
    expect(
      identical(transformPhoto((bytes: jpeg, turns: 4, flip: false)), jpeg),
      isTrue,
    );

    final png = Uint8List.fromList(
      img.encodePng(
        img.Image(width: 4, height: 2)..setPixelRgb(0, 0, 255, 0, 0),
      ),
    );
    final mirrored = img.decodePng(
      transformPhoto((bytes: png, turns: 0, flip: true)),
    )!;
    expect(mirrored.getPixel(3, 0).r, 255);
  });
}
