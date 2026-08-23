import 'dart:convert';

import '../models/checklist.dart';
import '../models/note.dart';

/// One note read out of somebody else's export, before it becomes a [Note].
///
/// Deliberately not a [Note]: an imported note has no id, no revision and no
/// device, and inventing those here would put identity in a parser. This is
/// the shape the capture path can accept, and nothing more.
class ImportedNote {
  const ImportedNote({
    required this.type,
    required this.text,
    this.title,
    this.tags = const [],
    this.createdAt,
    this.items = const [],
  });

  /// Only ever [NoteType.text] or [NoteType.checklist]. Photos and recordings
  /// in an export are files this cannot reach — see [NoteImport] on why they
  /// are counted rather than silently dropped.
  final NoteType type;

  /// The note's body, already in Nex's own format — checklist lines included,
  /// so a caller that only knows about text still writes something readable.
  final String text;

  final String? title;
  final List<String> tags;

  /// When it was written, where the export said so. Null when it did not.
  final DateTime? createdAt;

  /// The checklist's items, for a caller that wants them typed rather than as
  /// markdown. Empty for a text note.
  final List<ChecklistItem> items;
}

/// What one import found, including what it could not bring across.
class NoteImportResult {
  const NoteImportResult({
    required this.notes,
    this.skippedTrashed = 0,
    this.skippedAttachments = 0,
    this.unreadable = 0,
  });

  final List<ImportedNote> notes;

  /// Notes the export had already put in its own trash. Not imported: someone
  /// who deleted a note in Keep deleted it, and a "restore everything you ever
  /// wrote" import is not what anybody asks for.
  final int skippedTrashed;

  /// Notes whose only content was a photo or a drawing. Counted rather than
  /// silently ignored — an import that says "48 notes" when the export had 60
  /// is a bug report waiting to happen, and this is the honest number.
  final int skippedAttachments;

  /// Files in the archive that were not notes in any format understood here.
  final int unreadable;

  bool get isEmpty => notes.isEmpty;
}

