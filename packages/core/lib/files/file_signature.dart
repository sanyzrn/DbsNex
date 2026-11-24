import 'file_kind.dart';

/// What a file's own first bytes say it is.
///
/// An extension and a MIME type are both claims made by somebody else. A PDF
/// renamed `scan.jpg` still starts with `%PDF`, and Android's picker can hand
/// back a cached copy whose name carries no extension at all. This reads the
/// header instead, so a media pick can refuse a file that is not a photo or a
/// video rather than storing it as one.
///
/// Only the signatures Nex can show are recognised. An unknown header answers
/// null, which lets the caller fall back to the name or MIME type — a real
/// photo must not be refused because its container starts with a box this
/// reader does not know.
abstract final class NexFileSignatures {
  /// How many leading bytes [of] reads. Enough for every signature here,
  /// including the ISO base-media brands at offset 8.
  static const headLength = 64;

  /// The kind [head] identifies, or null when it matches no known signature.
  static NexFileKind? of(List<int> head) {
    if (head.isEmpty) return null;

    // ISO base media (MP4, MOV, 3GP, HEIC, AVIF, M4A) puts its brand after
    // a four-byte box length and `ftyp` at offset 4.
    if (_ascii(head, 4, 'ftyp')) {
      final brand = _asciiAt(head, 8, 4);
      if (brand == null) return null;
      if (const {
        'heic',
        'heix',
        'hevc',
        'hevx',
        'heim',
        'heis',
        'hevm',
        'hevs',
        'heif',
        'mif1',
        'msf1',
        'avif',
        'avis',
      }.contains(brand)) {
        return NexFileKind.image;
      }
      if (const {'M4A ', 'M4B ', 'M4P ', 'F4A ', 'F4B '}.contains(brand)) {
        return NexFileKind.audio;
      }
      // Whatever else the brand is, a file behind `ftyp` is a video
      // container: `qt  `, `isom`, `mp41`, `mp42`, `avc1`, `dash`, `3gp4`…
      return NexFileKind.video;
    }

    if (_ascii(head, 0, 'RIFF')) {
      final form = _asciiAt(head, 8, 4);
      if (form == 'WEBP') return NexFileKind.image;
      if (form == 'AVI ') return NexFileKind.video;
      if (form == 'WAVE') return NexFileKind.audio;
    }

    // Matroska and WebM share one EBML header.
    if (_bytes(head, 0, const [0x1A, 0x45, 0xDF, 0xA3])) {
      return NexFileKind.video;
    }

    if (_bytes(head, 0, const [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ])) {
      return NexFileKind.image; // PNG
    }
    if (_bytes(head, 0, const [0xFF, 0xD8, 0xFF])) {
      return NexFileKind.image; // JPEG
    }
    if (_ascii(head, 0, 'GIF87a') || _ascii(head, 0, 'GIF89a')) {
      return NexFileKind.image;
    }
    if (_bytes(head, 0, const [0x42, 0x4D])) return NexFileKind.image; // BMP
    // TIFF, both byte orders. Flutter can decode the common ones.
    if (_bytes(head, 0, const [0x49, 0x49, 0x2A, 0x00]) ||
        _bytes(head, 0, const [0x4D, 0x4D, 0x00, 0x2A])) {
      return NexFileKind.image;
    }

    if (_ascii(head, 0, '%PDF')) return NexFileKind.document;
    // ZIP and its office-document relatives; RAR, 7z and gzip are archives.
    if (_bytes(head, 0, const [0x50, 0x4B, 0x03, 0x04]) ||
        _bytes(head, 0, const [0x50, 0x4B, 0x05, 0x06]) ||
        _bytes(head, 0, const [0x50, 0x4B, 0x07, 0x08]) ||
        _ascii(head, 0, 'Rar!') ||
        _bytes(head, 0, const [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) ||
        _bytes(head, 0, const [0x1F, 0x8B])) {
      return NexFileKind.other;
    }

    if (_ascii(head, 0, 'OggS') ||
        _ascii(head, 0, 'fLaC') ||
        _ascii(head, 0, 'ID3') ||
        _ascii(head, 0, '#!AMR')) {
      return NexFileKind.audio;
    }
    // An MPEG audio frame with no ID3 tag.
    if (head.length >= 2 && head[0] == 0xFF && (head[1] & 0xE0) == 0xE0) {
      return NexFileKind.audio;
    }

    return null;
  }

  static bool _ascii(List<int> bytes, int at, String text) =>
      _asciiAt(bytes, at, text.length) == text;

  static String? _asciiAt(List<int> bytes, int at, int length) {
    if (at < 0 || length <= 0 || bytes.length < at + length) return null;
    final codes = bytes.sublist(at, at + length);
    if (codes.any((code) => code < 0x20 || code > 0x7E)) return null;
    return String.fromCharCodes(codes);
  }

  static bool _bytes(List<int> bytes, int at, List<int> signature) {
    if (bytes.length < at + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[at + i] != signature[i]) return false;
    }
    return true;
  }
}
