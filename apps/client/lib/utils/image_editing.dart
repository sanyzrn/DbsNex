import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// How a photo's bytes are encoded on disk.
enum NexImageFormat { jpeg, png, other }

/// What the editor knows about a photo before it decodes it.
class NexImageInfo {
  const NexImageInfo({
    required this.width,
    required this.height,
    required this.format,
  });

  /// Pixel width of the photo, when the header could be read.
  ///
  /// Null for a format whose header this file cannot parse (e.g. a WebP):
  /// the "Original" aspect preset then falls back to free crop rather than
  /// guessing.
  final int? width;
  final int? height;
  final NexImageFormat format;
}

/// Reads a photo's dimensions and encoding straight from its header bytes —
/// no full decode, so it is effectively free even for a 48-megapixel capture.
///
/// JPEG dimensions come from the SOF marker, PNG's from the IHDR chunk.
NexImageInfo nexImageInfo(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    final (width, height) = _jpegSize(bytes);
    return NexImageInfo(width: width, height: height, format: NexImageFormat.jpeg);
  }
  if (bytes.length >= 24 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    final width = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
    final height = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
    return NexImageInfo(
      width: width,
      height: height,
      format: NexImageFormat.png,
    );
  }
  return const NexImageInfo(width: null, height: null, format: NexImageFormat.other);
}

/// Parses a JPEG's SOF marker for width and height.
///
/// Returns (null, null) when no SOF marker is found — the file is a JPEG
/// (the magic was already checked) but in an unusual layout, and falling back
/// to "unknown" is always safe.
(int?, int?) _jpegSize(Uint8List bytes) {
  var offset = 2;
  while (offset + 9 < bytes.length) {
    if (bytes[offset] != 0xFF) {
      offset++;
      continue;
    }
    final marker = bytes[offset + 1];
    // Standalone markers carry no length.
    if (marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD7) || marker == 0x01) {
      offset += 2;
      continue;
    }
    final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
    // SOF0–SOF3, SOF5–SOF7, SOF9–SOF11, SOF13–SOF15 (not DHT/DAC/RST/SOI/EOI).
    final isSof =
        (marker >= 0xC0 && marker <= 0xC3) ||
        (marker >= 0xC5 && marker <= 0xC7) ||
        (marker >= 0xC9 && marker <= 0xCB) ||
        (marker >= 0xCD && marker <= 0xCF);
    if (isSof && offset + 9 < bytes.length) {
      final height = (bytes[offset + 5] << 8) | bytes[offset + 6];
      final width = (bytes[offset + 7] << 8) | bytes[offset + 8];
      return (width, height);
    }
    offset += 2 + length;
  }
  return (null, null);
}

/// Applies the editor's geometric transforms to a photo.
///
/// Pure and top-level so it can run through `compute()` off the UI isolate.
/// Returns new bytes; the input is never modified.
///
/// Order matters and is deliberate:
///
/// 1. **EXIF orientation is baked in** — a camera JPEG can carry a rotation
///    tag instead of rotated pixels, and every tool below would otherwise
///    work on a sideways image.
/// 2. **Downscale happens before geometry** — with orthogonal rotations and
///    flips the output is pixel-identical to doing it after, and working on
///    a smaller image keeps peak memory a fraction of the original's.
/// 3. Flips, then rotation, in the order the user pressed them.
///
/// The output encoding follows the input: PNG stays PNG (it may carry
/// transparency), everything else becomes JPEG at quality 90 — the format a
/// camera or gallery produces in the first place.
Uint8List nexTransformImage(
  Uint8List bytes, {
  int quarterTurns = 0,
  bool flipHorizontal = false,
  bool flipVertical = false,
  int maxLongEdge = 0,
}) {
  final source = img.decodeImage(bytes);
  if (source == null) return bytes;

  var image = img.bakeOrientation(source);

  if (maxLongEdge > 0) {
    final long = image.width > image.height ? image.width : image.height;
    if (long > maxLongEdge) {
      image = image.width >= image.height
          ? img.copyResize(
              image,
              width: maxLongEdge,
              interpolation: img.Interpolation.cubic,
            )
          : img.copyResize(
              image,
              height: maxLongEdge,
              interpolation: img.Interpolation.cubic,
            );
    }
  }

  if (flipHorizontal && flipVertical) {
    image = img.flip(image, direction: img.FlipDirection.both);
  } else if (flipHorizontal) {
    image = img.flip(image, direction: img.FlipDirection.horizontal);
  } else if (flipVertical) {
    image = img.flip(image, direction: img.FlipDirection.vertical);
  }

  final angle = (quarterTurns % 4) * 90;
  if (angle != 0) {
    image = img.copyRotate(image, angle: angle);
  }

  return nexImageFormatOf(bytes) == NexImageFormat.png
      ? img.encodePng(image)
      : img.encodeJpg(image, quality: 90);
}

