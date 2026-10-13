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

bool _isJpeg(Uint8List bytes) =>
    bytes.length > 2 && bytes[0] == 0xff && bytes[1] == 0xd8;

/// Whether [bytes] is a JPEG whose tag says to turn or mirror it — read
/// from the header alone, so it is cheap enough to ask on the UI thread.
bool photoNeedsUpright(Uint8List bytes) {
  if (!_isJpeg(bytes)) return false;
  try {
    final orientation = img.decodeJpgExif(bytes)?.imageIfd.orientation;
    return orientation != null && orientation != 1;
  } catch (_) {
    return false;
  }
}

/// [bytes] turned the way the photo is meant to be seen.
///
/// Cameras save a photo the way the sensor lay and add a tag saying how to
/// turn it. Every viewer honours the tag, so the preview was upright — and
/// the cropper did not: it reads the tag from the wrong place in the file,
/// so a photo held upright opened on its side there, and the crop came back
/// sideways. Turned here once, before the editor sees it, the tag no longer
/// matters. A photo with no tag, or that is not a JPEG, comes back as it is.
Uint8List uprightPhoto(Uint8List bytes) {
  if (!photoNeedsUpright(bytes)) return bytes;
  final decoded = img.decodeJpg(bytes);
  if (decoded == null) return bytes;
  final upright = img.bakeOrientation(decoded);
  return Uint8List.fromList(img.encodeJpg(upright, quality: 95));
}

/// [input.bytes] mirrored and then turned [input.turns] quarter turns
/// clockwise — always from the same picture, so turning it four times costs
/// one re-encoding, not four. A JPEG stays a JPEG (a PNG of a camera photo is
/// several times the size and slow to write); anything else becomes a PNG.
Uint8List transformPhoto(({Uint8List bytes, int turns, bool flip}) input) {
  final turns = input.turns % 4;
  if (turns == 0 && !input.flip) return input.bytes;
  final decoded = img.decodeImage(input.bytes);
  if (decoded == null) throw const FormatException('Unsupported image');
  var out = input.flip ? img.flipHorizontal(decoded) : decoded;
  if (turns != 0) out = img.copyRotate(out, angle: 90 * turns);
  return _isJpeg(input.bytes)
      ? Uint8List.fromList(img.encodeJpg(out, quality: 95))
      : Uint8List.fromList(img.encodePng(out));
}