/// Reads notes out of an export from another app.
///
/// Three shapes, because they are the three people actually have in hand:
///
/// - a Google Takeout `.zip` — every `.json` under it that looks like a Keep
///   note, which is where Takeout puts them (`Takeout/Keep/*.json`), though
///   this does not depend on that path holding;
/// - a single Keep `.json`, for anyone who unzipped it themselves;
/// - `.md` and `.txt` files, one note each, alone or inside a zip. That is
///   every other notes app in the world once it has been exported, and it is
///   also what Nex's own export writes.
///
/// The zip itself is not opened here — [packages/core] has no archive
/// dependency and is not getting one for this. The caller unzips and hands
/// over `(filename, bytes)` pairs; see [readEntries].
abstract final class NoteImport {
  /// Whether a filename is worth handing to [readEntries] at all.
  static bool looksImportable(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('/')) return false;
    // Takeout ships a `.html` beside every `.json`, and macOS ships
    // `__MACOSX/._name` resource forks beside everything. Both are the same
    // note twice, or no note at all.
    if (lower.contains('__macosx/')) return false;
    if (lower.split('/').last.startsWith('.')) return false;
    return lower.endsWith('.json') ||
        lower.endsWith('.md') ||
        lower.endsWith('.markdown') ||
        lower.endsWith('.txt');
  }

  /// Turns a set of files into notes.
  ///
  /// Entries are `(filename, bytes)`. Order does not matter and neither do
  /// directories: the filename is used for a title and for choosing a parser,
  /// never for deciding what belongs to what.
  static NoteImportResult readEntries(List<(String, List<int>)> entries) {
    final notes = <ImportedNote>[];
    var trashed = 0;
    var attachments = 0;
    var unreadable = 0;

    for (final (name, bytes) in entries) {
      if (!looksImportable(name)) continue;
      final String text;
      try {
        text = utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        unreadable++;
        continue;
      }
      if (name.toLowerCase().endsWith('.json')) {
        final result = _readKeepJson(text);
        switch (result.outcome) {
          case _Outcome.note:
            notes.add(result.note!);
          case _Outcome.trashed:
            trashed++;
          case _Outcome.attachmentOnly:
            attachments++;
          case _Outcome.notKeep:
            unreadable++;
        }
        continue;
      }
      final note = _readMarkdown(name, text);
      if (note == null) {
        unreadable++;
        continue;
      }
      notes.add(note);
    }

    // Oldest first, so importing writes them in the order they were written
    // and the timeline reads as a history rather than as a shuffle. Notes with
    // no date sort last: they are the ones with nothing to place them.
    notes.sort((a, b) {
      final left = a.createdAt;
      final right = b.createdAt;
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      return left.compareTo(right);
    });

    return NoteImportResult(
      notes: notes,
      skippedTrashed: trashed,
      skippedAttachments: attachments,
      unreadable: unreadable,
    );
  }

  static _KeepOutcome _readKeepJson(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } catch (_) {
      return const _KeepOutcome.notKeep();
    }
    if (decoded is! Map) return const _KeepOutcome.notKeep();

    // Keep's own field names. A JSON file that has none of them is some other
    // app's export or a settings file that happened to be in the archive.
    final hasText = decoded.containsKey('textContent');
    final hasList = decoded.containsKey('listContent');
    final hasTitle = decoded.containsKey('title');
    if (!hasText && !hasList && !hasTitle) return const _KeepOutcome.notKeep();

    if (decoded['isTrashed'] == true) return const _KeepOutcome.trashed();

    final title = (decoded['title'] as String?)?.trim();
    final tags = <String>[
      for (final label in (decoded['labels'] as List? ?? const []))
        if (label is Map && label['name'] is String)
          (label['name'] as String).trim(),
    ]..removeWhere((tag) => tag.isEmpty);
    final createdAt = _keepTimestamp(decoded);

    final listContent = decoded['listContent'];
    if (listContent is List && listContent.isNotEmpty) {
      final items = <ChecklistItem>[
        for (final entry in listContent)
          if (entry is Map && entry['text'] is String)
            ChecklistItem(
              text: (entry['text'] as String).trim(),
              done: entry['isChecked'] == true,
            ),
      ]..removeWhere((item) => item.text.isEmpty);
      if (items.isEmpty) return const _KeepOutcome.attachmentOnly();
      return _KeepOutcome.note(
        ImportedNote(
          type: NoteType.checklist,
          text: formatChecklist(items),
          items: items,
          title: title == null || title.isEmpty ? null : title,
          tags: tags,
          createdAt: createdAt,
        ),
      );
    }

    final body = (decoded['textContent'] as String?)?.trim() ?? '';
    if (body.isEmpty) {
      // A titled note with no body is still a note — a one-line reminder
      // someone typed into the title field, which Keep encourages. A note with
      // neither is the attachment-only case.
      if (title != null && title.isNotEmpty) {
        return _KeepOutcome.note(
          ImportedNote(
            type: NoteType.text,
            text: title,
            tags: tags,
            createdAt: createdAt,
          ),
        );
      }
      return const _KeepOutcome.attachmentOnly();
    }
    return _KeepOutcome.note(
      ImportedNote(
        type: NoteType.text,
        text: body,
        title: title == null || title.isEmpty ? null : title,
        tags: tags,
        createdAt: createdAt,
      ),
    );
  }

  /// Keep writes microseconds since the epoch, in a field named for the last
  /// *edit*. That is the only timestamp in the export, so it stands in for
  /// both — better than dating every imported note to the day it was imported.
  static DateTime? _keepTimestamp(Map<Object?, Object?> json) {
    for (final key in const [
      'createdTimestampUsec',
      'userEditedTimestampUsec',
    ]) {
      final value = json[key];
      final micros = value is int
          ? value
          : value is String
          ? int.tryParse(value)
          : null;
      if (micros == null || micros <= 0) continue;
      final at = DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
      // A clock that says 1971 or 2200 is a unit mismatch, not a note from
      // the future. Importing one would sort the whole library around it.
      if (at.year < 1990 || at.year > DateTime.now().year + 1) continue;
      return at;
    }
    return null;
  }

  static ImportedNote? _readMarkdown(String filename, String source) {
    final body = source.trim();
    if (body.isEmpty) return null;

    // A markdown file whose every non-empty line is a task line is a
    // checklist, not a text note that happens to contain brackets. Nex's own
    // export writes them exactly this way, so its archives round-trip.
    final lines = body.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final taskLine = RegExp(r'^\s*[-*]\s*\[[ xX]\]');
    if (lines.length > 1 && lines.every(taskLine.hasMatch)) {
      final items = parseChecklist(body);
      if (items.isNotEmpty) {
        return ImportedNote(
          type: NoteType.checklist,
          text: formatChecklist(items),
          items: items,
          title: _titleFrom(filename),
        );
      }
    }
    return ImportedNote(
      type: NoteType.text,
      text: body,
      title: _titleFrom(filename),
    );
  }

  /// The filename, as a person would read it.
  ///
  /// Null when it carries no information — `note-1730000000000.md` is a
  /// timestamp, not a name, and putting it on the note makes the timeline
  /// worse rather than better.
  static String? _titleFrom(String filename) {
    var base = filename.split('/').last;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    base = base.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    if (base.isEmpty) return null;
    if (RegExp(r'^[\d\s]+$').hasMatch(base)) return null;
    return base;
  }
}

/// What one JSON file turned out to be.
///
/// A tagged result rather than a nullable note, because "not a note" has three
/// different meanings here and the counts shown to the user depend on telling
/// them apart: a note the owner already deleted, a note that was only a photo,
/// and a file that was never a note at all.
enum _Outcome { note, trashed, attachmentOnly, notKeep }

class _KeepOutcome {
  const _KeepOutcome._(this.outcome, [this.note]);

  const _KeepOutcome.note(ImportedNote note) : this._(_Outcome.note, note);
  const _KeepOutcome.trashed() : this._(_Outcome.trashed);
  const _KeepOutcome.attachmentOnly() : this._(_Outcome.attachmentOnly);
  const _KeepOutcome.notKeep() : this._(_Outcome.notKeep);

  final _Outcome outcome;
  final ImportedNote? note;
}
