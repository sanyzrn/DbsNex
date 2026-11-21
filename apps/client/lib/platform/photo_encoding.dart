import 'dart:typed_data';

import 'package:image/image.dart' as img;

String photoExtension(Uint8List bytes) =>
    bytes.length > 2 && bytes[0] == 0xff && bytes[1] == 0xd8 ? '.jpg' : '.png';

bool _isJpeg(Uint8List bytes) =>
    bytes.length > 2 && bytes[0] == 0xff && bytes[1] == 0xd8;

/// Export directly from the original pixels. Only recovery of an annotation
/// draft from before this editor needs the previous byte-for-byte JPEG path.
Uint8List cropPhoto(
  Uint8List bytes, {
  required int turns,
  required bool flip,
  required int x,
  required int y,
  required int width,
  required int height,
  bool legacy = false,
}) {
  final jpeg = _isJpeg(bytes);
  final quarterTurns = ((turns % 4) + 4) % 4;
  final source = legacy && jpeg
      ? transformPhoto((
          bytes: uprightPhoto(bytes),
          turns: quarterTurns,
          flip: flip,
        ))
      : bytes;
  final decoded = img.decodeImage(source);
  if (decoded == null) throw const FormatException('Unsupported image');
  final orientation = decoded.exif.imageIfd.orientation;
  var image = !legacy && orientation != null && orientation != 1
      ? img.bakeOrientation(decoded)
      : decoded;
  if (!legacy || !jpeg) {
    if (flip) image = img.flipHorizontal(image);
    if (quarterTurns != 0) {
      image = img.copyRotate(image, angle: 90 * quarterTurns);
    }
  }
  // A crop rect can arrive a fraction past the edge from the picker's own
  // validator; clamping keeps it inside the pixels instead of throwing or
  // shaving the wrong row.
  final cropX = x.clamp(0, image.width - 1);
  final cropY = y.clamp(0, image.height - 1);
  final cropWidth = width.clamp(1, image.width - cropX);
  final cropHeight = height.clamp(1, image.height - cropY);
  final crop = img.copyCrop(
    image,
    x: cropX,
    y: cropY,
    width: cropWidth,
    height: cropHeight,
  );
  return jpeg
      ? img.encodeJpg(crop, quality: legacy ? 100 : 95)
      : img.encodePng(crop);
}

Uint8List encodeAnnotatedJpeg(
  ({Uint8List rgba, int width, int height}) input,
) => img.encodeJpg(
  img.Image.fromBytes(
    width: input.width,
    height: input.height,
    bytes: input.rgba.buffer,
    bytesOffset: input.rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  ),
  quality: 95,
);

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
