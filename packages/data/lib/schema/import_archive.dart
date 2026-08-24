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
  /// The largest run of note text worth reading out of an archive.
  ///
  /// A zip bomb is 40KB on disk and gigabytes in memory, and the text side of
  /// this reads every entry into memory to decode it. Photos are not counted
  /// against this: they are written straight to disk one at a time and never
  /// all held at once — see [_extractAttachments].
  static const maxUncompressedBytes = 256 * 1024 * 1024;

  /// The largest single file read out of an archive. A note is text; anything
  /// this size claiming to be one is not.
  static const maxEntryBytes = 8 * 1024 * 1024;

  /// The largest photo brought across, and the most of them.
  ///
  /// Both are ceilings on someone else's export rather than judgements: a
  /// Takeout archive is whatever Keep put in it, and an import that quietly
  /// fills a phone is worse than one that stops. A photo over the size cap is
  /// left behind and counted.
  static const maxAttachmentBytes = 25 * 1024 * 1024;
  static const maxAttachmentCount = 2000;

  /// Extensions worth writing out. Keep exports photos and drawings; anything
  /// else it references is not something Nex has a note type for.
  static const _imageExtensions = {'.jpg', '.jpeg', '.png', '.gif', '.webp'};

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
  /// [mediaInto] is where photos are written. Without it the text still
  /// imports and every photo is counted as skipped — which is what this did
  /// for every import until now, and what a caller with nowhere to put files
  /// still gets.
  static NoteImportResult read(File file, {Directory? mediaInto}) {
    if (!file.existsSync()) return const NoteImportResult(notes: []);
    final List<int> bytes;
    try {
      bytes = file.readAsBytesSync();
    } catch (_) {
      return const NoteImportResult(notes: []);
    }
    if (_isZip(bytes)) return _readZip(bytes, mediaInto: mediaInto);
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

  static NoteImportResult _readZip(List<int> bytes, {Directory? mediaInto}) {
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
      // export are most of its bytes, and there is no reason to inflate one to
      // decide it is not a note. They are found again below, by name, only for
      // the notes that actually reference them.
      if (!NoteImport.looksImportable(entry.name)) continue;
      if (entry.size > maxEntryBytes) continue;
      total += entry.size;
      if (total > maxUncompressedBytes) break;
      final content = entry.readBytes();
      if (content == null) continue;
      entries.add((entry.name, content));
    }
    final parsed = NoteImport.readEntries(entries);
    if (mediaInto == null) return parsed;
    return _extractAttachments(archive, parsed, mediaInto);
  }

  /// Writes out the photos the parsed notes point at, and re-types the notes
  /// that got one.
  ///
  /// Matched on the last path segment. Keep's JSON says `"filePath":
  /// "1699….jpg"` while the archive holds `Takeout/Keep/1699….jpg`, and every
  /// export nests differently — so the directory is ignored and the name is
  /// what has to agree.
  ///
  /// One photo in memory at a time. The bytes go from the archive entry
  /// straight to a file and are dropped; a Takeout export with a thousand
  /// photos never has more than one of them held.
  static NoteImportResult _extractAttachments(
    Archive archive,
    NoteImportResult parsed,
    Directory into,
  ) {
    final wanted = <String>{
      for (final note in parsed.notes)
        for (final name in note.attachments) _basename(name).toLowerCase(),
    };
    if (wanted.isEmpty) return parsed;

    final written = <String, String>{};
    var missing = 0;
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final base = _basename(entry.name).toLowerCase();
      if (!wanted.contains(base)) continue;
      if (!_imageExtensions.any(base.endsWith)) continue;
      if (entry.size > maxAttachmentBytes) continue;
      if (written.length >= maxAttachmentCount) break;
      final content = entry.readBytes();
      if (content == null) continue;
      try {
        into.createSync(recursive: true);
        // Prefixed, because an export's own filenames are timestamps and two
        // exports imported a month apart would otherwise collide in a
        // directory that already holds this user's own captures.
        final target = File(
          '${into.path}${Platform.pathSeparator}keep-${_basename(entry.name)}',
        );
        target.writeAsBytesSync(content);
        written[base] = target.path;
      } catch (_) {
        missing++;
      }
    }

    final notes = <ImportedNote>[];
    for (final note in parsed.notes) {
      final path = note.attachments
          .map((name) => written[_basename(name).toLowerCase()])
          .firstWhere((found) => found != null, orElse: () => null);
      if (path == null) {
        // Referenced a photo the archive did not carry, or one too large to
        // take. The words still import; the count says the rest did not.
        if (note.attachments.isNotEmpty) missing++;
        // A note that was only ever a photo, with no photo, is nothing.
        if (note.text.trim().isEmpty && note.title == null) continue;
        notes.add(note);
        continue;
      }
      notes.add(note.copyWith(type: NoteType.photo, text: note.text));
      _mediaFor[notes.last] = path;
    }

    return NoteImportResult(
      notes: notes,
      skippedTrashed: parsed.skippedTrashed,
      skippedAttachments: parsed.skippedAttachments + missing,
      unreadable: parsed.unreadable,
    );
  }

  /// Where each imported note's photo landed.
  ///
  /// An expando rather than a field on [ImportedNote]: that type lives in
  /// core, which has no filesystem and no business holding a path into one.
  /// The caller writing notes reads this and puts it on the note it creates.
  static final _mediaFor = Expando<String>('nex.import.media');

  /// The file this imported note's photo was written to, or null.
  static String? mediaPathFor(ImportedNote note) => _mediaFor[note];

  static String _basename(String path) {
    final cut = path.lastIndexOf(RegExp(r'[/\\]'));
    return cut < 0 ? path : path.substring(cut + 1);
  }
}
