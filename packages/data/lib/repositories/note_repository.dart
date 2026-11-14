import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../schema/backup_archive.dart';
import '../schema/database.dart';
import 'attachment_repository.dart';
import '../schema/write_lock.dart';
import '../search/vector_index.dart';
import '../schema/zip_file_writer.dart';

/// Suggested starter tags (FR-3.3) — offered, never enforced.
const List<String> suggestedStarterTags = [
  'Idea',
  'Work',
  'Shopping',
  'Learning',
  'Inspiration',
];

/// The suggested tag accent swatches (ADR-021 / design mockup accents).
///
/// Offered first in the colour picker, not enforced: the palette used to be the
/// only colours a tag could take, which meant a user could not encode their own
/// meaning — the very thing ADR-021 says the colour exists for. Any valid
/// `#RRGGBB` is accepted now; these are simply the ones that ship.
const List<String> tagAccentPalette = [
  '#F0A93B',
  '#5B9BF0',
  '#F17FA0',
  '#2FBF8F',
  '#B49AE0',
];

/// The colours a new tag is given when nobody picked one: the five starter
/// swatches first, then seven more hues spaced between them.
///
/// Five alone ran out fast. A library with a dozen tags had every colour two
/// or three times over, so colour stopped telling tags apart — which is the
/// only thing it is for. Mid tones, so they read as *dots on the dark card*
/// (4.8–8:1) and are recognisable at a glance on the light one — where
/// several sit in the 1.8–3:1 band. That is the ADR-021 trade-off: the dot is
/// a recognition aid only, never the carrier of the tag's name, and it is
/// the name that has to carry the information. The picker still offers the
/// five as its starters.
const List<String> tagAutoPalette = [
  ...tagAccentPalette,
  '#E8684A', // coral
  '#3FB6D0', // cyan
  '#9CC44A', // lime
  '#7C83E8', // indigo
  '#D46BD0', // orchid
  '#D9B23A', // mustard
  '#5DB06A', // leaf
];

final _accentRandom = Random();

/// The colour for a new tag nobody coloured: one of the least used in
/// [tagAutoPalette] among [inUse], so colours repeat only once every one of
/// them has been used, and evenly after that. A random pick among the tied
/// ones, so two libraries do not colour their tags in the same order.
String pickTagAccent(Iterable<String?> inUse) {
  final counts = {for (final hex in tagAutoPalette) hex.toUpperCase(): 0};
  for (final color in inUse) {
    final key = color?.toUpperCase();
    if (key != null && counts.containsKey(key)) counts[key] = counts[key]! + 1;
  }
  final least = counts.values.reduce((a, b) => a < b ? a : b);
  final options = [
    for (final hex in tagAutoPalette)
      if (counts[hex.toUpperCase()] == least) hex,
  ];
  return options[_accentRandom.nextInt(options.length)];
}

/// Whether a string is a colour a tag may carry: `#RRGGBB`, case-insensitive.
bool isTagAccent(String value) => RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value);

/// What came out of reading an export archive back in.
///
/// [skipped] is not an error: importing the same archive twice should leave the
/// library exactly as it was, and the count is how the UI says so rather than
/// claiming it added notes it did not.
class ImportResult {
  const ImportResult({required this.imported, required this.skipped});

  final int imported;
  final int skipped;
}

// newUuidV7, sha256OfBytes and sha256OfFile moved to packages/core (ids.dart):
// they depend only on uuid and crypto, and keeping them here forced core's
// capture service to import the storage layer just to mint an id.

