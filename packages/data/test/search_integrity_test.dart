import 'dart:io';

import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The search system's integrity contract: every writer derives the whole
/// search row, a query with no words finds nothing rather than everything,
/// and a filter-only search keeps the timeline's own order. Every failure
/// below shipped at least once.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_search_integrity_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db, localDeviceId: 'd');
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Note makeText(String content, {String? title}) {
    final now = DateTime.now().toUtc();
    return Note(
      id: newUuidV7(),
      type: NoteType.text,
      content: content,
      title: title,
      createdAt: now,
      updatedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    );
  }

  Note insert(Note note) => repo.insert(note);

  List<String> searchIds(String query) =>
      repo.search(SearchFilters(query: query)).map((n) => n.id).toList();

  /// A photo attachment whose OCR text is the note's searchable window onto
  /// it, written the way `SqliteAttachmentRepository` writes one.
  void attachWithOcr(String noteId, String ocrText) {
    final now = DateTime.now().toUtc().toIso8601String();
    repo.db.execute(
      '''
INSERT INTO note_attachments (
  id, note_id, position, kind, media_uri, media_hash, ocr_text,
  created_at, updated_at, device_id, rev
) VALUES (?, ?, 0, 'photo', '/tmp/x.jpg', 'hash', ?, ?, ?, 'd', 1)
''',
      [newUuidV7(), noteId, ocrText, now, now],
    );
    repo.attachmentsChanged(noteId);
  }

  group('every writer derives the whole search row', () {
    test('captioning a note keeps its attachments findable', () {
      final note = insert(makeText('a plain note body'));
      attachWithOcr(note.id, 'receipt for the chimney sweep');
      expect(searchIds('chimney'), contains(note.id));

      repo.setCaption(note.id, 'the visit');

      // The caption used to be written with the note's own derived text
      // alone, and the attachment's read text fell out of the search row:
      // the words that had just made the photo findable stopped finding it.
      expect(searchIds('chimney'), contains(note.id));
      expect(searchIds('visit'), contains(note.id));
    });

    test('a synced content edit keeps the title findable', () {
      final note = insert(makeText('first draft', title: 'Berlin trip'));

      repo.updateContentAt(note.id, 'second draft', DateTime.now().toUtc());

      // The raw body used to be upserted on its own, dropping the title.
      expect(searchIds('berlin'), contains(note.id));
      expect(searchIds('second'), contains(note.id));
    });

    test('a remote update keeps local attachment words findable', () {
      final note = insert(makeText('body words'));
      attachWithOcr(note.id, 'warranty card inside the box');
      expect(searchIds('warranty'), contains(note.id));
      repo.markSynced(note.id, serverRev: note.rev);

      repo.applyRemoteNote(
        id: note.id,
        type: NoteType.text,
        content: 'body words from the server',
        createdAt: note.createdAt,
        updatedAt: DateTime.now().toUtc(),
        deviceId: 'peer',
        rev: note.rev + 1,
        tagIds: const [],
      );

      expect(searchIds('warranty'), contains(note.id));
      expect(searchIds('server'), contains(note.id));
    });

    test('a remote tombstone leaves nothing findable', () {
      final note = insert(makeText('to be deleted elsewhere'));
      // Synced, so the pending-edit protection does not keep a conflict
      // copy of a note the server says is gone — that copy is a live note
      // and is meant to stay findable.
      repo.markSynced(note.id, serverRev: note.rev);

      repo.applyRemoteNote(
        id: note.id,
        type: NoteType.text,
        content: 'to be deleted elsewhere',
        createdAt: note.createdAt,
        updatedAt: DateTime.now().toUtc(),
        deletedAt: DateTime.now().toUtc(),
        deviceId: 'peer',
        rev: note.rev + 1,
        tagIds: const [],
      );

      expect(searchIds('deleted'), isEmpty);
    });
  });

  group('a query with no words in it finds nothing', () {
    setUp(() {
      insert(makeText('alpha'));
      insert(makeText('beta'));
    });

    test('a lone half-space does not list the library', () {
      // Shift+Space on a Persian keyboard. It folded to an empty needle and
      // `instr(content, '')` is true of every row.
      expect(repo.search(const SearchFilters(query: '‌')), isEmpty);
    });

    test('quotes and stars alone find nothing', () {
      expect(repo.search(const SearchFilters(query: '"')), isEmpty);
      expect(repo.search(const SearchFilters(query: '**')), isEmpty);
      expect(repo.search(const SearchFilters(query: ' " * ')), isEmpty);
    });
  });

  group('a filter-only search keeps the timeline order', () {
    test('pinned first, then most recently changed', () async {
      final old = insert(makeText('written first'));
      final pinned = insert(makeText('written second'));
      final newest = insert(makeText('written third'));
      // The oldest note is edited now: the timeline floats it above the
      // newer note, and so must a search that has nothing to rank by.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      repo.updateContent(old.id, 'written first, edited');

      expect(repo.pinNote(pinned.id), isTrue);

      final results = repo.search(const SearchFilters(types: [NoteType.text]));
      expect(results.map((n) => n.id), [pinned.id, old.id, newest.id]);
    });
  });

  group('the fused round can ride on the instant one', () {
    test('passed keyword matches are used, not recomputed', () {
      final match = insert(makeText('boiler service'));
      insert(makeText('unrelated'));

      // An empty keyword list with a meaning hit: if the fused round ignored
      // the list and recomputed, the boiler note would lead the answer.
      final ranked = repo.rankedSearch(
        const SearchFilters(query: 'unrelated'),
        semantic: [match.id],
        keyword: const [],
      );
      expect(ranked.map((n) => n.id), [match.id]);

      // And the same query's own list, passed back, ranks as if computed.
      final keyword = repo.keywordRanked(const SearchFilters(query: 'boiler'));
      final fused = repo.rankedSearch(
        const SearchFilters(query: 'boiler'),
        keyword: keyword,
      );
      expect(fused.map((n) => n.id), [match.id]);
    });
  });

  group('versioned repair heals rows the old writers damaged', () {
    test('a caption-era partial row is re-derived on upgrade', () {
      final note = insert(makeText('body words', title: 'Reykjavik notes'));
      // What `setCaption` used to write: the note's own text, no title.
      repo.db.execute("UPDATE notes_fts SET content = ? WHERE note_id = ?", [
        nexSearchIndexText('body words'),
        note.id,
      ]);
      repo.db.execute(
        "INSERT OR REPLACE INTO nex_meta (key, value) "
        "VALUES ('search_text_version', '1')",
      );
      expect(searchIds('reykjavik'), isEmpty, reason: 'the damaged row');

      repo.repairSearchIndex();

      expect(searchIds('reykjavik'), contains(note.id));
      final version = repo.db.select(
        "SELECT value FROM nex_meta WHERE key = 'search_text_version'",
      );
      expect('$version', contains('2'));
    });
  });

  group('one keystroke runs the keyword search once', () {
    test('the same filters, unchanged library: the remembered answer', () {
      insert(makeText('boiler service'));
      const filters = SearchFilters(query: 'boiler');
      final first = repo.keywordRanked(filters);
      // The fused round asks again for the same keystroke: same answer,
      // not a second FTS query and whole-index substring pass.
      expect(identical(repo.keywordRanked(filters), first), isTrue);
    });

    test('any write makes it stale', () {
      final a = insert(makeText('boiler service'));
      const filters = SearchFilters(query: 'boiler');
      expect(repo.keywordRanked(filters), [a.id]);

      final b = insert(makeText('boiler repair'));
      expect(repo.keywordRanked(filters).toSet(), {a.id, b.id});

      repo.softDelete(a.id);
      expect(repo.keywordRanked(filters), [b.id]);

      repo.updateContent(b.id, 'the furnace');
      expect(repo.keywordRanked(filters), isEmpty);
    });
  });
}