/// The editor's final write: [bytes] (the cropper's PNG output) re-encoded
/// for storage — JPEG at quality 90 for photographic input, PNG kept for PNG
/// input, and the long edge capped at [maxLongEdge] when it exceeds it.
Uint8List nexEncodeFinal(
  Uint8List bytes, {
  required NexImageFormat sourceFormat,
  int maxLongEdge = 0,
}) {
  final keepPng = sourceFormat == NexImageFormat.png;
  if (maxLongEdge <= 0) {
    if (keepPng) return bytes;
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;
    return img.encodeJpg(image, quality: 90);
  }

  final image = img.decodeImage(bytes);
  if (image == null) return bytes;
  final long = image.width > image.height ? image.width : image.height;
  final capped = long > maxLongEdge
      ? (image.width >= image.height
            ? img.copyResize(
                image,
                width: maxLongEdge,
                interpolation: img.Interpolation.cubic,
              )
            : img.copyResize(
                image,
                height: maxLongEdge,
                interpolation: img.Interpolation.cubic,
              ))
      : image;
  return keepPng ? img.encodePng(capped) : img.encodeJpg(capped, quality: 90);
}

/// The encoding a byte sequence actually carries, by its magic number.
NexImageFormat nexImageFormatOf(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return NexImageFormat.jpeg;
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return NexImageFormat.png;
  }
  return NexImageFormat.other;
}

/// The filename extension for a photo stored as [format].
///
/// Falls back to [fallback] (the picked file's own extension) for anything
/// the editor did not normalize.
String nexExtensionFor(NexImageFormat format, {required String fallback}) =>
    switch (format) {
      NexImageFormat.jpeg => 'jpg',
      NexImageFormat.png => 'png',
      NexImageFormat.other => fallback,
    };

/// One editor transform, boxed so it can cross an isolate boundary as the
/// single argument `compute()` allows.
class NexTransformRequest {
  const NexTransformRequest({
    required this.bytes,
    this.quarterTurns = 0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.maxLongEdge = 0,
  });

  final Uint8List bytes;
  final int quarterTurns;
  final bool flipHorizontal;
  final bool flipVertical;
  final int maxLongEdge;
}

/// Top-level entry point for `compute()`; see [nexTransformImage].
Uint8List nexTransformImageRequest(NexTransformRequest request) =>
    nexTransformImage(
      request.bytes,
      quarterTurns: request.quarterTurns,
      flipHorizontal: request.flipHorizontal,
      flipVertical: request.flipVertical,
      maxLongEdge: request.maxLongEdge,
    );

/// The editor's final write, boxed for `compute()`; see [nexEncodeFinal].
class NexEncodeRequest {
  const NexEncodeRequest({
    required this.bytes,
    required this.sourceFormat,
    this.maxLongEdge = 0,
  });

  final Uint8List bytes;
  final NexImageFormat sourceFormat;
  final int maxLongEdge;
}

/// Top-level entry point for `compute()`; see [nexEncodeFinal].
Uint8List nexEncodeRequest(NexEncodeRequest request) => nexEncodeFinal(
  request.bytes,
  sourceFormat: request.sourceFormat,
  maxLongEdge: request.maxLongEdge,
);