/// SQLite-backed implementation of the [NoteRepository] port.
///
/// Named for its storage engine because the port it implements owns the plain
/// name. Every method is synchronous — package:sqlite3 is a synchronous FFI
/// binding — so this class is only ever constructed **inside** the database
/// isolate. `NexDbWorker` is what the UI isolate talks to.
class SqliteNoteRepository implements NoteRepository {
  SqliteNoteRepository(this._db, {this.localDeviceId, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// Clock for content edits and embedding snapshots; injectable in tests.
  final DateTime Function() _now;

  final NexDatabase _db;

  /// When set, local mutations stamp this as `device_id` (sync concurrency).
  final String? localDeviceId;

  Database get db => _db.db;

  /// Each category gets its own small budget; an old quiet library is not
  /// mistaken for an empty one. No media, private-vault content or AI calls.
  NexNudgeSnapshot nudgeSnapshot(List<NexCommitment> commitments) {
    final candidates = <String, Note>{};
    final now = DateTime.now().toUtc();
    final categories = [
      (where: 'is_urgent = 1', order: 'updated_at DESC', args: <Object?>[]),
      // A repeat's stored start can be years old. Keep a separate budget so
      // old one-off reminders cannot hide either repeats or the nearest due.
      (
        where: "due_at IS NOT NULL AND due_repeat != 'once'",
        order: 'updated_at DESC',
        args: <Object?>[],
      ),
      (
        where: "due_at BETWEEN ? AND ? AND (due_repeat IS NULL OR due_repeat = 'once')",
        order: 'ABS(julianday(due_at) - julianday(?))',
        args: <Object?>[
          now.subtract(const Duration(days: 7)).toIso8601String(),
          now.add(const Duration(days: 33)).toIso8601String(),
          now.toIso8601String(),
        ],
      ),
      (
        where: "type = 'checklist'",
        order: 'updated_at DESC',
        args: <Object?>[],
      ),
    ];
    for (final category in categories) {
      for (final row in db.select(
        'SELECT * FROM notes WHERE deleted_at IS NULL '
        'AND (set_aside_at IS NULL OR set_aside_until IS NOT NULL) '
        'AND (${category.where}) ORDER BY ${category.order} LIMIT 60',
        category.args,
      )) {
        final note = Note.fromRow(row);
        candidates[note.id] = note;
      }
    }
    final hasData =
        commitments.isNotEmpty ||
        db
                .select(
                  'SELECT EXISTS(SELECT 1 FROM notes) '
                  'OR EXISTS(SELECT 1 FROM scheduled_notes) '
                  'OR EXISTS(SELECT 1 FROM module_records) AS present',
                )
                .first['present'] ==
            1;
    final revision = db
        .select(
          'SELECT COUNT(*) AS count, COALESCE(SUM(rev), 0) AS revision, '
          'MAX(updated_at) AS latest, (SELECT MAX(updated_at) FROM module_records) AS modules '
          'FROM notes WHERE deleted_at IS NULL',
        )
        .first
        .values
        .join('|');
    return NexNudgeSnapshot(
      notes: candidates.values.toList(),
      commitments: commitments,
      hasData: hasData,
      revision: revision,
      memories: _nudgeMemories(DateTime.now()),
    );
  }

  /// How many years back "on this day" looks.
  static const nudgeMemoryYears = 5;

  /// The days around today each earlier year is read for: two behind, so a
  /// calendar whose year is not the Gregorian one can still find its own
  /// anniversary a day either side, and a fortnight ahead, which is as far as
  /// the daily nudge plans a memory before the app is next opened.
  static const nudgeMemoryDaysBehind = 2;
  static const nudgeMemoryDaysAhead = 16;

  /// Notes with words of their own, written near this time of year in each of
  /// the last [nudgeMemoryYears] years: at most two a day, the longest first.
  ///
  /// One narrow range read of `idx_notes_created_at` per day rather than one
  /// read of the whole window — a busy month is thousands of rows, and a
  /// notification quotes one.
  /// Public only so a test can pin its query plan. Held to the creation
  /// index by name: the planner otherwise prefers `deleted_at IS NULL`, an
  /// equality on another index, and reads every live note once per day asked.
  static const nudgeMemoriesSql =
      'SELECT * FROM notes INDEXED BY idx_notes_created_at '
      'WHERE created_at >= ? AND created_at < ? '
      'AND deleted_at IS NULL AND set_aside_at IS NULL '
      "AND type IN ('text', 'photo', 'voice') "
      "AND length(trim(coalesce(title, '') || coalesce(content, '') || "
      "coalesce(caption, ''))) > 0 "
      "ORDER BY length(coalesce(content, '')) DESC LIMIT 2";

  List<Note> _nudgeMemories(DateTime now) {
    final statement = db.prepare(nudgeMemoriesSql);
    try {
      final found = <Note>[];
      for (var years = 1; years <= nudgeMemoryYears; years++) {
        for (
          var day = -nudgeMemoryDaysBehind;
          day <= nudgeMemoryDaysAhead;
          day++
        ) {
          // Local midnights: "that day" is the day it was where it was
          // written, as nearly as this device's zone can say.
          final from = DateTime(now.year - years, now.month, now.day + day);
          final to = DateTime(now.year - years, now.month, now.day + day + 1);
          for (final row in statement.select([
            from.toUtc().toIso8601String(),
            to.toUtc().toIso8601String(),
          ])) {
            found.add(Note.fromRow(row));
          }
        }
      }
      return found;
    } finally {
      statement.close();
    }
  }

  /// Commits the note and its delivery receipt together. Re-delivery after an
  /// engine restart or a lost platform acknowledgement cannot create a copy.
  Note? captureShared(Map<String, String> payload) {
    final requestId = payload['requestId'];
    if (requestId == null || requestId.isEmpty) {
      throw ArgumentError('A shared capture requires a request id');
    }
    db.beginImmediate();
    try {
      final receipt = db.select(
        'SELECT note_id FROM capture_receipts WHERE request_id = ?',
        [requestId],
      );
      if (receipt.isNotEmpty) {
        final note = getById(receipt.first['note_id'] as String);
        db.execute('COMMIT');
        return note;
      }
      final capture = CaptureService(this, deviceId: localDeviceId!);
      var note = switch (payload['type']) {
        // A browser shares a page as text. A share that is a link is
        // captured as a link note, with any words around it as its caption.
        // Not a recovered draft (`draft-`), which is text the person typed
        // into a text note and stays one.
        'shared_text' => switch (requestId.startsWith('draft-')
            ? null
            : sharedLink(payload['text'] ?? '')) {
          final link? => _sharedLinkNote(capture, link.url, link.words),
          null => capture.submitTextCapture(payload['text'] ?? ''),
        },
        // The capture sheet's words become a list when it closes. Routed
        // through here rather than `captureChecklist` so the receipt covers
        // it: a close that was interrupted after the commit used to make a
        // second, identical list when it was tried again — the same
        // protection `link-` requests already had, given to the one kind
        // that was left without it.
        'checklist' => capture.submitChecklistCapture(
          parseChecklist(payload['body'] ?? ''),
        ),
        'shared_photo' => capture.submitPhotoCapture(
          mediaUri: payload['mediaUri']!,
          mediaHash: payload['mediaHash']!,
        ),
        'shared_file' => capture.submitFileCapture(
          mediaUri: payload['mediaUri']!,
          mediaHash: payload['mediaHash']!,
          originalFilename: payload['filename'],
          mimeType: payload['mimeType'],
        ),
        _ => throw ArgumentError('Unsupported shared capture'),
      };
      // The words another app sent with the file — Telegram's or WhatsApp's
      // caption under a video or a photo — are the note's caption, in the
      // same transaction, so the note never exists without them.
      final words = payload['caption']?.trim();
      if (note != null &&
          words != null &&
          words.isNotEmpty &&
          payload['type'] != 'shared_text') {
        setCaption(note.id, words);
        note = getById(note.id);
      }
      if (note == null) {
        if (requestId.startsWith('draft-')) {
          db.execute('COMMIT');
          return null;
        }
        throw ArgumentError('Empty shared capture');
      }
      db.execute('INSERT INTO capture_receipts VALUES (?, ?)', [
        requestId,
        note.id,
      ]);
      db.execute('COMMIT');
      return note;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// The note a share request already became, or null when it has not
  /// committed. A capture whose answer was lost — the window closed, a step
  /// after the commit failed — is a saved capture, not a failed one.
  Note? capturedFor(String requestId) {
    final receipt = db.select(
      'SELECT note_id FROM capture_receipts WHERE request_id = ?',
      [requestId],
    );
    if (receipt.isEmpty) return null;
    return getById(receipt.first['note_id'] as String);
  }

  Note? _sharedLinkNote(CaptureService capture, String url, String? words) {
    final note = capture.submitLinkCapture(url);
    if (note == null || words == null) return note;
    setCaption(note.id, words);
    return getById(note.id);
  }

  @override
  Note insert(Note note) {
    return db.together(() {
      db.execute(
        '''
INSERT INTO notes (
  id, type, content, media_uri, media_hash, duration_ms,
  created_at, updated_at, deleted_at, device_id, rev, sync_state,
  caption, title, link_excerpt, mime_type, is_urgent
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
        [
          note.id,
          note.type.wireName,
          note.content,
          note.mediaUri,
          note.mediaHash,
          note.durationMs,
          note.createdAt.toUtc().toIso8601String(),
          note.updatedAt.toUtc().toIso8601String(),
          note.deletedAt?.toUtc().toIso8601String(),
          note.deviceId,
          note.rev,
          note.syncState.wireName,
          note.caption,
          note.title,
          note.linkExcerpt,
          note.mimeType,
          note.isUrgent ? 1 : 0,
        ],
      );
      final searchable = note.searchableDerivedText;
      if (searchable != null && searchable.isNotEmpty) {
        _upsertFts(note.id, searchable);
      }
      return getById(note.id)!;
    });
  }

  void updateContent(String noteId, String content) {
    db.together(() {
      final now = _now().toUtc().toIso8601String();
      db.execute(
        '''
UPDATE notes
SET content = ?, updated_at = ?, rev = rev + 1, sync_state = 'pending'
    ${localDeviceId != null ? ', device_id = ?' : ''}
WHERE id = ? AND deleted_at IS NULL
''',
        [content, now, if (localDeviceId != null) localDeviceId, noteId],
      );
      // Re-derived from the whole note, not the raw body: a note with a title
      // used to drop the title from its search row here, and a checklist got
      // its `[x]` markers indexed. Every FTS writer goes through [_reindex].
      _reindex(noteId);
    });
  }

  /// Changes representation in place: tags, reminders, title and identity survive.
  ///
  /// With [uri], a text note becomes the Markdown file at that path — the
  /// only file a note is ever turned into. Without it, a file note becomes a
  /// text note holding [text]: any file the app could read words out of
  /// (see the client's `NexTextImport`), not only Markdown. The file itself is
  /// left on disk for library maintenance, exactly as before.
  void convertMarkdown(String id, String text, String? uri, String? hash) {
    final note = getById(id);
    final toFile = uri != null;
    if (note == null ||
        (toFile ? note.type != NoteType.text : note.type != NoteType.file)) {
      throw StateError('Invalid Markdown conversion');
    }
    db.beginImmediate();
    try {
      db.execute(
        """
UPDATE notes SET type = ?, content = ?, media_uri = ?, media_hash = ?, mime_type = ?,
  ocr_text = ?, transcript_text = NULL, summary_text = NULL,
  updated_at = ?, rev = rev + 1, sync_state = 'pending'
  ${localDeviceId != null ? ', device_id = ?' : ''}
WHERE id = ? AND deleted_at IS NULL
""",
        [
          toFile ? 'file' : 'text',
          toFile ? markdownFileNameFor(text) : text,
          uri,
          hash,
          toFile ? 'text/markdown' : null,
          toFile ? text : null,
          DateTime.now().toUtc().toIso8601String(),
          if (localDeviceId != null) localDeviceId,
          id,
        ],
      );
      _forgetEmbedding(id);
      _reindex(id);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Replaces the media of an existing image note. The old file is left in
  /// place until library maintenance can verify that no note references it.
  void updateImageMedia(String noteId, String mediaUri, String mediaHash) {
    final note = getById(noteId);
    if (note == null ||
        (note.type != NoteType.photo &&
            !(note.type == NoteType.file &&
                NexFileKinds.of(path: note.mediaUri, mimeType: note.mimeType) ==
                    NexFileKind.image))) {
      throw StateError('Only an existing image note can be edited');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    db.beginImmediate();
    try {
      db.execute(
        '''
UPDATE notes
SET media_uri = ?, media_hash = ?, mime_type = ?,
    ocr_text = NULL, summary_text = NULL, updated_at = ?,
    rev = rev + 1, sync_state = 'pending'
    ${localDeviceId != null ? ', device_id = ?' : ''}
WHERE id = ? AND deleted_at IS NULL
''',
        [
          mediaUri,
          mediaHash,
          p.extension(mediaUri).toLowerCase() == '.jpg'
              ? 'image/jpeg'
              : 'image/png',
          now,
          if (localDeviceId != null) localDeviceId,
          noteId,
        ],
      );
      _forgetEmbedding(noteId);
      _reindex(noteId);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Pins [noteId] while keeping the five-item home-screen limit atomic.
  /// Touches only `pinned_at`: this is local device state, not a change worth
  /// pushing to sync. Returns false when five other notes already hold pins.
  bool pinNote(String noteId) {
    final now = DateTime.now().toUtc().toIso8601String();
    db.beginImmediate();
    try {
      final existing = db.select(
        'SELECT pinned_at FROM notes WHERE id = ? AND deleted_at IS NULL',
        [noteId],
      );
      if (existing.isEmpty) {
        db.execute('ROLLBACK');
        return false;
      }
      if (existing.first['pinned_at'] != null) {
        db.execute('COMMIT');
        return true;
      }
      if (pinnedNoteCount() >= 5) {
        db.execute('ROLLBACK');
        return false;
      }
      db.execute('UPDATE notes SET pinned_at = ? WHERE id = ?', [now, noteId]);
      db.execute('COMMIT');
      return true;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Existence across the entire home timeline, including unloaded pages.
  bool hasUntaggedTimelineNotes() =>
      db.select(
        'SELECT EXISTS(SELECT 1 FROM notes n '
        'WHERE n.deleted_at IS NULL AND $_notSetAside '
        'AND NOT EXISTS(SELECT 1 FROM note_tags nt JOIN tags t ON t.id = nt.tag_id '
        'WHERE nt.note_id = n.id)) AS found',
        [DateTime.now().toUtc().toIso8601String()],
      ).first['found'] ==
      1;

  /// Exact live counts, including set-aside notes, without reading content.
  Map<String, int> libraryNoteCounts() => {
    for (final type in NoteType.values) type.wireName: 0,
    for (final row in db.select(
      'SELECT type, COUNT(*) AS n FROM notes WHERE deleted_at IS NULL GROUP BY type',
    ))
      row['type'] as String: row['n'] as int,
  };

  void unpinNote(String noteId) =>
      db.execute('UPDATE notes SET pinned_at = NULL WHERE id = ?', [noteId]);

  /// Local metadata only: keep timestamps, ordering, content and Pin intact.
  void setUrgent(String noteId, bool urgent) => db.execute(
    'UPDATE notes SET is_urgent = ? WHERE id = ? AND deleted_at IS NULL',
    [urgent ? 1 : 0, noteId],
  );

  int pinnedNoteCount() =>
      db
              .select(
                'SELECT COUNT(*) AS count FROM notes WHERE pinned_at IS NOT NULL AND deleted_at IS NULL',
              )
              .first['count']
          as int;

  /// The SQL term that keeps a note off the home timeline while it is set
  /// aside, with one `?` for "now". A note whose return time has passed counts
  /// as back whether or not [releaseDueSetAside] has cleared its columns yet.
  static const _notSetAside =
      '(set_aside_at IS NULL OR '
      '(set_aside_until IS NOT NULL AND set_aside_until <= ?))';

  /// Puts [noteId] to one side: off the home timeline, still searchable, still
  /// carrying its reminder and its place in every backup. Returns false when
  /// there is no such live note, or when [until] is not in the future.
  ///
  /// Touches only the two `set_aside_*` columns (and drops a pin): this is
  /// where *this device* shows a note, not a change worth syncing — the same
  /// reasoning as [pinNote]. A pinned note gives up its pin, so a hidden note
  /// never holds one of the five slots on a home screen it is not on.
  bool setAside(String noteId, {DateTime? until}) {
    final now = DateTime.now().toUtc();
    if (until != null && !until.toUtc().isAfter(now)) return false;
    db.beginImmediate();
    try {
      final existing = db.select(
        'SELECT id FROM notes WHERE id = ? AND deleted_at IS NULL',
        [noteId],
      );
      if (existing.isEmpty) {
        db.execute('ROLLBACK');
        return false;
      }
      db.execute(
        'UPDATE notes SET set_aside_at = ?, set_aside_until = ?, '
        'pinned_at = NULL WHERE id = ?',
        [now.toIso8601String(), until?.toUtc().toIso8601String(), noteId],
      );
      db.execute('COMMIT');
      return true;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Brings [noteId] back onto the home timeline, or does nothing if it was
  /// not set aside.
  void bringBack(String noteId) => db.execute(
    'UPDATE notes SET set_aside_at = NULL, set_aside_until = NULL '
    'WHERE id = ?',
    [noteId],
  );

  /// Every note currently set aside, the ones due back first, then the ones
  /// that have waited longest — the order a person looking for something to
  /// bring back would want. Notes with no return time come after those that
  /// have one.
  List<Note> listSetAside({int limit = 500}) {
    final rows = db.select(
      '''
SELECT n.* FROM notes n
WHERE n.deleted_at IS NULL
  AND n.set_aside_at IS NOT NULL
  AND (n.set_aside_until IS NULL OR n.set_aside_until > ?)
ORDER BY (n.set_aside_until IS NULL), n.set_aside_until, n.set_aside_at DESC,
  n.rowid DESC
LIMIT ?
''',
      [DateTime.now().toUtc().toIso8601String(), limit],
    );
    return _withTags(rows);
  }

  int setAsideCount() =>
      db.select(
            'SELECT COUNT(*) AS count FROM notes '
            'WHERE deleted_at IS NULL AND set_aside_at IS NOT NULL '
            'AND (set_aside_until IS NULL OR set_aside_until > ?)',
            [DateTime.now().toUtc().toIso8601String()],
          ).first['count']
          as int;

  /// Clears the set-aside columns of every note whose return time has come,
  /// and returns their ids so the caller can say "3 notes are back".
  List<String> releaseDueSetAside() {
    final now = DateTime.now().toUtc().toIso8601String();
    final due = [
      for (final row in db.select(
        'SELECT id FROM notes WHERE set_aside_at IS NOT NULL '
        'AND set_aside_until IS NOT NULL AND set_aside_until <= ?',
        [now],
      ))
        row['id']! as String,
    ];
    if (due.isEmpty) return const [];
    db.execute(
      'UPDATE notes SET set_aside_at = NULL, set_aside_until = NULL '
      'WHERE set_aside_at IS NOT NULL AND set_aside_until IS NOT NULL '
      'AND set_aside_until <= ?',
      [now],
    );
    return due;
  }

  /// Leaves `updated_at` alone, for the reason spelled out on [_bumpNote]:
  /// it is what the timeline sorts on, so it means "when this note last said
  /// something different". Deleting a note does not change what it says, and
  /// the pair of timestamps that used to move here is what sent an undone
  /// delete to the top of the list wearing a "now" badge — the note came back
  /// somewhere it had never been. `deleted_at` is the delete's own timestamp
  /// and Trash sorts on that, so nothing needed the edit clock.
  ///
  /// Sync is unaffected: `rev` and `sync_state` still move, and
  /// the merger decides a delete in its tombstone branch — which is
  /// reached before any timestamp is compared — so a delete never needed a
  /// newer `updated_at` to win.
  void softDelete(String noteId) {
    db.together(() {
      final now = DateTime.now().toUtc().toIso8601String();
      db.execute(
        '''
UPDATE notes
SET deleted_at = ?, rev = rev + 1, sync_state = 'pending'
    ${localDeviceId != null ? ', device_id = ?' : ''}
WHERE id = ?
''',
        [now, if (localDeviceId != null) localDeviceId, noteId],
      );
      deleteSearchRow(noteId);
    });
  }

  /// Undo a soft-delete within the toast window (FR-2.6).
  ///
  /// Undo means undo: the note comes back exactly where it was, keeping the
  /// `updated_at` [softDelete] deliberately did not touch. Restoring it to
  /// the top of the timeline instead was the visible half of the same bug —
  /// the row was newer than the note, so the list put it first and the card
  /// said it had just been written.
  void undelete(String noteId) {
    db.together(() {
      final rows = db.select('SELECT * FROM notes WHERE id = ?', [noteId]);
      if (rows.isEmpty) return;
      db.execute(
        '''
UPDATE notes
SET deleted_at = NULL, rev = rev + 1, sync_state = 'pending'
    ${localDeviceId != null ? ', device_id = ?' : ''}
WHERE id = ?
''',
        [if (localDeviceId != null) localDeviceId, noteId],
      );
      // Re-derived from the whole restored row, not just the text body: a
      // checklist, a voice note with its transcript, a photo with OCR text and
      // a link with its excerpt all leave the trash searchable again — before
      // this, only plain text came back findable.
      _reindex(noteId);
    });
  }

  @override
  Note? getById(String id, {bool includeDeleted = false}) {
    final rows = db.select(
      '''
SELECT * FROM notes
WHERE id = ?
  ${includeDeleted ? '' : 'AND deleted_at IS NULL'}
''',
      [id],
    );
    if (rows.isEmpty) return null;
    return Note.fromRow(
      rows.first,
      tags: tagsForNote(id),
      attachmentCount: attachmentCounts([id])[id] ?? 0,
    );
  }

  /// Timeline page, most recently touched first (FR-2.2 / FR-2.5).
  ///
  /// Ordered by `updated_at`, not `created_at`: editing a note's content,
  /// caption or tags bumps it, and a note you just changed belongs at the
  /// top of what you are looking at, not wherever it was originally written.
  ///
  /// Pinned notes (at most five) always lead. Behind them, notes nobody has
  /// manually placed sort by recency same as ever; notes that *have* been
  /// dragged into place in Rearrange mode follow, in that manual order —
  /// which is why a fresh capture still surfaces at the top instead of
  /// waiting at the bottom of an arrangement it was never part of.
  ///
  /// When [tagId] is set, only notes with that tag are returned (Timeline
  /// filter chips / FR-4).
  @override
  List<Note> listTimeline({int limit = 50, int offset = 0, String? tagId}) {
    // Pinned first, then newest. `sort_order` is deliberately absent: manual
    // arrangement is gone, and the timeline is grouped by date on screen —
    // Today, Yesterday, Last week — which only reads as a history if the rows
    // under each heading actually belong to it. A hand-placed note would drop
    // into whichever group it landed next to and make the heading a lie.
    //
    // The column stays. Dropping it means a migration on every existing
    // database to remove something that now simply goes unread.
    //
    // `rowid` breaks ties, in the order the notes were written. Without it two
    // notes with the same `updated_at` — two files shared at once, an import,
    // or simply two captures inside one tick of a coarse clock — came back in
    // whatever order SQLite happened to produce, and could swap places between
    // one read and the next. An independent audit saw it as a test that failed
    // on Windows and passed on rerun: Windows' clock ticks coarsely enough that
    // two captures a line apart often share a timestamp.
    final nowIso = DateTime.now().toUtc().toIso8601String();
    // Dart omits zero microseconds: .123Z sorts above the later .123024Z
    // as plain text. Pad UTC fractions for ordering, including existing pins.
    const order = '''
ORDER BY
  (pinned_at IS NOT NULL) DESC,
  substr(replace(pinned_at, 'Z', '000000'), 1, 26) DESC,
  updated_at DESC,
  n.rowid DESC
''';
    final rows = tagId == null
        ? db.select(
            // Aliased like the tagged query below, because the tie-break has
            // to name `n.rowid`: in that one `note_tags` has a rowid too, and
            // a bare `rowid` in a join is ambiguous.
            '''
SELECT n.* FROM notes n
WHERE deleted_at IS NULL
  AND $_notSetAside
$order
LIMIT ? OFFSET ?
''',
            [nowIso, limit, offset],
          )
        : db.select(
            '''
SELECT n.* FROM notes n
INNER JOIN note_tags nt ON nt.note_id = n.id
WHERE n.deleted_at IS NULL AND nt.tag_id = ?
  AND $_notSetAside
$order
LIMIT ? OFFSET ?
''',
            [tagId, nowIso, limit, offset],
          );
    return _withTags(rows);
  }

  /// Notes for [rows], with their tags read in one query rather than one per
  /// note (PERF-06). The batch keeps each note's tags in the same order
  /// [tagsForNote] gives them.
  List<Note> _withTags(ResultSet rows) {
    final ids = [for (final r in rows) r['id']! as String];
    final tags = tagsForNotes(ids);
    final attached = attachmentCounts(ids);
    return [
      for (final r in rows)
        Note.fromRow(
          r,
          tags: tags[r['id']! as String] ?? const [],
          attachmentCount: attached[r['id']! as String] ?? 0,
        ),
    ];
  }

  /// How many live attachments each of [noteIds] has, in one query per 500.
  /// Notes with none are left out.
  Map<String, int> attachmentCounts(List<String> noteIds) {
    final out = <String, int>{};
    for (var at = 0; at < noteIds.length; at += 500) {
      final chunk = noteIds.sublist(
        at,
        at + 500 > noteIds.length ? noteIds.length : at + 500,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      for (final row in db.select('''
SELECT note_id, COUNT(*) AS n FROM note_attachments
WHERE deleted_at IS NULL AND note_id IN ($placeholders)
GROUP BY note_id
''', chunk)) {
        out[row['note_id']! as String] = row['n']! as int;
      }
    }
    return out;
  }

  /// The tags of every note in [noteIds], in one query rather than one each.
  Map<String, List<Tag>> tagsForNotes(List<String> noteIds) {
    final out = <String, List<Tag>>{for (final id in noteIds) id: <Tag>[]};
    for (var at = 0; at < noteIds.length; at += 500) {
      final chunk = noteIds.sublist(
        at,
        at + 500 > noteIds.length ? noteIds.length : at + 500,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      for (final row in db.select('''
SELECT nt.note_id AS owner, t.* FROM tags t
INNER JOIN note_tags nt ON nt.tag_id = t.id
WHERE nt.note_id IN ($placeholders)
ORDER BY t.name COLLATE NOCASE
''', chunk)) {
        out[row['owner']! as String]!.add(Tag.fromRow(row));
      }
    }
    return out;
  }

  List<Tag> tagsForNote(String noteId) {
    final rows = db.select(
      '''
SELECT t.* FROM tags t
INNER JOIN note_tags nt ON nt.tag_id = t.id
WHERE nt.note_id = ?
ORDER BY t.name COLLATE NOCASE
''',
      [noteId],
    );
    return rows.map(Tag.fromRow).toList();
  }

  @override
  Tag upsertTag({required String name, String? color}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('tag name must not be empty');
    }
    if (color != null && !isTagAccent(color)) {
      throw ArgumentError.value(color, 'color', 'not a #RRGGBB colour');
    }
    final existing = db.select(
      'SELECT * FROM tags WHERE name = ? COLLATE NOCASE',
      [trimmed],
    );
    if (existing.isNotEmpty) {
      // A colour already chosen is never overwritten. It belongs to the tag,
      // decided in the tag manager — not to whichever note was most recently
      // tagged with it. Re-adding "Shopping" in blue to a second note used to
      // repaint every note already carrying the red one.
      //
      // A tag that has no colour yet may still take its first one here, so a
      // seeded starter tag is not stuck colourless forever. Changing an
      // existing colour is `setTagColor`, and it is explicit.
      final id = existing.first['id'];
      if (color != null && existing.first['color'] == null) {
        db.execute(
          "UPDATE tags SET color = ?, sync_state = 'pending' WHERE id = ?",
          [color, id],
        );
      }
      return Tag.fromRow(
        db.select('SELECT * FROM tags WHERE id = ?', [id]).first,
      );
    }
    final tag = Tag(
      id: newUuidV7(),
      name: trimmed,
      // A brand new tag with nobody having picked a colour for it yet still
      // gets one — a random pick off the same starter palette the colour
      // picker offers first — rather than sitting grey until somebody
      // opens the tag manager. `setTagColor` remains the explicit way back
      // to no colour at all.
      color:
          color ??
          pickTagAccent([
            for (final row in db.select('SELECT color FROM tags'))
              row['color'] as String?,
          ]),
      createdAt: DateTime.now().toUtc(),
    );
    db.execute(
      'INSERT INTO tags (id, name, color, created_at) VALUES (?, ?, ?, ?)',
      [tag.id, tag.name, tag.color, tag.createdAt.toUtc().toIso8601String()],
    );
    return tag;
  }

  @override
  void attachTag({required String noteId, required String tagId}) {
    // The tag and the note's sync stamp together: apart, a process killed
    // between them left a tag the outbox would never send (DATA-06).
    db.together(() {
      final present = db.select(
        'SELECT 1 FROM note_tags WHERE note_id = ? AND tag_id = ?',
        [noteId, tagId],
      );
      if (present.isNotEmpty) return;
      final count =
          db.select('SELECT COUNT(*) AS n FROM note_tags WHERE note_id = ?', [
                noteId,
              ]).first['n']!
              as int;
      if (count >= nexMaxTagsPerNote) {
        throw StateError('A note can have at most $nexMaxTagsPerNote tags.');
      }
      db.execute('INSERT INTO note_tags (note_id, tag_id) VALUES (?, ?)', [
        noteId,
        tagId,
      ]);
      // Filing, not editing: the note still says exactly what it said.
      _bumpNote(noteId, edited: false);
    });
  }

  @override
  void detachTag({required String noteId, required String tagId}) {
    db.together(() {
      db.execute('DELETE FROM note_tags WHERE note_id = ? AND tag_id = ?', [
        noteId,
        tagId,
      ]);
      _bumpNote(noteId, edited: false);
    });
  }

  @override
  List<Tag> listTags() {
    final rows = db.select('SELECT * FROM tags ORDER BY name COLLATE NOCASE');
    return rows.map(Tag.fromRow).toList();
  }

  /// Outbox: notes still pending sync (including tombstones).
  List<Note> listPending({bool includeDeleted = false}) {
    final rows = db.select('''
SELECT * FROM notes
WHERE sync_state = 'pending'
ORDER BY updated_at ASC
''');
    return _withTags(rows)
        .where((n) => includeDeleted || !n.isDeleted)
        .toList();
  }

  /// Clears a note from the outbox, adopting the server's revision.
  ///
  /// [serverRev] is not optional decoration: `rev` is server-authoritative, and
  /// a client that keeps its own number after an accepted write will push a
  /// stale revision next time and have it rejected. Only ever called for ids
  /// the server actually acknowledged — see [SyncClient].
  void markSynced(String noteId, {int? serverRev, Note? expected}) {
    if (serverRev == null) {
      db.execute("UPDATE notes SET sync_state = 'synced' WHERE id = ?", [
        noteId,
      ]);
      return;
    }
    db.execute(
      "UPDATE notes SET sync_state = 'synced', rev = ? WHERE id = ?"
      "${expected == null ? '' : ' AND rev = ? AND updated_at = ?'}",
      [
        serverRev,
        noteId,
        if (expected != null) ...[
          expected.rev,
          expected.updatedAt.toUtc().toIso8601String(),
        ],
      ],
    );
  }

  /// Outbox: tags still pending sync.
  List<Tag> listPendingTags() {
    final rows = db.select(
      "SELECT * FROM tags WHERE sync_state = 'pending' ORDER BY name COLLATE NOCASE",
    );
    return rows.map(Tag.fromRow).toList();
  }

  void markTagsSynced(Iterable<String> tagIds, {Map<String, Tag>? expected}) {
    for (final id in tagIds) {
      final tag = expected?[id];
      db.execute(
        "UPDATE tags SET sync_state = 'synced' WHERE id = ?"
        "${tag == null ? '' : ' AND name = ? AND color IS ?'}",
        [
          id,
          if (tag != null) ...[tag.name, tag.color],
        ],
      );
    }
  }

  /// Folds this device's tag ids into the ones the server made canonical.
  ///
  /// Tag identity on the server is `(user_id, lower(name))`, because two
  /// devices offline both mint a UUID for `#ideas` and only one can win. The
  /// server reports the outcome as a remap and the client used to throw it
  /// away, so the loser kept its local id forever: every push re-sent it, the
  /// server re-remapped it, and the response was discarded again — a loop that
  /// never converged, with two `#ideas` tags on screen and pulled note↔tag
  /// joins pointing at ids that did not exist locally.
  ///
  /// One transaction, and the losing row goes before the canonical one is
  /// written: `tags.name` is UNIQUE, so the two cannot coexist.
  void applyTagRemap(List<({String clientId, String canonicalId})> pairs) {
    final real = [
      for (final pair in pairs)
        if (pair.clientId != pair.canonicalId) pair,
    ];
    if (real.isEmpty) return;
    db.beginImmediate();
    try {
      for (final pair in real) {
        final losing = db.select('SELECT * FROM tags WHERE id = ?', [
          pair.clientId,
        ]);
        if (losing.isEmpty) continue;
        final row = losing.first;

        // Read the joins before touching the tag row. `note_tags.tag_id` is
        // ON DELETE CASCADE, so deleting the losing tag takes its joins with
        // it — repointing them afterwards finds nothing and the notes come out
        // untagged. They have to be carried across by hand.
        final noteIds = [
          for (final join in db.select(
            'SELECT note_id FROM note_tags WHERE tag_id = ?',
            [pair.clientId],
          ))
            join['note_id']! as String,
        ];

        // The losing row goes first: `tags.name` is UNIQUE, so the canonical
        // row cannot take the name while the loser still holds it.
        db.execute('DELETE FROM tags WHERE id = ?', [pair.clientId]);
        final existing = db.select('SELECT id FROM tags WHERE id = ?', [
          pair.canonicalId,
        ]);
        if (existing.isEmpty) {
          db.execute(
            '''
INSERT INTO tags (id, name, color, created_at, sync_state)
VALUES (?, ?, ?, ?, 'synced')
''',
            [pair.canonicalId, row['name'], row['color'], row['created_at']],
          );
        }
        for (final noteId in noteIds) {
          // OR IGNORE: a note already carrying the canonical tag would
          // otherwise violate the composite primary key.
          db.execute(
            'INSERT OR IGNORE INTO note_tags (note_id, tag_id) VALUES (?, ?)',
            [noteId, pair.canonicalId],
          );
        }
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// The pull watermark, surviving process restarts.
  ///
  /// It used to live only in a field on the sync client, so even once the
  /// field name was right every cold launch restarted the pull from sequence
  /// zero and re-downloaded the whole corpus.
  String? get syncCursor {
    final rows = db.select(
      "SELECT value FROM nex_meta WHERE key = 'sync_cursor'",
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  set syncCursor(String? value) {
    if (value == null) {
      db.execute("DELETE FROM nex_meta WHERE key = 'sync_cursor'");
      return;
    }
    db.execute(
      "INSERT INTO nex_meta (key, value) VALUES ('sync_cursor', ?) "
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [value],
    );
  }

  /// Test/helper: set content with an explicit `updated_at` (sync matrix).
  void updateContentAt(String noteId, String content, DateTime updatedAt) {
    db.together(() {
      db.execute(
        '''
UPDATE notes
SET content = ?, updated_at = ?, rev = rev + 1, sync_state = 'pending'
    ${localDeviceId != null ? ', device_id = ?' : ''}
WHERE id = ? AND deleted_at IS NULL
''',
        [
          content,
          updatedAt.toUtc().toIso8601String(),
          if (localDeviceId != null) localDeviceId,
          noteId,
        ],
      );
      // Re-derived from the whole note, as every FTS writer but this one
      // already did: upserting the raw body dropped a titled note's title,
      // its caption and the words of its attachments out of the search row,
      // so a synced edit made a note harder to find than writing it had.
      _reindex(noteId);
    });
  }

  Tag upsertTagFromSync({
    required String id,
    required String name,
    String? color,
    required DateTime createdAt,
    bool preservePending = true,
  }) {
    final existing = db.select('SELECT * FROM tags WHERE id = ?', [id]);
    if (existing.isNotEmpty) {
      if (preservePending && existing.first['sync_state'] == 'pending') {
        return Tag.fromRow(existing.first);
      }
      db.execute(
        "UPDATE tags SET name = ?, color = COALESCE(?, color), "
        "sync_state = 'synced' WHERE id = ?",
        [name, color, id],
      );
      return Tag.fromRow(
        db.select('SELECT * FROM tags WHERE id = ?', [id]).first,
      );
    }
    final byName = db.select(
      'SELECT * FROM tags WHERE name = ? COLLATE NOCASE',
      [name],
    );
    if (byName.isNotEmpty) {
      final localId = byName.first['id']! as String;
      if (localId != id) {
        // The same dance `applyTagRemap` does, and for the same two reasons —
        // this path did neither.
        //
        // It used to re-point `note_tags` at the server's id and only then
        // insert that row. `note_tags.tag_id` is a foreign key and
        // `PRAGMA foreign_keys` is ON, so the joins pointed at a row that did
        // not exist yet: `SqliteException(787)`, thrown out of `_applyPage`,
        // which rolls the page back and leaves the cursor where it was. Every
        // later sync re-fetched the same page and failed identically — the
        // device never synced again. Reachable by restoring an archive whose
        // tag shares a name with a peer's but not its id, which is the
        // ordinary case: two devices minted two ids for one name.
        //
        // And the fix cannot simply be "insert first": `tags.name` is UNIQUE,
        // so the incoming row cannot take the name while the local one still
        // holds it. The losing row has to go first — which cascades its joins
        // away, so they are carried across by hand.
        final noteIds = [
          for (final join in db.select(
            'SELECT note_id FROM note_tags WHERE tag_id = ?',
            [localId],
          ))
            join['note_id']! as String,
        ];
        db.execute('DELETE FROM tags WHERE id = ?', [localId]);
        db.execute(
          '''
INSERT INTO tags (id, name, color, created_at, sync_state)
VALUES (?, ?, ?, ?, 'synced')
''',
          [
            id,
            name,
            preservePending && byName.first['sync_state'] == 'pending'
                ? byName.first['color']
                : color ?? byName.first['color'],
            createdAt.toUtc().toIso8601String(),
          ],
        );
        if (preservePending && byName.first['sync_state'] == 'pending') {
          db.execute("UPDATE tags SET sync_state = 'pending' WHERE id = ?", [
            id,
          ]);
        }
        for (final noteId in noteIds) {
          // OR IGNORE: a note already carrying the incoming tag would
          // otherwise violate the composite primary key.
          db.execute(
            'INSERT OR IGNORE INTO note_tags (note_id, tag_id) VALUES (?, ?)',
            [noteId, id],
          );
        }
      }
      return Tag.fromRow(
        db.select('SELECT * FROM tags WHERE id = ?', [id]).first,
      );
    }
    // Straight from the server, so it is already in step with it — pushing it
    // back would mint a new sequence and re-broadcast it to every peer.
    db.execute(
      '''
INSERT INTO tags (id, name, color, created_at, sync_state)
VALUES (?, ?, ?, ?, 'synced')
''',
      [id, name, color, createdAt.toUtc().toIso8601String()],
    );
    return Tag.fromRow(
      db.select('SELECT * FROM tags WHERE id = ?', [id]).first,
    );
  }

  /// Apply a server-merged note as local truth (does not mark pending).
  void applyRemoteNote({
    required String id,
    required NoteType type,
    String? content,
    String? mediaUri,
    String? mediaHash,
    int? durationMs,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
    required String deviceId,
    required int rev,
    required List<String> tagIds,
  }) => db.together(() {
    final existing = db.select('SELECT * FROM notes WHERE id = ?', [id]);
    final pending =
        existing.isNotEmpty && existing.first['sync_state'] == 'pending';
    final localTags = pending ? tagsForNote(id) : const <Tag>[];
    if (pending) {
      final row = existing.first;
      if (row['deleted_at'] != null && deletedAt == null) {
        // A pending local deletion must not be resurrected by the pull.
        // Adopt the server baseline so its tombstone can be retried.
        db.execute('UPDATE notes SET rev = ? WHERE id = ?', [rev, id]);
        return;
      }
      if (row['deleted_at'] == null &&
          (row['content'] != content ||
              row['type'] != type.wireName ||
              row['media_uri'] != mediaUri ||
              row['media_hash'] != mediaHash ||
              row['duration_ms'] != durationMs ||
              deletedAt != null)) {
        // Preserve the entire unsent local version before accepting server
        // truth. The enclosing transaction also protects its tags/files.
        final copyId = newUuidV7();
        final columns = row.keys.toList();
        final values = [
          for (final column in columns)
            switch (column) {
              'id' => copyId,
              'rev' => 1,
              'sync_state' => 'pending',
              'pinned_at' ||
              'sort_order' ||
              'due_at' ||
              'due_repeat' ||
              'reminder_acked_at' => null,
              _ => row[column],
            },
        ];
        db.execute(
          'INSERT INTO notes (${columns.join(',')}) VALUES '
          '(${List.filled(columns.length, '?').join(',')})',
          values,
        );
        for (final tag in localTags) {
          db.execute('INSERT INTO note_tags (note_id, tag_id) VALUES (?, ?)', [
            copyId,
            tag.id,
          ]);
        }
        for (final attachment in db.select(
          'SELECT * FROM note_attachments WHERE note_id = ?',
          [id],
        )) {
          final names = attachment.keys.toList();
          db.execute(
            'INSERT INTO note_attachments (${names.join(',')}) VALUES '
            '(${List.filled(names.length, '?').join(',')})',
            [
              for (final name in names)
                switch (name) {
                  'id' => newUuidV7(),
                  'note_id' => copyId,
                  _ => attachment[name],
                },
            ],
          );
        }
        _reindex(copyId);
      }
    }
    if (existing.isEmpty) {
      db.execute(
        '''
INSERT INTO notes (
  id, type, content, media_uri, media_hash, duration_ms,
  created_at, updated_at, deleted_at, device_id, rev, sync_state
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced')
''',
        [
          id,
          type.wireName,
          content,
          mediaUri,
          mediaHash,
          durationMs,
          createdAt.toUtc().toIso8601String(),
          updatedAt.toUtc().toIso8601String(),
          deletedAt?.toUtc().toIso8601String(),
          deviceId,
          rev,
        ],
      );
    } else {
      db.execute(
        '''
UPDATE notes SET
  type = ?, content = ?, media_uri = ?, media_hash = ?, duration_ms = ?,
  created_at = ?, updated_at = ?, deleted_at = ?, device_id = ?, rev = ?,
  sync_state = 'synced'
WHERE id = ?
''',
        [
          type.wireName,
          content,
          mediaUri,
          mediaHash,
          durationMs,
          createdAt.toUtc().toIso8601String(),
          updatedAt.toUtc().toIso8601String(),
          deletedAt?.toUtc().toIso8601String(),
          deviceId,
          rev,
          id,
        ],
      );
    }
    deleteSearchRow(id);
    // Re-derived from the written row, not just the note's own derived text:
    // attachments never cross the sync wire, but they are already here from
    // an earlier page or an import, and their words — a photo's read text, a
    // clip's transcript — used to fall out of the index with every remote
    // update of the note they hang from. A tombstone re-derives to nothing
    // and stays out of the index (W2.2, DATA-08).
    _reindex(id);
    db.execute('DELETE FROM note_tags WHERE note_id = ?', [id]);
    // A remote payload can name a tag this device has never seen — a peer
    // that created the tag out of order, or a server that kept the note but
    // dropped the tag. With the foreign key on, one dangling id used to
    // throw out of this method and abort the whole applying loop (a sync
    // page, an import) at that note, permanently, every retry. A tag link
    // that cannot resolve is skipped; the note itself still arrives.
    final incomingTags = {
      ...tagIds,
      if (pending && deletedAt == null) ...localTags.map((t) => t.id),
    }.toList();
    final knownTags = <String>{};
    for (var offset = 0; offset < incomingTags.length; offset += 500) {
      final batch = incomingTags.skip(offset).take(500).toList();
      knownTags.addAll(
        db
            .select(
              'SELECT id FROM tags WHERE id IN (${List.filled(batch.length, '?').join(',')})',
              batch,
            )
            .map((row) => row['id'] as String),
      );
    }
    for (final tagId in incomingTags) {
      if (!knownTags.contains(tagId)) continue;
      db.execute(
        'INSERT OR IGNORE INTO note_tags (note_id, tag_id) VALUES (?, ?)',
        [id, tagId],
      );
    }
    if (pending &&
        deletedAt == null &&
        localTags.any((t) => !tagIds.contains(t.id))) {
      db.execute("UPDATE notes SET sync_state = 'pending' WHERE id = ?", [id]);
    }
  });

  @override
  void setTagColor({required String tagId, String? color}) {
    if (color != null && !isTagAccent(color)) {
      throw ArgumentError.value(color, 'color', 'not a #RRGGBB colour');
    }
    db.execute(
      "UPDATE tags SET color = ?, sync_state = 'pending' WHERE id = ?",
      [color, tagId],
    );
  }

  /// Persist AI transcript alongside the voice note (09-ai.md — non-destructive).
  @override
  void setTranscriptText(String noteId, String text) {
    db.together(() {
      db.execute('UPDATE notes SET transcript_text = ? WHERE id = ?', [
        text,
        noteId,
      ]);
      // Re-derived, not replaced: writing a transcript used to drop the note's
      // title and caption out of its search row.
      _reindex(noteId);
    });
  }

  /// Persist AI OCR text alongside the photo note.
  @override
  void setOcrText(String noteId, String text) {
    db.together(() {
      db.execute('UPDATE notes SET ocr_text = ? WHERE id = ?', [text, noteId]);
      _reindex(noteId);
    });
  }

  @override
  void setSummaryText(String noteId, String text) {
    db.execute('UPDATE notes SET summary_text = ? WHERE id = ?', [
      text,
      noteId,
    ]);
  }

  /// Appends explicitly accepted AI output using the current stored caption.
  /// Reading and writing together prevents a concurrent edit being overwritten.
  bool appendCaption(String noteId, String text) => db.together(() {
    final note = getById(noteId);
    final addition = text.trim();
    if (note == null || addition.isEmpty) return false;
    final before = note.caption?.trim() ?? '';
    if (before == addition || before.endsWith('\n\n$addition')) return true;
    setCaption(noteId, before.isEmpty ? addition : '$before\n\n$addition');
    return true;
  });

  /// Replaces only the caption the person actually approved replacing.
  /// The comparison and write share a transaction, so a later edit is kept.
  bool replaceCaption(
    String noteId,
    String text, {
    required String? expectedCaption,
  }) => db.together(() {
    final note = getById(noteId);
    final replacement = text.trim();
    if (note == null ||
        replacement.isEmpty ||
        note.caption != expectedCaption) {
      return false;
    }
    if (note.caption == replacement) return true;
    setCaption(noteId, replacement);
    return true;
  });

  /// Optional post-capture caption on photo/voice/file (distinct from OCR/transcript).
  void setCaption(String noteId, String? caption) {
    db.together(() {
      final now = DateTime.now().toUtc().toIso8601String();
      final trimmed = caption?.trim();
      final value = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
      db.execute(
        '''
UPDATE notes
SET caption = ?, updated_at = ?, rev = rev + 1, sync_state = 'pending'
    ${localDeviceId != null ? ', device_id = ?' : ''}
WHERE id = ? AND deleted_at IS NULL
''',
        [value, now, if (localDeviceId != null) localDeviceId, noteId],
      );
      // Re-derived through the one writer every other edit goes through:
      // this used to upsert the note's own derived text alone, so captioning
      // a note with attachments — a photo whose read text had just made it
      // findable — wiped the attachments' words out of its search row.
      _reindex(noteId);
    });
  }

  /// The note's optional headline. Empty clears it, so the same control both
  /// names a note and un-names it.
  void setTitle(String noteId, String? title) {
    db.together(() {
      final now = DateTime.now().toUtc().toIso8601String();
      final trimmed = title?.trim();
      final value = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
      db.execute(
        '''
UPDATE notes
SET title = ?, updated_at = ?, rev = rev + 1, sync_state = 'pending'
    ${localDeviceId != null ? ', device_id = ?' : ''}
WHERE id = ? AND deleted_at IS NULL
''',
        [value, now, if (localDeviceId != null) localDeviceId, noteId],
      );
      _reindex(noteId);
    });
  }

  /// A link note's fetched metadata, written together because they arrive
  /// together and either both apply or neither does.
  ///
  /// Not a user edit: the revision is bumped so the change syncs, but a null
  /// argument leaves that field alone rather than clearing it — a page that
  /// stops answering should not erase what was read from it the first time.
  void setLinkMetadata(String noteId, {String? title, String? excerpt}) {
    db.together(() {
      if (title == null && excerpt == null) return;
      final now = DateTime.now().toUtc().toIso8601String();
      db.execute(
        '''
UPDATE notes
SET title = COALESCE(?, title),
    link_excerpt = COALESCE(?, link_excerpt),
    updated_at = ?, rev = rev + 1, sync_state = 'pending'
WHERE id = ? AND deleted_at IS NULL
''',
        [title?.trim(), excerpt?.trim(), now, noteId],
      );
      _reindex(noteId);
    });
  }

  /// Ticks or unticks one line of a checklist, by position.
  ///
  /// Read-modify-write on the note's own `content`, which is where a
  /// checklist's items live (see `models/checklist.dart`) — so this rides the
  /// same revision, sync and search machinery as editing any other note body,
  /// with nothing checklist-shaped in the storage layer at all.
  ///
  /// Silently does nothing for an index that is no longer there: a stale tap
  /// from a list that changed underneath is not an error worth surfacing.
  void toggleChecklistItem(String noteId, int index) {
    final note = getById(noteId);
    if (note == null || note.type != NoteType.checklist) return;
    final items = [...note.checklistItems];
    if (index < 0 || index >= items.length) return;
    items[index] = items[index].toggled();
    updateContent(noteId, formatChecklist(items));
  }

  /// Re-derives this note's search row from whatever it now holds.
  void _reindex(String noteId) {
    final note = getById(noteId);
    // A word in the third photo finds the note: each attachment's caption,
    // OCR and transcript ride on the note's own row (docs/14-attachments.md).
    final searchable = [
      note?.searchableDerivedText,
      if (note != null) _attachmentSearchText(noteId),
    ].whereType<String>().where((s) => s.isNotEmpty).join('\n');
    if (note != null && searchable.isNotEmpty) {
      _upsertFts(noteId, searchable);
    } else {
      deleteSearchRow(noteId);
    }
  }

  String _attachmentSearchText(String noteId) => [
    for (final row in db.select(
      'SELECT caption, ocr_text, transcript_text FROM note_attachments '
      'WHERE note_id = ? AND deleted_at IS NULL ORDER BY position',
      [noteId],
    ))
      for (final key in const ['caption', 'ocr_text', 'transcript_text'])
        if (row[key] case final String text when text.trim().isNotEmpty) text,
  ].join('\n');

  /// For [SqliteAttachmentRepository]: a note's attachments changed, so its
  /// search row is re-derived and it is marked as edited, for sync and for
  /// "edited" order.
  void attachmentsChanged(String noteId) {
    _bumpNote(noteId);
    _reindex(noteId);
  }

  /// An attachment's derived words arrived — text read in a photo. Search
  /// learns them; the note is not edited, any more than its own text being
  /// read edits it.
  void attachmentTextRead(String noteId) => _reindex(noteId);

  /// Repairs the search index's *membership*: FTS rows for notes that are
  /// gone (purged, deleted) are removed, and live notes with searchable text
  /// but no row — a crash between one FTS statement and its pair, a database
  /// restored from before a fix — get their row back, derived exactly as a
  /// fresh capture would have.
  ///
  /// Runs once per open, in the database isolate. On a healthy library both
  /// queries return nothing and the cost is two set lookups; on a damaged
  /// one it is the difference between a note that is findable and one that
  /// silently is not until the next time it is edited.
  ///
  /// Version 2 (2.6.29): every writer now derives the whole search row —
  /// title, caption and attached files' text included — so libraries written
  /// by versions whose `setCaption`, `updateContentAt` and `applyRemoteNote`
  /// upserted partial rows get theirs re-derived once, on the first open
  /// after the upgrade.
  static const searchTextVersion = 2;

  /// Synchronous entry point for maintenance/tests.
  void repairSearchIndex() {
    for (final _ in _repairSearchIndexSteps()) {}
  }

  /// Startup repair yields between transactions so large libraries don't
  /// monopolize the database isolate. The version is committed only at the end.
  Future<void> repairSearchIndexInBatches() async {
    for (final _ in _repairSearchIndexSteps()) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Iterable<int> _repairSearchIndexSteps() sync* {
    // FTS rows for notes that are gone — purged, or deleted from under a
    // crash between the paired statements. Asked on docids and answered
    // with a probe of the notes' own B-tree per search row, where the
    // note_id join read each surviving note in full; the `deleted_at IS
    // NULL` arm keeps the old meaning, that a soft-deleted note's search row
    // goes with it.
    db.execute('''
DELETE FROM notes_fts WHERE rowid IN (
 SELECT f.rowid FROM notes_fts f LEFT JOIN notes n
 ON n.rowid = f.rowid AND n.deleted_at IS NULL WHERE n.rowid IS NULL
)
''');
    final version = db.select(
      "SELECT value FROM nex_meta WHERE key = 'search_text_version'",
    );
    final rebuild =
        version.isEmpty ||
        (int.tryParse('${version.first['value']}') ?? 0) < searchTextVersion;
    var cursor = '';
    while (true) {
      // Membership in docids: after `_alignFtsRowids` a search row's rowid
      // *is* its note's, so this subquery reads the docid B-tree alone —
      // where `note_id IN (SELECT note_id ...)` read every indexed word to
      // re-derive each row's label, once per batch, on every open.
      final ids = db
          .select(
            'SELECT id FROM notes WHERE deleted_at IS NULL AND id > ? '
            "${rebuild ? '' : 'AND rowid NOT IN (SELECT rowid FROM notes_fts) '}"
            'ORDER BY id LIMIT 200',
            [cursor],
          )
          .map((row) => row['id']! as String)
          .toList();
      if (ids.isEmpty) break;
      db.together(() {
        for (final id in ids) {
          _reindex(id);
        }
      });
      cursor = ids.last;
      yield ids.length;
    }
    if (rebuild) {
      db.execute(
        "INSERT OR REPLACE INTO nex_meta (key, value) VALUES ('search_text_version', ?)",
        ['$searchTextVersion'],
      );
    }
  }

  @override
  void setEmbedding(String noteId, List<double> values) {
    // An empty or directionless vector is still written — as the marker that
    // says "asked, and there is nothing" — so the note is not retried.
    final encoded = VectorCodec.encode(values);
    final now = _now().toUtc().toIso8601String();
    db.execute(
      '''
INSERT INTO note_embeddings (note_id, dims, values_json, updated_at, vec, q8, scale)
VALUES (?, ?, '', ?, ?, ?, ?)
ON CONFLICT(note_id) DO UPDATE SET
  dims = excluded.dims,
  values_json = '',
  updated_at = excluded.updated_at,
  vec = excluded.vec,
  q8 = excluded.q8,
  scale = excluded.scale
''',
      [
        noteId,
        encoded == null ? 0 : values.length,
        now,
        encoded?.vec ?? Uint8List(0),
        encoded?.q8 ?? Uint8List(0),
        encoded?.scale ?? 0.0,
      ],
    );
    final index = _vectors;
    if (index != null) {
      if (encoded == null) {
        index.remove(noteId);
      } else if (index.dims == values.length) {
        index.put(noteId, encoded.q8, encoded.scale);
      } else {
        // A different space arriving; the next search rebuilds.
        _vectors = null;
      }
      _vectorsSignature = _embeddingsSignature();
    }
  }

  /// The in-memory quantised vectors, built on the first semantic search and
  /// kept in step with every write this connection makes (W2.1).
  VectorIndex? _vectors;

  /// What the table looked like when [_vectors] last matched it. A different
  /// answer means another connection — the share window — wrote vectors,
  /// and the index is rebuilt rather than trusted.
  String? _vectorsSignature;

  String _embeddingsSignature() {
    final row = db
        .select(
          'SELECT COUNT(*) AS c, MAX(updated_at) AS m FROM note_embeddings',
        )
        .first;
    return '${row['c']}|${row['m']}';
  }

  /// Drops one note's vector, and keeps the index in step.
  /// Drops [noteId]'s vector, so the next backfill embeds it again — for a
  /// change to what the note means that is not an edit of its words.
  void forgetEmbedding(String noteId) => _forgetEmbedding(noteId);

  void _forgetEmbedding(String noteId) {
    db.execute('DELETE FROM note_embeddings WHERE note_id = ?', [noteId]);
    final index = _vectors;
    if (index != null) {
      index.remove(noteId);
      _vectorsSignature = _embeddingsSignature();
    }
  }

  VectorIndex? _freshVectors() {
    final signature = _embeddingsSignature();
    if (_vectors != null && signature == _vectorsSignature) return _vectors;
    final space = db.select(
      'SELECT dims, COUNT(*) AS c FROM note_embeddings '
      'WHERE length(q8) > 0 GROUP BY dims ORDER BY c DESC LIMIT 1',
    );
    if (space.isEmpty) {
      _vectors = null;
      _vectorsSignature = signature;
      return null;
    }
    final index = VectorIndex(space.first['dims']! as int);
    for (final row in db.select(
      'SELECT note_id, q8, scale FROM note_embeddings '
      'WHERE dims = ? AND length(q8) > 0',
      [index.dims],
    )) {
      index.put(
        row['note_id']! as String,
        row['q8']! as Uint8List,
        (row['scale']! as num).toDouble(),
      );
    }
    _vectors = index;
    _vectorsSignature = signature;
    return index;
  }

  /// How many close candidates the quantised pass hands to the exact one.
  /// Quantisation moves scores by around a hundredth; a few hundred
  /// candidates is far more than that can reorder past.
  static const _vectorCandidates = 200;

  /// How far above the usual floor a plain match has to be to be shown when
  /// nothing stands out, and how many such matches at most.
  static const strongMargin = 0.1;
  static const strongFallback = 3;

  @override
  List<({String noteId, double score})> nearestEmbeddings(
    List<double> query, {
    int limit = 20,
    double minScore = 0,
    String? excludeNoteId,
    bool standout = false,
  }) {
    final unit = VectorCodec.unit(query);
    if (unit == null || limit <= 0) return const [];
    final index = _freshVectors();
    if (index == null || index.dims != unit.length) return const [];
    final exclude = excludeNoteId == null ? null : {excludeNoteId};
    if (standout && index.length >= VectorIndex.standoutMinRows) {
      final standing = _standoutEmbeddings(
        index,
        unit,
        limit,
        minScore,
        exclude,
      );
      if (standing.isNotEmpty) return standing;
      // Nothing stood out — and after 1.99.82 that was, on the owner's
      // phone, every search: meaning search went silent. A note that is
      // plainly close is still a match: held to a higher floor than usual,
      // which the generic notes the standout test is for sit just under,
      // and only the closest few.
      return _plainEmbeddings(
        index,
        unit,
        limit < strongFallback ? limit : strongFallback,
        minScore + strongMargin,
        exclude,
      );
    }
    return _plainEmbeddings(index, unit, limit, minScore, exclude);
  }

  /// The nearest by plain similarity, at least [minScore], best first.
  List<({String noteId, double score})> _plainEmbeddings(
    VectorIndex index,
    Float32List unit,
    int limit,
    double minScore,
    Set<String>? exclude,
  ) {
    final candidates = index.nearest(
      unit,
      limit > _vectorCandidates ? limit : _vectorCandidates,
      exclude: exclude,
    );
    if (candidates.isEmpty) return const [];
    final placeholders = List.filled(candidates.length, '?').join(',');
    final rows = db.select(
      '''
SELECT e.note_id, e.vec FROM note_embeddings e
JOIN notes n ON n.id = e.note_id
WHERE n.deleted_at IS NULL AND e.note_id IN ($placeholders)
''',
      [for (final c in candidates) c.id],
    );
    final scored = <({String noteId, double score})>[];
    for (final row in rows) {
      final vec = VectorCodec.decode(row['vec']! as Uint8List);
      if (vec.length != unit.length) continue;
      var dot = 0.0;
      for (var i = 0; i < vec.length; i++) {
        dot += vec[i] * unit[i];
      }
      if (dot < minScore) continue;
      scored.add((noteId: row['note_id']! as String, score: dot));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.length > limit ? scored.sublist(0, limit) : scored;
  }

  /// [nearestEmbeddings] for a search: the notes that stand out for the
  /// query against the rest of the library ([VectorIndex.standout]), still
  /// held to [minScore] by their plain similarity, best first.
  List<({String noteId, double score})> _standoutEmbeddings(
    VectorIndex index,
    Float32List unit,
    int limit,
    double minScore,
    Set<String>? exclude,
  ) {
    final picked = index.standout(unit, limit, exclude: exclude);
    if (picked.isEmpty) return const [];
    final placeholders = List.filled(picked.length, '?').join(',');
    final plain = <String, double>{};
    for (final row in db.select(
      '''
SELECT e.note_id, e.vec FROM note_embeddings e
JOIN notes n ON n.id = e.note_id
WHERE n.deleted_at IS NULL AND e.note_id IN ($placeholders)
''',
      [for (final p in picked) p.id],
    )) {
      final vec = VectorCodec.decode(row['vec']! as Uint8List);
      if (vec.length != unit.length) continue;
      var dot = 0.0;
      for (var i = 0; i < vec.length; i++) {
        dot += vec[i] * unit[i];
      }
      plain[row['note_id']! as String] = dot;
    }
    return [
      for (final p in picked)
        if ((plain[p.id] ?? double.negativeInfinity) >= minScore)
          (noteId: p.id, score: p.score),
    ];
  }

  /// Which model's vector space the stored embeddings belong to.
  ///
  /// A fingerprint rather than the model name alone, because the space is
  /// decided by the endpoint as well: the same model name behind a different
  /// base URL is not a promise of the same vectors.
  ///
  /// Null when nothing has ever been embedded, which is not the same as a
  /// space that does not match — the first write simply records one.
  String? get embeddingSpace {
    final rows = db.select(
      "SELECT value FROM nex_meta WHERE key = 'embedding_space'",
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  /// Records the space and, when it has changed, throws the old vectors away.
  ///
  /// Throwing them away is the whole point and is not a loss worth avoiding:
  /// an embedding is derived, re-derivable, and the backfill re-embeds every
  /// note that has no vector. Keeping them would mean scoring one model's
  /// vectors against another's, which `_cosine` will happily do and get
  /// confidently wrong.
  ///
  /// Returns true when the vectors were cleared, so the caller can say so.
  bool setEmbeddingSpace(String fingerprint) {
    final current = embeddingSpace;
    if (current == fingerprint) return false;
    // The wipe and the new stamp together: apart, a crash between them left
    // the old vectors labelled as the new model's (DATA-08).
    db.together(() {
      if (current != null) db.execute('DELETE FROM note_embeddings');
      db.execute(
        "INSERT OR REPLACE INTO nex_meta (key, value) "
        "VALUES ('embedding_space', ?)",
        [fingerprint],
      );
    });
    if (current != null) _vectors = null;
    return current != null;
  }

  @override
  List<double>? getEmbedding(String noteId) {
    final rows = db.select(
      'SELECT vec, values_json FROM note_embeddings WHERE note_id = ?',
      [noteId],
    );
    if (rows.isEmpty) return null;
    final vec = rows.first['vec'];
    if (vec is Uint8List) return VectorCodec.decode(vec);
    return _parseVector(rows.first['values_json']! as String);
  }

  /// Records that **Done** was pressed for [noteId]'s reminder at [at].
  ///
  /// Not a rev bump and not an `updated_at` touch, for the same reason
  /// [setDueAt] is not: this is what the device was told, not an edit to what
  /// the note says. [Note.dueAt] is deliberately left alone — the answer is to
  /// one ring, and clearing the time would drop a repeating reminder's next
  /// turn and any future occurrence with it.
  void markReminderAcked(String noteId, DateTime at) {
    db.execute('UPDATE notes SET reminder_acked_at = ? WHERE id = ?', [
      at.toUtc().toIso8601String(),
      noteId,
    ]);
  }

  @override
  void setDueAt(
    String noteId,
    DateTime? when, {
    NoteRepeat repeat = NoteRepeat.once,
  }) {
    db.execute(
      // Not a rev bump and not an updated_at touch: a reminder is a thing
      // the user asked the app to do, not an edit to what the note says, and
      // re-sorting the timeline because someone set an alarm would move a
      // note they were not writing to.
      //
      // The acknowledgement is cleared with the time. A new time is a new
      // request, and a **Done** from the previous ring must not keep today's
      // nudge from mentioning a reminder that was just set for today.
      'UPDATE notes SET due_at = ?, due_repeat = ?, reminder_acked_at = NULL '
      'WHERE id = ?',
      [
        when?.toUtc().toIso8601String(),
        // Cleared alongside the time. A repeat left behind on a note with no
        // reminder is a rule with nothing to apply to, and it would come back
        // the next time one was set.
        when == null ? null : repeat.wireName,
        noteId,
      ],
    );
  }

  @override
  List<Note> listUpcomingReminders({int limit = 200}) {
    final rows = db.select(
      '''
SELECT * FROM notes
WHERE deleted_at IS NULL
  AND due_at IS NOT NULL
  -- A repeating reminder's stored time is when the *series* started, which
  -- is in the past for every one that has fired even once. Filtering on
  -- `due_at > now` would drop exactly those from the relaunch rebuild, so a
  -- repeat would stop coming back after the first reinstall or reboot —
  -- which is the one thing this query exists to prevent.
  AND (due_at > ? OR (due_repeat IS NOT NULL AND due_repeat != 'once'))
ORDER BY due_at ASC
LIMIT ?
''',
      [DateTime.now().toUtc().toIso8601String(), limit],
    );
    return _withTags(rows);
  }

  @override
  List<Note> listBriefWaiting({int limit = 200}) {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final rows = db.select(
      '''
SELECT * FROM notes
WHERE deleted_at IS NULL
  AND $_notSetAside
  AND (due_at IS NOT NULL OR is_urgent = 1)
  -- Urgent first, because a caller truncating by the limit must never be
  -- able to drop them: with dated notes ahead, a library of more than the
  -- limit in dated reminders left every urgent note outside the cap.
  -- Within each side: dated soonest first, then the undated newest first.
  -- A caller truncating by the limit keeps the front of each group.
ORDER BY is_urgent DESC, (due_at IS NULL), due_at ASC, updated_at DESC
LIMIT ?
''',
      [nowIso, limit],
    );
    return _withTags(rows);
  }

  @override
  List<Note> listNeedingEmbedding({int limit = 25}) {
    // Anything with words in it: a note's own text, a caption, a transcript,
    // an OCR read, or a link's headline. A photo with nothing derived from it
    // yet is excluded rather than embedded as an empty string — it will come
    // back round once enrichment has read it.
    final rows = db.select(
      '''
SELECT n.* FROM notes n
LEFT JOIN note_embeddings e ON e.note_id = n.id
WHERE n.deleted_at IS NULL
  -- No vector yet, or one older than the note's last change (DATA-01): an
  -- edit, a caption, a transcript or a title written since it was embedded
  -- left the vector describing what the note used to say.
  -- Dart writes either three or six fractional digits. Pad both UTC
  -- timestamps so .123001Z is newer than .123Z, retaining microseconds
  -- and treating equivalent timestamps from existing libraries as equal.
  AND (e.note_id IS NULL OR
    substr(replace(e.updated_at, 'Z', '000000'), 1, 26) <
    substr(replace(n.updated_at, 'Z', '000000'), 1, 26))
  AND (
    COALESCE(TRIM(n.content), '') <> ''
    OR COALESCE(TRIM(n.transcript_text), '') <> ''
    OR COALESCE(TRIM(n.ocr_text), '') <> ''
    OR COALESCE(TRIM(n.title), '') <> ''
  )
ORDER BY n.created_at DESC
LIMIT ?
''',
      [limit],
    );
    return _withTags(rows);
  }

  /// Every stored vector, decoded. For export and tests only: a search goes
  /// through [nearestEmbeddings] and never loads the library this way.
  @override
  List<NoteEmbedding> listEmbeddings() {
    final rows = db.select(
      'SELECT note_id, vec, values_json FROM note_embeddings',
    );
    return [
      for (final r in rows)
        NoteEmbedding(
          noteId: r['note_id']! as String,
          values: r['vec'] is Uint8List
              ? VectorCodec.decode(r['vec']! as Uint8List)
              : _parseVector(r['values_json']! as String),
        ),
    ];
  }

  List<double> _parseVector(String json) {
    final trimmed = json.trim();
    if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) return const [];
    final inner = trimmed.substring(1, trimmed.length - 1).trim();
    if (inner.isEmpty) return const [];
    return inner.split(',').map((s) => double.parse(s.trim())).toList();
  }

  /// FR-4 search: FTS on text content + AI-derived transcript/OCR when present.
  @override
  List<Note> search(SearchFilters filters) {
    // A typed query is ranked (W2.2): best match first, not newest first. A
    // search that is only filters — a tag, a type, a date — has nothing to
    // rank and stays in the timeline's order.
    if (filters.query.trim().isNotEmpty) return rankedSearch(filters);

    final (where, args) = _filterClause(filters);
    // Nothing typed and nothing chosen is the whole library, which is what
    // opening the search box or clearing it used to read — every note, and
    // every note's tags one query at a time (PERF-04). With nothing to
    // narrow by, the newest [rankedLimit] are as many as anyone scrolls; a
    // chosen tag, type or date still lists everything it matches.
    final unnarrowed =
        filters.tagIds.isEmpty &&
        filters.types.isEmpty &&
        filters.createdFrom == null &&
        filters.createdTo == null;
    // The timeline's own order, not `created_at`: the comment above has
    // promised it since search moved onto the timeline, and the two lists
    // sit in the same scroll view — a note edited today but written last
    // month was at the top of one and pages deep in the other. Pinned first,
    // then most recently changed, with the same padded-fraction pin order
    // `listTimeline` uses.
    const order = '''
ORDER BY
  (n.pinned_at IS NOT NULL) DESC,
  substr(replace(n.pinned_at, 'Z', '000000'), 1, 26) DESC,
  n.updated_at DESC,
  n.rowid DESC
''';
    final sql =
        '''
SELECT n.* FROM notes n
WHERE ${where.join(' AND ')}
$order
${filters.pageSize != null
            ? 'LIMIT ${filters.pageSize!.clamp(1, 500)} OFFSET ${filters.offset < 0 ? 0 : filters.offset}'
            : unnarrowed
            ? 'LIMIT $rankedLimit'
            : ''}
''';
    return _withTags(db.select(sql, args));
  }

  /// The WHERE terms for everything in [filters] except the query, on notes
  /// aliased `n`: live notes, any of the tags, the date range, the types.
  ///
  /// Several tags mean "any of these", the way the same-shaped chips on the
  /// timeline's own filter row mean it. This used to demand every tag at once
  /// (`HAVING COUNT` equal to the number chosen), so the two rows of chips a
  /// person could see in one session filtered the same library in opposite
  /// directions — the timeline widened as the search narrowed. One meaning,
  /// the one the chips teach.
  (List<String>, List<Object?>) _filterClause(SearchFilters filters) {
    final where = <String>['n.deleted_at IS NULL'];
    final args = <Object?>[];
    if (filters.tagIds.isNotEmpty) {
      final placeholders = List.filled(filters.tagIds.length, '?').join(',');
      where.add('''
n.id IN (
  SELECT note_id FROM note_tags WHERE tag_id IN ($placeholders)
)
''');
      args.addAll(filters.tagIds);
    }
    if (filters.createdFrom != null) {
      where.add('n.created_at >= ?');
      args.add(filters.createdFrom!.toUtc().toIso8601String());
    }
    if (filters.createdTo != null) {
      where.add('n.created_at <= ?');
      args.add(filters.createdTo!.toUtc().toIso8601String());
    }
    if (filters.types.isNotEmpty) {
      final placeholders = List.filled(filters.types.length, '?').join(',');
      where.add('n.type IN ($placeholders)');
      args.addAll(filters.types.map((t) => t.wireName));
    }
    return (where, args);
  }

  /// How many keyword matches are ranked. Past a few hundred, nobody scrolls
  /// a result list — they type another word.
  static const rankedLimit = 200;

  /// Keyword matches for [filters], best first: FTS5 matches by BM25, then
  /// the matches only a substring finds ("tor" in "Generator"), newest first.
  ///
  /// Remembered for the next call with the same filters until this
  /// connection next writes anything: one keystroke asks twice — the instant
  /// round, then the fused round once the meaning search answers — and the
  /// second used to run the FTS query and its whole-index substring pass
  /// again for the same answer (2.6.30). `total_changes()` counts every row
  /// this connection has inserted, updated or deleted, so any write at all,
  /// whichever table, makes the remembered answer stale.
  List<String> keywordRanked(SearchFilters filters, {int limit = rankedLimit}) {
    final key =
        '${filters.query}\u0000${filters.tagIds.join(',')}\u0000'
        '${filters.types.map((t) => t.name).join(',')}\u0000'
        '${filters.createdFrom?.toIso8601String()}\u0000'
        '${filters.createdTo?.toIso8601String()}\u0000$limit';
    final changes = db.select('SELECT total_changes() AS n').first['n']! as int;
    final last = _lastKeyword;
    if (last != null && last.key == key && last.changes == changes) {
      return last.ids;
    }
    final ids = List<String>.unmodifiable(_keywordRanked(filters, limit));
    _lastKeyword = (key: key, changes: changes, ids: ids);
    return ids;
  }

  ({String key, int changes, List<String> ids})? _lastKeyword;

  List<String> _keywordRanked(SearchFilters filters, int limit) {
    final q = filters.query.trim();
    if (q.isEmpty) return const [];
    final tokens = nexSearchTokens(q);
    // A query that folds to no words at all — only quotes, stars or the
    // half-space — has nothing to match. It used to fall through to the
    // substring pass with an empty needle, and `instr(content, '')` is true
    // of every row: one stray keystroke and the whole library was the answer.
    if (tokens.isEmpty) return const [];
    final (where, args) = _filterClause(filters);
    final filter = where.join(' AND ');
    // Deleted notes are taken out of the index when they are deleted, so a
    // search with no filters needs nothing from `notes` at all — and at
    // 50,000 notes the join was a primary-key lookup per match.
    final unfiltered =
        filters.tagIds.isEmpty &&
        filters.types.isEmpty &&
        filters.createdFrom == null &&
        filters.createdTo == null;
    final ids = <String>[
      for (final row in db.select(
        unfiltered
            ? '''
SELECT note_id AS id FROM notes_fts
WHERE notes_fts MATCH ?
ORDER BY bm25(notes_fts), rowid DESC
LIMIT ?
'''
            : '''
SELECT f.note_id AS id FROM notes_fts f
JOIN notes n ON n.id = f.note_id
WHERE notes_fts MATCH ? AND $filter
ORDER BY bm25(notes_fts), n.created_at DESC, n.rowid DESC
LIMIT ?
''',
        [_ftsQuery(tokens), if (!unfiltered) ...args, limit],
      ))
        row['id']! as String,
    ];
    if (ids.length < limit) {
      final seen = ids.toSet();
      final needle = nexSearchFold(q).toLowerCase();
      // `lower()` is ASCII-only — and that is exactly the gap left: the fold
      // normalises every Persian spelling but leaves Latin letters cased,
      // and the index keeps the note's own case. Without it, "NERA" stopped
      // finding "Generator" the moment the FTS pass missed it.
      for (final row in db.select(
        '''
SELECT f.note_id AS id FROM notes_fts f
JOIN notes n ON n.id = f.note_id
WHERE instr(lower(f.content), ?) > 0 AND $filter
ORDER BY n.created_at DESC, n.rowid DESC
LIMIT ?
''',
        [needle, ...args, limit],
      )) {
        final id = row['id']! as String;
        if (seen.add(id)) ids.add(id);
        if (ids.length >= limit) break;
      }
    }
    return ids;
  }

  /// One ranked list for [filters]: its keyword matches fused with
  /// [semantic], the ids a meaning search found, best first (W2.2). Meaning
  /// matches are held to the same filters as keyword ones.
  ///
  /// [keyword] is the same query's keyword matches, already computed in rank
  /// order — the fused round that follows the instant one passes what it just
  /// showed rather than running the FTS query and its substring pass a second
  /// time. Null computes them, as callers outside the search flow still do.
  List<Note> rankedSearch(
    SearchFilters filters, {
    List<String> semantic = const [],
    List<String>? keyword,
    int limit = rankedLimit,
  }) {
    final words = keyword ?? keywordRanked(filters, limit: limit);
    final candidates = {...words, ...semantic}.toList();
    if (candidates.isEmpty) return const [];
    final (where, args) = _filterClause(filters);
    final facts = <String, FusionFacts>{};
    final rows = <String, Row>{};
    for (var at = 0; at < candidates.length; at += 500) {
      final chunk = candidates.sublist(
        at,
        at + 500 > candidates.length ? candidates.length : at + 500,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      for (final row in db.select(
        '''
SELECT n.* FROM notes n
WHERE n.id IN ($placeholders) AND ${where.join(' AND ')}
''',
        [...chunk, ...args],
      )) {
        final id = row['id']! as String;
        rows[id] = row;
        facts[id] = FusionFacts(
          createdAt: DateTime.parse(row['created_at']! as String),
          type: NoteType.fromWire(row['type']! as String),
          pinned: row['pinned_at'] != null,
        );
      }
    }
    final ordered = FusedRanking.fuse(
      keyword: words,
      semantic: semantic,
      facts: facts,
      now: DateTime.now().toUtc(),
      query: filters.query,
    );
    final kept = ordered.take(limit).toList();
    final tags = tagsForNotes(kept);
    return [for (final id in kept) Note.fromRow(rows[id]!, tags: tags[id]!)];
  }

  @override
  List<Note> listNeedingEnrichment({int limit = 50}) {
    // Only media whose text was never derived. A text note is already its own
    // text, and a summary that came back empty is a legitimate answer — asking
    // again on every pass would spend a request to learn the same thing.
    final rows = db.select(
      '''
SELECT * FROM notes
WHERE deleted_at IS NULL
  AND media_uri IS NOT NULL
  AND (
    (type = 'voice' AND transcript_text IS NULL)
    OR (type = 'photo' AND ocr_text IS NULL)
  )
ORDER BY created_at DESC
LIMIT ?
''',
      [limit],
    );
    return _withTags(rows);
  }

  /// Export archive: JSON + Markdown + media (FR-6 / ADR-025).
  Future<File> exportArchive({
    required String outputPath,
    required String mediaRoot,
  }) async {
    final notes = db.select('SELECT * FROM notes WHERE deleted_at IS NULL');
    final tags = listTags();
    final noteModels = _withTags(notes);

    final out = File(outputPath);
    out.parent.createSync(recursive: true);
    final partial = File('$outputPath.partial');
    final encoder = ZipFileEncoder()..create(partial.path);
    try {
      final attachments = SqliteAttachmentRepository(
        this,
        localDeviceId: localDeviceId ?? 'export',
      ).allLive();
      final jsonPayload = jsonEncode({
        // Version 3 (1.99.70): the files a note carries after its own
        // (docs/14-attachments.md). An older build reads a v3 archive as it
        // read v2: every note with its own file, and the attachments left
        // out.
        'version': 3,
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        // Reminders ride on each note; [Note.toJson] leaves them out because
        // the sync wire does, and an archive is not the sync wire. The app
        // rebuilds alarms from the library, so a reminder in the archive is
        // one the device it is imported on can honour.
        'notes': [
          for (final n in noteModels)
            {
              ...n.toJson(),
              'due_at': n.dueAt?.toUtc().toIso8601String(),
              'due_repeat': n.dueRepeat.wireName,
            },
        ],
        'tags': tags.map((t) => t.toJson()).toList(),
        // Version 2 (1.92.2): the recurring items and the threads. Version 1
        // archives carried notes and tags only, and a library moved to a new
        // phone through one arrived without its rent, its insurance and its
        // threads — silently, with the import reporting success.
        'commitments': _rowsOf(
          'SELECT * FROM commitments WHERE deleted_at IS NULL',
        ),
        'threads': _rowsOf('SELECT * FROM threads WHERE deleted_at IS NULL'),
        // Notes written now and held back until later (DATA-03): not in
        // `notes` until they are released, so an export without them lost
        // them on the way to a new phone.
        'scheduled': _rowsOf('SELECT * FROM scheduled_notes'),
        'attachments': [for (final a in attachments) a.toJson()],
        'note_threads': _rowsOf('''
SELECT nt.* FROM note_threads nt
JOIN notes n ON n.id = nt.note_id AND n.deleted_at IS NULL
JOIN threads t ON t.id = nt.thread_id AND t.deleted_at IS NULL
'''),
      });
      final jsonBytes = utf8.encode(jsonPayload);
      encoder.addArchiveFile(
        ArchiveFile('notes.json', jsonBytes.length, jsonBytes),
      );
      final usedMediaNames = <String>{};

      for (final note in noteModels) {
        // The media entry is named before the note's Markdown is written,
        // because the Markdown links to it. It used to link to the bare name
        // whatever the entry was called, so of two photos with the same
        // file name the second note's Markdown showed the first note's photo.
        String? entryName;
        if (note.mediaUri != null) {
          final src = File(note.mediaUri!);
          if (src.existsSync()) {
            // Two notes can legitimately carry files with the same basename
            // (a photo exported twice, a recording re-made under the same
            // second). Flattening by name silently kept only the last one —
            // the archive looked complete and had one fewer photo in it.
            // On a collision the note's id goes in front, which is unique by
            // construction; the importer knows to look for both spellings.
            final name = nexPortableBasename(note.mediaUri!);
            final firstUse = usedMediaNames.add(name);
            entryName = firstUse ? name : '${note.id}-$name';
            addBoundedZipFile(encoder, src, 'media/$entryName');
          }
        }
        final md = _markdownFor(note, mediaName: entryName);
        final bytes = utf8.encode(md);
        encoder.addArchiveFile(
          ArchiveFile('markdown/${note.id}.md', bytes.length, bytes),
        );
      }

      // An attachment's file: under its own name when that is free, else
      // with the attachment's id in front — the same rule as the notes'
      // own files, and the importer looks for both spellings in that order.
      for (final attachment in attachments) {
        final src = File(attachment.mediaUri);
        if (!src.existsSync()) continue;
        final name = nexPortableBasename(attachment.mediaUri);
        final firstUse = usedMediaNames.add(name);
        final entryName = firstUse ? name : '${attachment.id}-$name';
        addBoundedZipFile(encoder, src, 'media/$entryName');
      }

      encoder.closeSync();
      partial.renameSync(out.path);
    } catch (_) {
      encoder.closeSync();
      if (partial.existsSync()) partial.deleteSync();
      rethrow;
    }
    return out;
  }

  /// Reads an export archive back into the library.
  ///
  /// The counterpart to [exportArchive], and the reason an export is worth
  /// having: without this, an archive was a one-way write that nothing could
  /// read back, and the only recoverable copy of a library was the automatic
  /// local backup — which lives on the very device the user might have lost.
  ///
  /// Additive by design. A note whose id is already here is left exactly as it
  /// is rather than overwritten: importing an old archive must never roll a
  /// note back to a previous state, so re-importing the same file twice is a
  /// no-op. Media travels with the archive and is written under [mediaRoot],
  /// and the stored path is rewritten to that new location — a path from
  /// another device means nothing here.
  Future<ImportResult> importArchive({
    required File archiveFile,
    required String mediaRoot,
  }) async {
    final input = InputFileStream(archiveFile.path);
    try {
      final archive = ZipDecoder().decodeStream(
        input,
        verify: true,
        throwOnError: true,
      );
      final jsonFile = archive.findFile('notes.json');
      if (jsonFile == null) {
        throw const FormatException('not a Nex export: notes.json is missing');
      }
      final payload = jsonDecode(
        utf8.decode(jsonFile.content as List<int>),
      ) as Map<String, dynamic>;

      var imported = 0;
      var skipped = 0;
      // One transaction around the whole import. A failure halfway through used
      // to leave a partial import on disk — half the notes, and a re-import of
      // the same file would then skip everything already landed, so the user
      // could not even heal it by trying again. All of it applies, or none.
      //
      // The tags are inside it too. They used to be written in a loop above
      // this line, so "all of it applies, or none" was not true of them: an
      // archive whose notes failed to parse still left its tags behind, and the
      // rollback below could not reach them.
      db.beginImmediate();
      try {
        for (final raw in (payload['tags'] as List? ?? const [])) {
          final tag = raw as Map<String, dynamic>;
          upsertTagFromSync(
            id: tag['id']! as String,
            name: tag['name']! as String,
            color: tag['color'] as String?,
            createdAt: DateTime.parse(tag['created_at']! as String),
            // An explicit import restores the archived metadata. Only live
            // sync must protect edits made while its HTTP request was away.
            preservePending: false,
          );
        }
        for (final raw in (payload['notes'] as List? ?? const [])) {
          final json = raw as Map<String, dynamic>;
          final note = Note.fromRow(json);
          if (db.select('SELECT id FROM notes WHERE id = ?', [
            note.id,
          ]).isNotEmpty) {
            skipped++;
            continue;
          }

          String? mediaUri;
          if (note.mediaUri != null) {
            final name = nexPortableBasename(note.mediaUri!);
            // The id-prefixed spelling first, and that order is the fix. The
            // exporter writes it *only* when the bare name was already taken by
            // another note — so a note that has an id-prefixed entry is exactly
            // a note whose bare name belongs to somebody else. Looking the bare
            // name up first therefore handed the second note the first note's
            // bytes, silently, on a round trip the exporter had gone out of its
            // way to keep lossless.
            var entry = archive.findFile('media/${note.id}-$name');
            entry ??= archive.findFile('media/$name');
            if (entry != null) {
              // A destination of its own, for the same reason. Both notes used
              // to be written to `<root>/<basename>`, so even with the right
              // bytes the second overwrote the first and the two rows ended up
              // sharing one file — which the purge then deleted out from under
              // whichever note was not the one being purged.
              final extension = p.extension(name);
              final suffix =
                  RegExp(r'^\.[a-zA-Z0-9]{1,10}$').hasMatch(extension)
                  ? extension
                  : '';
              final target = File(p.join(mediaRoot, '${newUuidV7()}$suffix'));
              target.parent.createSync(recursive: true);
              extractCheckedZipFile(entry, target.path);
              mediaUri = target.path;
            }
            // No media in the archive: the note still comes in, with its text
            // and its tags. Losing the whole note over a missing attachment
            // would be a worse trade than losing the attachment.
          }

          applyRemoteNote(
            id: note.id,
            type: note.type,
            content: note.content,
            mediaUri: mediaUri,
            mediaHash: note.mediaHash,
            durationMs: note.durationMs,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
            deletedAt: note.deletedAt,
            deviceId: note.deviceId,
            rev: note.rev,
            tagIds: [
              for (final tag in (json['tags'] as List? ?? const []))
                (tag as Map<String, dynamic>)['id']! as String,
            ],
          );
          // applyRemoteNote carries no captions, transcripts, summaries, titles
          // or link excerpts — none of them are part of the sync wire — so they
          // are written back here.
          //
          // Titles and link excerpts are on that list deliberately, alongside
          // the caption they most resemble. What *does* cross the wire is
          // `content`, which is where a checklist keeps its items and a link
          // keeps its URL — so both of those new types sync as completely as a
          // text note does, and it is only the annotation on top that stays
          // local until the wire grows a field for it.
          _restoreEnrichment(note);
          if (note.dueAt case final dueAt?) {
            db.execute(
              'UPDATE notes SET due_at = ?, due_repeat = ? WHERE id = ?',
              [
                dueAt.toUtc().toIso8601String(),
                note.dueRepeat.wireName,
                note.id,
              ],
            );
          }
          imported++;
        }
        // Recurring items and threads, with the same additive rule as notes:
        // a row whose id is already here is left as it is.
        _insertRowsIfAbsent('commitments', payload['commitments']);
        _insertRowsIfAbsent('threads', payload['threads']);
        _insertRowsIfAbsent('scheduled_notes', payload['scheduled']);
        for (final raw in (payload['note_threads'] as List? ?? const [])) {
          final row = raw as Map<String, dynamic>;
          db.execute(
            '''
INSERT OR IGNORE INTO note_threads (note_id, thread_id, added_at)
SELECT ?, ?, ?
WHERE EXISTS (SELECT 1 FROM notes WHERE id = ?)
  AND EXISTS (SELECT 1 FROM threads WHERE id = ?)
''',
            [
              row['note_id'],
              row['thread_id'],
              row['added_at'],
              row['note_id'],
              row['thread_id'],
            ],
          );
        }
        // Attachments (v3), with the additive rule: one whose id is here
        // already, or whose note is not, is left out. Each file gets a fresh
        // name under the media root, as a note's own does.
        final attachmentRepo = SqliteAttachmentRepository(
          this,
          localDeviceId: localDeviceId ?? 'import',
        );
        final touched = <String>{};
        for (final raw in (payload['attachments'] as List? ?? const [])) {
          final json = raw as Map<String, dynamic>;
          final attachment = NoteAttachment.fromRow(json);
          final name = nexPortableBasename(attachment.mediaUri);
          var entry = archive.findFile('media/${attachment.id}-$name');
          entry ??= archive.findFile('media/$name');
          if (entry == null) continue;
          final extension = p.extension(name);
          final suffix = RegExp(r'^\.[a-zA-Z0-9]{1,10}$').hasMatch(extension)
              ? extension
              : '';
          final target = File(p.join(mediaRoot, '${newUuidV7()}$suffix'));
          final placed = NoteAttachment(
            id: attachment.id,
            noteId: attachment.noteId,
            position: attachment.position,
            kind: attachment.kind,
            mediaUri: target.path,
            mediaHash: attachment.mediaHash,
            name: attachment.name,
            mimeType: attachment.mimeType,
            durationMs: attachment.durationMs,
            caption: attachment.caption,
            ocrText: attachment.ocrText,
            transcriptText: attachment.transcriptText,
            createdAt: attachment.createdAt,
            updatedAt: attachment.updatedAt,
            deviceId: attachment.deviceId,
            rev: attachment.rev,
          );
          if (!attachmentRepo.insertIfAbsent(placed)) continue;
          target.parent.createSync(recursive: true);
          extractCheckedZipFile(entry, target.path);
          touched.add(attachment.noteId);
        }
        for (final noteId in touched) {
          _reindex(noteId);
        }
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
      return ImportResult(imported: imported, skipped: skipped);
    } finally {
      input.closeSync();
    }
  }

  /// Every row [sql] returns, as plain maps for an export archive.
  List<Map<String, Object?>> _rowsOf(String sql) => [
    for (final row in db.select(sql))
      {for (final column in row.keys) column: row[column]},
  ];

  /// Inserts the archived [rows] into [table], skipping ids already here.
  ///
  /// Only the columns this version's table has are written, so an archive
  /// from a newer version with an extra column still imports, and one from
  /// an older version leaves the newer columns at their defaults.
  void _insertRowsIfAbsent(String table, Object? rows) {
    if (rows is! List || rows.isEmpty) return;
    final columns = {
      for (final info in db.select('PRAGMA table_info($table)'))
        info['name']! as String,
    };
    for (final raw in rows) {
      final row = (raw as Map<String, dynamic>)
        ..removeWhere((key, _) => !columns.contains(key));
      if (row['id'] is! String) continue;
      final names = row.keys.toList();
      db.execute(
        'INSERT OR IGNORE INTO $table (${names.join(', ')}) '
        'VALUES (${List.filled(names.length, '?').join(', ')})',
        [for (final name in names) row[name]],
      );
    }
  }

  void _restoreEnrichment(Note note) {
    if (note.caption == null &&
        note.transcriptText == null &&
        note.ocrText == null &&
        note.summaryText == null &&
        note.title == null &&
        note.linkExcerpt == null &&
        note.mimeType == null) {
      return;
    }
    db.execute(
      '''
UPDATE notes
SET caption = ?, transcript_text = ?, ocr_text = ?, summary_text = ?,
    title = ?, link_excerpt = ?, mime_type = ?
WHERE id = ?
''',
      [
        note.caption,
        note.transcriptText,
        note.ocrText,
        note.summaryText,
        note.title,
        note.linkExcerpt,
        note.mimeType,
        note.id,
      ],
    );
    final searchable = note.searchableDerivedText;
    if (searchable != null && note.deletedAt == null) {
      _upsertFts(note.id, searchable);
    }
  }

  /// Reads an export archive and returns the parsed notes/tags JSON payload.
  static Map<String, dynamic> readExportJson(File archiveFile) {
    final bytes = archiveFile.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(
      bytes,
      verify: true,
      throwOnError: true,
    );
    final jsonFile = archive.findFile('notes.json');
    if (jsonFile == null) {
      throw StateError('export archive missing notes.json');
    }
    return jsonDecode(utf8.decode(jsonFile.content as List<int>))
        as Map<String, dynamic>;
  }

  /// Writes a complete backup — the database and every media file.
  ///
  /// [mediaDir] is required rather than optional: making it optional is how
  /// the media came to be left out of a backup in the first place, and a
  /// caller that genuinely has no media can pass a directory that does not
  /// exist.
  File backupSnapshot(String backupDir) =>
      NexBackupArchive.snapshotDatabase(database: _db, backupDir: backupDir);

  File backup(
    String backupDir, {
    required String mediaDir,
    bool allowMissingMedia = false,
  }) => NexBackupArchive.create(
    database: _db,
    mediaDir: mediaDir,
    backupDir: backupDir,
    allowMissingMedia: allowMissingMedia,
  );

  /// Marks a note changed, and says whether the change was an *edit*.
  ///
  /// The two are not the same thing, and conflating them is what put a note
  /// back at the top of the timeline for being tagged. `updated_at` is what
  /// the timeline sorts on, so it means "when this note last said something
  /// different" — filing it under a tag does not change what it says. `rev`
  /// and `sync_state` still move either way, because the change does have to
  /// reach other devices.
  ///
  /// The cost of leaving `updated_at` alone is in the merge rule, which is
  /// last-write-wins on that field with `rev` as the tiebreak: a tag added
  /// here loses to a *newer* remote edit of the same note. Equal timestamps —
  /// the ordinary case, where the other device has not touched the note — are
  /// still decided by `rev`, so the tag propagates. Floating every note that
  /// was ever filed to the top of the list is the worse of the two.
  void _bumpNote(String noteId, {bool edited = true}) {
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute(
      '''
UPDATE notes
SET rev = rev + 1, sync_state = 'pending'
    ${edited ? ', updated_at = ?' : ''}
    ${localDeviceId != null ? ', device_id = ?' : ''}
WHERE id = ?
''',
      [if (edited) now, if (localDeviceId != null) localDeviceId, noteId],
    );
  }

  /// Removes [noteId]'s search row by its key, not by scanning for its
  /// label.
  ///
  /// `note_id` is UNINDEXED in `notes_fts`, so `DELETE ... WHERE note_id = ?`
  /// read every indexed note to find the one being removed — linear in the
  /// library on every capture, edit, reindex and delete. The row's key is
  /// the note's own `notes.rowid` (see `NexDatabase._alignFtsRowids`), which
  /// FTS5 keeps a B-tree on, so the delete is one lookup.
  ///
  /// Public because the scheduled-note move and this class's own writers
  /// both need it, and because the note row must still exist at the moment
  /// it is called — callers that delete the note row itself order the two
  /// statements so it does.
  void deleteSearchRow(String noteId) {
    final rowid = _noteRowid(noteId);
    if (rowid == null) {
      // The note row is gone, so nothing maps its search row to a key; the
      // scan is the only way left to find it. Rare — the purge paths that
      // drop the row hard delete the search row inside the same
      // transaction, ahead of it.
      db.execute('DELETE FROM notes_fts WHERE note_id = ?', [noteId]);
      return;
    }
    db.execute('DELETE FROM notes_fts WHERE rowid = ?', [rowid]);
  }

  /// The `notes.rowid` a note's search row is keyed on, or null when the
  /// note is not there.
  int? _noteRowid(String noteId) {
    final rows = db.select('SELECT rowid FROM notes WHERE id = ?', [noteId]);
    return rows.isEmpty ? null : rows.first['rowid'] as int;
  }

  void _upsertFts(String noteId, String content) {
    final rowid = _noteRowid(noteId);
    if (rowid == null) {
      // No note, no search row — the open-time repair is what re-adds one
      // for a note that comes back.
      db.execute('DELETE FROM notes_fts WHERE note_id = ?', [noteId]);
      return;
    }
    db.execute('DELETE FROM notes_fts WHERE rowid = ?', [rowid]);
    if (content.isEmpty) return;
    // Folded, so every spelling of a word is one token
    // (see [nexSearchIndexText]). The rowid is the note's own — see
    // [deleteSearchRow] for why that makes the delete above one lookup
    // rather than a scan of the whole index.
    db.execute(
      'INSERT INTO notes_fts (rowid, note_id, content) VALUES (?, ?, ?)',
      [rowid, noteId, nexSearchIndexText(content)],
    );
  }

  /// Build an FTS5 MATCH query from tokens already folded
  /// ([nexSearchTokens]): quote each so no character is read as FTS syntax,
  /// and make the final token a prefix so results narrow as the user types.
  ///
  /// Every token used to be an exact match, which meant nothing was found until
  /// a whole word had been typed — FR-4.7 requires results to update
  /// incrementally. Only the last token gets `*`: the earlier ones are words the
  /// user finished typing and meant literally, while the trailing one is still
  /// mid-keystroke.
  String _ftsQuery(List<String> tokens) {
    if (tokens.isEmpty) return '""';
    return [
      for (var i = 0; i < tokens.length; i++)
        i == tokens.length - 1 ? '"${tokens[i]}"*' : '"${tokens[i]}"',
    ].join(' ');
  }

  /// [mediaName] is the name the note's file has under `media/` in the
  /// archive; null when the file was not there to copy, where the bare name
  /// still says which file the note had.
  String _markdownFor(Note note, {String? mediaName}) {
    final media = note.mediaUri == null
        ? null
        : mediaName ?? nexPortableBasename(note.mediaUri!);
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('nex_export: 1')
      ..writeln('id: ${note.id}')
      ..writeln('type: ${note.type.wireName}')
      ..writeln('title: ${jsonEncode(note.title)}')
      ..writeln('created_at: ${note.createdAt.toUtc().toIso8601String()}')
      ..writeln('tags: ${jsonEncode(note.tags.map((t) => t.name).toList())}')
      ..writeln('---')
      ..writeln();
    // Also render the title for a Markdown reader. Its explicit metadata
    // distinguishes it from a heading that belongs to the body on re-import.
    if (note.title != null) {
      buffer
        ..writeln('# ${note.title}')
        ..writeln();
    }
    switch (note.type) {
      case NoteType.text:
        buffer.writeln(note.content ?? '');
      case NoteType.voice:
        buffer.writeln('_Voice note_');
        if (note.durationMs != null) {
          buffer.writeln('Duration: ${note.durationMs} ms');
        }
        if (media != null) buffer.writeln('Media: $media');
        if (note.transcriptText != null) {
          buffer.writeln('Transcript: ${note.transcriptText}');
        }
      case NoteType.photo:
        buffer.writeln('_Photo note_');
        if (media != null) buffer.writeln('![photo](../media/$media)');
        if (note.ocrText != null) {
          buffer.writeln('OCR: ${note.ocrText}');
        }
      case NoteType.file:
        buffer.writeln('_File attachment_');
        if (media != null) buffer.writeln('File: $media');
      // Written out as the markdown task list it already is, so an exported
      // checklist opens as a working checklist in any markdown editor rather
      // than as a description of one.
      case NoteType.checklist:
        buffer.writeln(note.content ?? '');
      case NoteType.link:
        final url = note.linkUrl;
        if (url != null) buffer.writeln('<$url>');
        if (note.linkExcerpt != null) {
          buffer
            ..writeln()
            ..writeln(note.linkExcerpt);
        }
        if (note.summaryText != null) {
          buffer
            ..writeln()
            ..writeln('Summary: ${note.summaryText}');
        }
    }
    return buffer.toString();
  }
}
