import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nex_client/platform/photo_encoding.dart';
import 'package:nex_client/screens/photo_crop_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('large previews stay bounded and exports use original pixels', () async {
    final jpeg = img.encodeJpg(img.Image(width: 1800, height: 900));
    final preview = await PhotoCropPreview.decode(jpeg);
    addTearDown(preview.dispose);
    expect((preview.image.width, preview.image.height), (1440, 720));
    final rendered = img.decodePng(await preview.render(1, true))!;
    expect((rendered.width, rendered.height), (720, 1440));
    final geometry = preview.parser(1)(jpeg);
    expect((geometry.width, geometry.height), (900, 1800));

    final exported = cropPhoto(
      jpeg,
      turns: 1,
      flip: true,
      x: 0,
      y: 200,
      width: 900,
      height: 1500,
    );
    expect(photoExtension(exported), '.jpg');
    final decoded = img.decodeJpg(exported)!;
    expect((decoded.width, decoded.height), (900, 1500));
  });

  test('a crop past the edge is clamped, not thrown', () {
    final source = img.encodePng(img.Image(width: 40, height: 20));
    final exported = img.decodePng(
      cropPhoto(
        source,
        turns: 0,
        flip: false,
        x: -5,
        y: 15,
        width: 100,
        height: 100,
      ),
    )!;

    expect(exported.width, lessThanOrEqualTo(40));
    expect(exported.height, lessThanOrEqualTo(20));
    expect(exported.width, greaterThan(0));
    expect(exported.height, greaterThan(0));
  });

  test('turns count as quarter turns past four and below zero', () {
    final source = img.encodePng(img.Image(width: 40, height: 20));
    final six = img.decodePng(
      cropPhoto(
        source,
        turns: 6,
        flip: false,
        x: 0,
        y: 0,
        width: 40,
        height: 20,
      ),
    )!;
    expect((six.width, six.height), (40, 20));

    final minusOne = img.decodePng(
      cropPhoto(
        source,
        turns: -1,
        flip: false,
        x: 0,
        y: 0,
        width: 20,
        height: 40,
      ),
    )!;
    expect((minusOne.width, minusOne.height), (20, 40));
  });

  test('preview and export agree on all EXIF orientations', () async {
    for (var orientation = 1; orientation <= 8; orientation++) {
      final source = img.Image(width: 32, height: 16);
      img.fillRect(
        source,
        x1: 0,
        y1: 0,
        x2: 15,
        y2: 7,
        color: img.ColorRgb8(255, 0, 0),
      );
      source.exif.imageIfd.orientation = orientation;
      final jpeg = img.encodeJpg(source);
      final preview = await PhotoCropPreview.decode(jpeg);
      try {
        final expected = img.decodePng(await preview.render(1, true))!;
        final exported = img.decodeJpg(
          cropPhoto(
            jpeg,
            turns: 1,
            flip: true,
            x: 0,
            y: 0,
            width: expected.width,
            height: expected.height,
          ),
        )!;
        expect(
          (exported.width, exported.height),
          (expected.width, expected.height),
        );
        for (final (x, y) in [
          (2, 2),
          (expected.width - 3, 2),
          (2, expected.height - 3),
          (expected.width - 3, expected.height - 3),
        ]) {
          expect(
            exported.getPixel(x, y).r > 128,
            expected.getPixel(x, y).r > 128,
            reason: 'orientation $orientation at $x,$y',
          );
        }
      } finally {
        preview.dispose();
      }
    }
  });

  test('a PNG crop keeps transparency and exact source pixels', () {
    final source = img.Image(width: 8, height: 4, numChannels: 4);
    source.setPixelRgba(1, 2, 255, 20, 50, 128);
    final cropped = cropPhoto(
      img.encodePng(source),
      turns: 0,
      flip: true,
      x: 4,
      y: 1,
      width: 4,
      height: 3,
    );
    expect(photoExtension(cropped), '.png');
    final decoded = img.decodePng(cropped)!;
    expect((decoded.width, decoded.height), (4, 3));
    final marked = decoded.getPixel(2, 1);
    expect((marked.r, marked.g, marked.b, marked.a), (255, 20, 50, 128));
  });

  test('an annotated JPEG is encoded directly at the rendered dimensions', () {
    final rgba = Uint8List(8 * 8 * 4);
    for (var i = 0; i < rgba.length; i += 4) {
      rgba[i] = 245;
      rgba[i + 3] = 255;
    }
    final bytes = encodeAnnotatedJpeg((rgba: rgba, width: 8, height: 8));
    expect(photoExtension(bytes), '.jpg');
    final decoded = img.decodeJpg(bytes)!;
    expect((decoded.width, decoded.height), (8, 8));
    expect(decoded.getPixel(3, 3).r, greaterThan(235));
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
