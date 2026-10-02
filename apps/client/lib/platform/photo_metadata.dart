import 'dart:typed_data';

/// [jpeg] with its metadata segments removed, keeping only the orientation.
///
/// A photo note stores the bytes it was given, and a phone's camera writes
/// where and when it was taken — GPS, timestamps, the device — into the
/// file's EXIF block. Sharing the note handed all of it to whoever received
/// it (SEC-08). This drops the EXIF/XMP (APP1) and IPTC (APP13) segments
/// without re-encoding the picture, and writes back a minimal EXIF block with
/// the one tag the picture needs to stand the right way up.
///
/// Anything that is not a well-formed JPEG is returned unchanged.
Uint8List jpegWithoutMetadata(Uint8List jpeg) {
  if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) return jpeg;
  final out = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
  int? orientation;
  var wroteOrientation = false;
  var i = 2;
  while (i + 4 <= jpeg.length) {
    if (jpeg[i] != 0xFF) return jpeg;
    final marker = jpeg[i + 1];
    // Start of scan: the rest is image data, copied as it is.
    if (marker == 0xDA) {
      if (!wroteOrientation && orientation != null) {
        out.add(_orientationSegment(orientation));
      }
      out.add(Uint8List.sublistView(jpeg, i));
      return out.takeBytes();
    }
    final length = (jpeg[i + 2] << 8) | jpeg[i + 3];
    if (length < 2 || i + 2 + length > jpeg.length) return jpeg;
    final segment = Uint8List.sublistView(jpeg, i, i + 2 + length);
    if (marker == 0xE1 || marker == 0xED) {
      if (marker == 0xE1) {
        orientation ??= _readOrientation(Uint8List.sublistView(segment, 4));
      }
    } else {
      // Metadata is dropped where it stood; the orientation goes back in
      // right after the leading APP0 (JFIF) segment, or first if none.
      if (!wroteOrientation && orientation != null && marker != 0xE0) {
        out.add(_orientationSegment(orientation));
        wroteOrientation = true;
      }
      out.add(segment);
    }
    i += 2 + length;
  }
  return jpeg;
}

/// The orientation tag (0x0112) from an APP1 payload, if it is EXIF.
int? _readOrientation(Uint8List payload) {
  const header = [0x45, 0x78, 0x69, 0x66, 0, 0]; // "Exif\0\0"
  if (payload.length < 14) return null;
  for (var k = 0; k < header.length; k++) {
    if (payload[k] != header[k]) return null;
  }
  final tiff = ByteData.sublistView(payload, 6);
  final Endian endian;
  if (payload[6] == 0x49 && payload[7] == 0x49) {
    endian = Endian.little;
  } else if (payload[6] == 0x4D && payload[7] == 0x4D) {
    endian = Endian.big;
  } else {
    return null;
  }
  try {
    final ifd = tiff.getUint32(4, endian);
    final count = tiff.getUint16(ifd, endian);
    for (var e = 0; e < count; e++) {
      final entry = ifd + 2 + e * 12;
      if (tiff.getUint16(entry, endian) == 0x0112) {
        final value = tiff.getUint16(entry + 8, endian);
        return value >= 1 && value <= 8 ? value : null;
      }
    }
  } on RangeError {
    return null;
  }
  return null;
}

/// An APP1 segment holding a one-entry EXIF block: the orientation.
Uint8List _orientationSegment(int orientation) {
  final tiff = ByteData(26)
    ..setUint8(0, 0x4D) // "MM": big-endian
    ..setUint8(1, 0x4D)
    ..setUint16(2, 42)
    ..setUint32(4, 8) // IFD0 right after the header
    ..setUint16(8, 1) // one entry
    ..setUint16(10, 0x0112) // Orientation
    ..setUint16(12, 3) // SHORT
    ..setUint32(14, 1) // count
    ..setUint16(18, orientation)
    ..setUint32(22, 0); // no next IFD
  final payload = [0x45, 0x78, 0x69, 0x66, 0, 0, ...tiff.buffer.asUint8List()];
  final length = payload.length + 2;
  return Uint8List.fromList([
    0xFF,
    0xE1,
    length >> 8,
    length & 0xFF,
    ...payload,
  ]);
}
