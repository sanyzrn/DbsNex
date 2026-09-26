import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Keep lossless sources lossless. Use high quality JPEG for edited JPEG
/// photos only when smaller, without resizing or flattening transparency.
Uint8List encodeEditedPhoto(({Uint8List bytes, bool wasJpeg}) input) {
  if (!input.wasJpeg || input.bytes.length < 256 * 1024) return input.bytes;
  final decoded = img.decodeImage(input.bytes);
  if (decoded == null) throw const FormatException('Unsupported image');
  if (decoded.hasAlpha &&
      decoded.any((pixel) => pixel.a != pixel.maxChannelValue)) {
    return input.bytes;
  }
  final jpeg = Uint8List.fromList(img.encodeJpg(decoded, quality: 95));
  return jpeg.length < input.bytes.length * 0.8 ? jpeg : input.bytes;
}

String photoExtension(Uint8List bytes) =>
    bytes.length > 2 && bytes[0] == 0xff && bytes[1] == 0xd8 ? '.jpg' : '.png';
