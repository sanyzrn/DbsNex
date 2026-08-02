import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nex_client/utils/image_editing.dart';

/// Builds a tiny PNG of [width]x[height], each pixel a distinct color when
/// [gradient] is set (row-major), so geometry can be asserted pixel-exactly.
Uint8List _png(int width, int height, {bool gradient = false}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(
        x,
        y,
        gradient ? (x * 40 + y * 80) % 256 : 120,
        gradient ? (x * 90 + y * 30) % 256 : 40,
        gradient ? (x * 20 + y * 160) % 256 : 200,
        255,
      );
    }
  }
  return img.encodePng(image);
}

Uint8List _jpeg(int width, int height) {
  final image = img.Image(width: width, height: height);
  image.fill(img.ColorRgb8(90, 120, 200));
  return img.encodeJpg(image, quality: 92);
}

void main() {
  group('nexImageInfo reads headers without decoding', () {
    test('jpeg magic and SOF dimensions', () {
      final info = nexImageInfo(_jpeg(640, 480));
      expect(info.format, NexImageFormat.jpeg);
      expect(info.width, 640);
      expect(info.height, 480);
    });

    test('png magic and IHDR dimensions', () {
      final info = nexImageInfo(_png(320, 200));
      expect(info.format, NexImageFormat.png);
      expect(info.width, 320);
      expect(info.height, 200);
    });

    test('unknown bytes are reported, never thrown', () {
      final info = nexImageInfo(Uint8List.fromList([1, 2, 3, 4, 5]));
      expect(info.format, NexImageFormat.other);
      expect(info.width, isNull);
      expect(info.height, isNull);
    });

    test('nexImageFormatOf agrees with nexImageInfo', () {
      expect(nexImageFormatOf(_jpeg(4, 4)), NexImageFormat.jpeg);
      expect(nexImageFormatOf(_png(4, 4)), NexImageFormat.png);
    });
  });

  group('nexTransformImage', () {
    test('rotate 90 swaps the dimensions', () {
      final out = nexTransformImage(_png(4, 2), quarterTurns: 1);
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, 2);
      expect(decoded.height, 4);
    });

    test('rotate 270 swaps them the other way', () {
      // 4x2 gradient: row 0 has r = 0, 40, 80, 120; row 1 has r = 80, 120,
      // 160, 200. 270° clockwise (90° counter-clockwise) maps
      // dst(x, y) = src(w - 1 - y, x).
      final out = nexTransformImage(_png(4, 2, gradient: true), quarterTurns: 3);
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, 2);
      expect(decoded.height, 4);
      expect(decoded.getPixel(1, 0).r, 120); // src(3, 0)
      expect(decoded.getPixel(0, 1).r, 160); // src(2, 1)
    });

    test('rotate 180 keeps the dimensions and moves every corner', () {
      // 4x2 gradient; dst(x, y) = src(w - 1 - x, h - 1 - y).
      final out = nexTransformImage(_png(4, 2, gradient: true), quarterTurns: 2);
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, 4);
      expect(decoded.height, 2);
      expect(decoded.getPixel(0, 0).r, 200); // src(3, 1)
      expect(decoded.getPixel(3, 0).r, 80); // src(0, 1)
      expect(decoded.getPixel(0, 1).r, 120); // src(3, 0)
      expect(decoded.getPixel(3, 1).r, 0); // src(0, 0)
    });

    test('horizontal flip mirrors the columns', () {
      final out = nexTransformImage(_png(3, 1, gradient: true), flipHorizontal: true);
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, 3);
      expect(decoded.getPixel(0, 0).r, 80); // was the rightmost column
      expect(decoded.getPixel(2, 0).r, 0); // was the leftmost column
    });

    test('vertical flip mirrors the rows', () {
      final out = nexTransformImage(_png(1, 3, gradient: true), flipVertical: true);
      final decoded = img.decodeImage(out)!;
      expect(decoded.height, 3);
      expect(decoded.getPixel(0, 0).r, 160); // was the bottom row
      expect(decoded.getPixel(0, 2).r, 0); // was the top row
    });

    test('maxLongEdge caps the long edge and keeps the aspect', () {
      final out = nexTransformImage(_png(400, 200), maxLongEdge: 100);
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, 100);
      expect(decoded.height, 50);
    });

    test('a small image is not upscaled', () {
      final out = nexTransformImage(_png(40, 20), maxLongEdge: 100);
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, 40);
      expect(decoded.height, 20);
    });

    test('png stays png; jpeg input becomes jpeg output', () {
      expect(nexImageFormatOf(nexTransformImage(_png(4, 4))), NexImageFormat.png);
      expect(
        nexImageFormatOf(nexTransformImage(_jpeg(4, 4))),
        NexImageFormat.jpeg,
      );
    });

    test('undecodable bytes come back untouched, not thrown', () {
      final garbage = Uint8List.fromList([1, 2, 3]);
      expect(nexTransformImage(garbage, quarterTurns: 1), same(garbage));
    });
  });

  group('nexEncodeFinal', () {
    test('png source stays png and is not re-encoded pointlessly', () {
      final source = _png(4, 4);
      final out = nexEncodeFinal(source, sourceFormat: NexImageFormat.png);
      expect(out, same(source), reason: 'PNG is already the storage format');
    });

    test('jpeg source is encoded as jpeg', () {
      final out = nexEncodeFinal(_png(4, 4), sourceFormat: NexImageFormat.jpeg);
      expect(nexImageFormatOf(out), NexImageFormat.jpeg);
    });

    test('maxLongEdge downscales the final image', () {
      final out = nexEncodeFinal(
        _png(400, 200),
        sourceFormat: NexImageFormat.jpeg,
        maxLongEdge: 100,
      );
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, 100);
      expect(decoded.height, 50);
    });
  });

  group('nexExtensionFor', () {
    test('maps the normalized formats', () {
      expect(
        nexExtensionFor(NexImageFormat.jpeg, fallback: 'bin'),
        'jpg',
      );
      expect(nexExtensionFor(NexImageFormat.png, fallback: 'bin'), 'png');
      expect(
        nexExtensionFor(NexImageFormat.other, fallback: 'bin'),
        'bin',
      );
    });
  });
}
