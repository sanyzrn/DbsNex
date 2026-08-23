import 'dart:io';

import 'package:archive/archive.dart';
import 'package:nex_core/nex_core.dart';

/// Opens whatever file someone picked and hands its notes over.
///
/// The split with [NoteImport] is deliberate: parsing a note is pure logic and
/// lives in core, where it is tested without a filesystem or a zip library.
/// This is the part that has to touch both, and it lives here because
/// `packages/data` already depends on `archive` for backups — adding that
/// dependency to core, which is documented as depending on nothing in this
/// repository, to read one file format would be the wrong trade.
abstract final class NoteImportArchive {
  /// The largest archive worth opening, uncompressed.
  ///
  /// A zip bomb is 40KB on disk and gigabytes in memory, and this reads every
  /// entry into memory to decode it. Takeout exports of a decade of notes come
  /// in far under this once the photos are excluded, which they are.
  static const maxUncompressedBytes = 256 * 1024 * 1024;

  /// The largest single file read out of an archive. A note is text; anything
  /// this size claiming to be one is not.
  static const maxEntryBytes = 8 * 1024 * 1024;

  /// Whether this file is worth offering to import.
  static bool looksImportable(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.zip') || NoteImport.looksImportable(lower);
  }

  /// Reads [file] and returns what it found.
  ///
  /// Never throws for a file that is simply not an import: a `.zip` that is not
  /// a zip, a `.json` that is not a note, an empty archive all come back as an
  /// empty [NoteImportResult] rather than an error someone has to interpret.
  static NoteImportResult read(File file) {
    if (!file.existsSync()) return const NoteImportResult(notes: []);
    final List<int> bytes;
    try {
      bytes = file.readAsBytesSync();
    } catch (_) {
      return const NoteImportResult(notes: []);
    }
    if (_isZip(bytes)) return _readZip(bytes);
    return NoteImport.readEntries([(file.path, bytes)]);
  }

  /// The local-file-header magic. Checked rather than trusting the extension:
  /// people rename things, and a `.json` that is really a zip should still
  /// import.
  static bool _isZip(List<int> bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4B &&
      (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07);

  static NoteImportResult _readZip(List<int> bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return const NoteImportResult(notes: []);
    }
    final entries = <(String, List<int>)>[];
    var total = 0;
    for (final entry in archive) {
      if (!entry.isFile) continue;
      // Filtered before decompressing, not after: the photos in a Takeout
      // export are most of its bytes, and there is no reason to inflate a
      // single one of them to decide it is not a note.
      if (!NoteImport.looksImportable(entry.name)) continue;
      if (entry.size > maxEntryBytes) continue;
      total += entry.size;
      if (total > maxUncompressedBytes) break;
      final content = entry.readBytes();
      if (content == null) continue;
      entries.add((entry.name, content));
    }
    return NoteImport.readEntries(entries);
  }
}
