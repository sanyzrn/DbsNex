import 'dart:typed_data';
import 'package:archive/archive.dart';

/// A supplied password alone does not make a ZIP authenticated: the decoder
/// also accepts plaintext/ZipCrypto entries. Require Nex's WinZip AES-256
/// format before trusting settings or private attachments from another device.
void assertAuthenticatedZip(ZipDecoder decoder) {
  for (final header in decoder.directory.fileHeaders) {
    final file = header.file;
    final extra = file?.extraField;
    var authenticated = false;
    if (file != null &&
        extra != null &&
        header.compressionMethod == 99 &&
        header.generalPurposeBitFlag & 1 != 0 &&
        file.flags & 1 != 0) {
      final data = ByteData.sublistView(extra);
      var at = 0;
      while (at + 4 <= extra.length) {
        final id = data.getUint16(at, Endian.little);
        final length = data.getUint16(at + 2, Endian.little);
        final end = at + 4 + length;
        if (end > extra.length) break;
        if (id == 0x9901 && length == 7) {
          final version = data.getUint16(at + 4, Endian.little);
          authenticated =
              (version == 1 || version == 2) &&
              extra[at + 6] == 65 &&
              extra[at + 7] == 69 &&
              extra[at + 8] == 3;
        }
        at = end;
      }
    }
    if (!authenticated) {
      throw const FormatException('Unauthenticated private ZIP');
    }
  }
}
