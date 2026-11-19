import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crop_your_image/crop_your_image.dart';

import '../platform/photo_encoding.dart';

/// The editor draws and transforms a screen-sized copy. The crop rectangle
/// still uses original pixels, including when restoring an older draft.
class PhotoCropPreview {
  PhotoCropPreview._(this.image, this.originalSize);

  static const maxSide = 1440;

  final ui.Image image;
  final ui.Size originalSize;

  static Future<PhotoCropPreview> decode(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      // The engine applies EXIF orientation to both the dimensions and pixels.
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      final scale = math.min(1.0, maxSide / math.max(width, height));
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (width * scale).round()),
        targetHeight: math.max(1, (height * scale).round()),
      );
      final frame = await codec.getNextFrame();
      return PhotoCropPreview._(
        frame.image,
        ui.Size(width.toDouble(), height.toDouble()),
      );
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  Future<Uint8List> render(int turns, bool flip) async {
    if (turns == 0 && !flip) {
      return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
          .asUint8List();
    }
    final width = turns.isOdd ? image.height : image.width;
    final height = turns.isOdd ? image.width : image.height;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..translate(width / 2, height / 2)
      ..rotate(turns * math.pi / 2)
      ..scale(flip ? -1 : 1, 1);
    canvas.drawImage(
      image,
      ui.Offset(-image.width / 2, -image.height / 2),
      ui.Paint(),
    );
    final picture = recorder.endRecording();
    ui.Image? transformed;
    try {
      transformed = await picture.toImage(width, height);
      return (await transformed.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
    } finally {
      transformed?.dispose();
      picture.dispose();
    }
  }

  ImageParser<ui.Size> parser(int turns) =>
      _CropDimensions(turns.isOdd ? originalSize.flipped : originalSize).parse;

  void dispose() => image.dispose();
}

class _CropDimensions {
  const _CropDimensions(this.size);

  final ui.Size size;

  // This method is sent to an isolate by Crop. Its receiver holds only the
  // size, never the UI image or the full photo.
  ImageDetail<ui.Size> parse(Uint8List _, {ImageFormat? inputFormat}) =>
      ImageDetail(image: size, width: size.width, height: size.height);
}

class OriginalPhotoCropper extends ImageCropper<ui.Size> {
  const OriginalPhotoCropper(this.bytes, this.turns, this.flip, this.legacy);

  final Uint8List bytes;
  final int turns;
  final bool flip;
  final bool legacy;

  @override
  RectValidator<ui.Size> get rectValidator =>
      (original, topLeft, bottomRight) =>
          topLeft.dx < 0 ||
              topLeft.dy < 0 ||
              bottomRight.dx > original.width + 0.001 ||
              bottomRight.dy > original.height + 0.001 ||
              topLeft.dx >= bottomRight.dx ||
              topLeft.dy >= bottomRight.dy
          ? const FormatException('Crop lies outside the photo')
          : null;

  @override
  RectCropper<ui.Size> get rectCropper =>
      (_, {required topLeft, required size, required outputFormat}) =>
          cropPhoto(
            bytes,
            turns: turns,
            flip: flip,
            x: topLeft.dx.toInt(),
            y: topLeft.dy.toInt(),
            width: math.max(1, size.width.toInt()),
            height: math.max(1, size.height.toInt()),
            legacy: legacy,
          );

  @override
  CircleCropper<ui.Size> get circleCropper =>
      (_, {required center, required radius, required outputFormat}) =>
          throw UnsupportedError('The photo editor uses rectangular crops');
}
