import 'dart:io';
import 'package:archive/archive_io.dart';

/// archive 4 buffers an entire deflated entry, even with file streams.
/// Store large attachments directly: bounded memory and no recompression of
/// already-compressed photos/video. Smaller entries still use deflate.
void addBoundedZipFile(ZipFileEncoder encoder, File file, String name) {
  final input = InputFileStream(file.path);
  try {
    final entry = ArchiveFile.stream(name, input)
      ..lastModTime = file.lastModifiedSync().millisecondsSinceEpoch ~/ 1000
      ..compression = file.lengthSync() > 8 * 1024 * 1024
          ? CompressionType.none
          : CompressionType.deflate;
    encoder.addArchiveFile(entry);
  } finally {
    input.closeSync();
  }
}

/// The pinned ZIP decoder does not enforce CRC even when verify is requested.
/// Validate the extracted file in bounded chunks before installing it.
///
/// The write itself stops at the size the entry declares (SEC-06). Checking
/// the length afterwards caught a lying entry only once it had already been
/// inflated to disk in full — a few megabytes of a crafted backup could fill
/// the phone before the check ran.
void extractCheckedZipFile(ArchiveFile entry, String path) {
  final output = BoundedOutputFileStream(path, limit: entry.size);
  try {
    entry.writeContent(output);
  } finally {
    output.closeSync();
  }
  final file = File(path);
  if (file.lengthSync() != entry.size) {
    throw const FormatException('Truncated ZIP entry');
  }
  final input = file.openSync();
  var crc = 0;
  try {
    while (true) {
      final bytes = input.readSync(64 * 1024);
      if (bytes.isEmpty) break;
      crc = getCrc32(bytes, crc);
    }
  } finally {
    input.closeSync();
  }
  if (entry.crc32 != null && crc != entry.crc32) {
    throw const FormatException('ZIP checksum mismatch');
  }
}

/// An [OutputFileStream] that refuses to grow past [limit] bytes.
class BoundedOutputFileStream extends OutputFileStream {
  BoundedOutputFileStream(String path, {required this.limit})
    : super.withFileHandle(FileHandle(path, mode: FileAccess.write));

  final int limit;

  void _check(int more) {
    if (length + more > limit) {
      throw const FormatException('ZIP entry larger than it declares');
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }
}
