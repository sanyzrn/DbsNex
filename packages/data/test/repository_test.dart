import 'dart:io';
import 'dart:typed_data';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_data_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Note makeText(String content, {DateTime? at}) {
    final now = at ?? DateTime.now().toUtc();
    return Note(
      id: newUuidV7(),
      type: NoteType.text,
      content: content,
      createdAt: now,
      updatedAt: now,
      deviceId: 'test-device',
      rev: 1,
      syncState: SyncState.pending,
    );
  }

  group('1.1 repository integration', () {
    test('insert returns note with UUIDv7-shaped id', () {
      final note = repo.insert(makeText('hello'));
      expect(note.id.length, 36);
      expect(note.content, 'hello');
      expect(note.rev, 1);
      expect(note.syncState, SyncState.pending);
      // UUIDv7 version nibble is 7 at character index 14 of the hex form.
      final hex = note.id.replaceAll('-', '');
      expect(hex[12], '7');
    });

    test('soft-delete hides note from timeline and FTS', () {
      final note = repo.insert(makeText('vanish me'));
      repo.softDelete(note.id);
      expect(repo.getById(note.id), isNull);
      expect(repo.listTimeline(), isEmpty);
      expect(repo.search(const SearchFilters(query: 'vanish')), isEmpty);
      expect(repo.getById(note.id, includeDeleted: true)?.isDeleted, isTrue);
    });

    test('tag attach and detach', () {
      final note = repo.insert(makeText('tagged'));
      final tag = repo.upsertTag(name: 'Work', color: tagAccentPalette.first);
      repo.attachTag(noteId: note.id, tagId: tag.id);
      expect(repo.getById(note.id)!.tags.map((t) => t.name), ['Work']);
      repo.detachTag(noteId: note.id, tagId: tag.id);
      expect(repo.getById(note.id)!.tags, isEmpty);
    });

    test('FTS query finds English text notes', () {
      repo.insert(makeText('alpha bravo charlie'));
      repo.insert(makeText('delta echo'));
      final hits = repo.search(const SearchFilters(query: 'bravo'));
      expect(hits, hasLength(1));
      expect(hits.first.content, contains('bravo'));
    });

    // FR-4.7: results update incrementally as the user types. Every token used
    // to be an exact match, so nothing appeared until a whole word was typed.
    test('search matches a partial word as it is typed (FR-4.7)', () {
      repo.insert(makeText('groceries for the weekend'));

      expect(repo.search(const SearchFilters(query: 'gro')).length, 1);
      expect(repo.search(const SearchFilters(query: 'grocer')).length, 1);
      expect(repo.search(const SearchFilters(query: 'groceries')).length, 1);
      expect(repo.search(const SearchFilters(query: 'grz')), isEmpty);
    });

    test('earlier tokens stay exact, only the last one is a prefix', () {
      repo.insert(makeText('weekend plan'));

      // "weekend" complete + "pl" still being typed -> matches.
      expect(repo.search(const SearchFilters(query: 'weekend pl')).length, 1);
      // A truncated earlier token is not a prefix, so it must not match.
      expect(repo.search(const SearchFilters(query: 'week plan')), isEmpty);
    });

    // Re-tagging a second note used to repaint every note already carrying
    // that tag, because upsertTag wrote whatever colour the caller passed.
    test('re-adding an existing tag never repaints it', () {
      final first = repo.insert(makeText('first'));
      final second = repo.insert(makeText('second'));
      final red = repo.upsertTag(name: 'Groceries', color: '#C0392B');
      repo.attachTag(noteId: first.id, tagId: red.id);

      final again = repo.upsertTag(name: 'Groceries', color: '#5B9BF0');

      expect(again.id, red.id, reason: 'still the same tag');
      expect(again.color, '#C0392B', reason: 'colour is the tag owner\'s call');
      repo.attachTag(noteId: second.id, tagId: again.id);
      expect(repo.getById(first.id)!.tags.single.color, '#C0392B');
      expect(repo.getById(second.id)!.tags.single.color, '#C0392B');
    });

    test('a tag with no colour yet takes its first one', () {
      // The starter tags ship colourless; tagging a note is a reasonable place
      // to give one its first colour, which is not the same as overwriting.
      final seeded = repo.listTags().firstWhere((t) => t.name == 'Shopping');
      expect(seeded.color, isNull);

      final coloured = repo.upsertTag(name: 'Shopping', color: '#2FBF8F');
      expect(coloured.id, seeded.id);
      expect(coloured.color, '#2FBF8F');

      // ...and from then on it is settled.
      expect(repo.upsertTag(name: 'Shopping', color: '#F17FA0').color, '#2FBF8F');
    });

    test('setTagColor accepts any #RRGGBB and rejects anything else', () {
      final tag = repo.upsertTag(name: 'Work');
      repo.setTagColor(tagId: tag.id, color: '#123ABC');
      expect(
        repo.listTags().firstWhere((t) => t.id == tag.id).color,
        '#123ABC',
      );

      for (final bad in ['red', '#FFF', '#12345G', '123ABC']) {
        expect(
          () => repo.setTagColor(tagId: tag.id, color: bad),
          throwsArgumentError,
          reason: bad,
        );
      }
    });

    test('starter tags carry the same id on every device (sync safety)', () {
      // Each device seeds its own copy, so a random id would give two devices
      // two different "Work" tags and syncing them would produce a duplicate
      // the user never made.
      final second = Directory.systemTemp.createTempSync('nex_second_device_');
      final otherDb = NexDatabase.open(p.join(second.path, 'nex.sqlite'));
      addTearDown(() {
        otherDb.close();
        second.deleteSync(recursive: true);
      });
      final other = SqliteNoteRepository(otherDb);

      final here = {for (final tag in repo.listTags()) tag.name: tag.id};
      final there = {for (final tag in other.listTags()) tag.name: tag.id};

      expect(here.keys, unorderedEquals(suggestedStarterTags));
      expect(here, there);
    });

    test('Persian FTS correctness (ADR-028)', () {
      // Includes ZWNJ (U+200C) between می and رود — common Persian orthography.
      const zwnj = '\u200C';
      final persian = 'این یک ایده$zwnjی مهم است';
      repo.insert(makeText(persian));
      repo.insert(makeText('unrelated english'));

      final byStem = repo.search(const SearchFilters(query: 'ایده'));
      expect(byStem, hasLength(1),
          reason: 'should find Persian note by content token');
      expect(byStem.first.content, contains('ایده'));

      final byWord = repo.search(const SearchFilters(query: 'مهم'));
      expect(byWord, hasLength(1));
    });

    test('voice notes excluded from keyword FTS (FR-4.6)', () {
      final now = DateTime.now().toUtc();
      final voice = Note(
        id: newUuidV7(),
        type: NoteType.voice,
        content: null,
        mediaUri: '/tmp/x.m4a',
        mediaHash: sha256OfBytes(Uint8List.fromList([1, 2, 3])),
        durationMs: 1200,
        createdAt: now,
        updatedAt: now,
        deviceId: 'test-device',
        rev: 1,
        syncState: SyncState.pending,
      );
      repo.insert(voice);
      // Even if we wrongly put text in content, FTS only indexes text types
      // via insert path — voice has no FTS row.
      expect(repo.search(const SearchFilters(query: 'anything')), isEmpty);
      expect(
        repo.search(const SearchFilters(types: [NoteType.voice])),
        hasLength(1),
      );
    });

    test('timeline is reverse-chronological', () {
      final t0 = DateTime.utc(2026, 1, 1);
      final t1 = DateTime.utc(2026, 1, 2);
      final t2 = DateTime.utc(2026, 1, 3);
      repo.insert(makeText('old', at: t0));
      repo.insert(makeText('mid', at: t1));
      repo.insert(makeText('new', at: t2));
      final page = repo.listTimeline();
      expect(page.map((n) => n.content).toList(), ['new', 'mid', 'old']);
    });

    test('editing a note moves it back to the top of the timeline', () {
      // Reported symptom: editing an old note left it sitting wherever it was
      // originally created instead of surfacing where the change was made.
      final t0 = DateTime.utc(2026, 1, 1);
      final t1 = DateTime.utc(2026, 1, 2);
      final t2 = DateTime.utc(2026, 1, 3);
      final old = repo.insert(makeText('old', at: t0));
      repo.insert(makeText('mid', at: t1));
      repo.insert(makeText('new', at: t2));
      expect(
        repo.listTimeline().map((n) => n.content).toList(),
        ['new', 'mid', 'old'],
      );

      repo.updateContent(old.id, 'old, edited just now');

      expect(
        repo.listTimeline().map((n) => n.content).toList(),
        ['old, edited just now', 'new', 'mid'],
      );
    });
  });

  group('1.9 export round-trip', () {
    test('export archive JSON matches source notes', () async {
      final mediaDir = Directory(p.join(tmp.path, 'media'))..createSync();
      final mediaFile = File(p.join(mediaDir.path, 'shot.jpg'))
        ..writeAsBytesSync([10, 20, 30]);
      final now = DateTime.now().toUtc();
      final text = repo.insert(makeText('export me'));
      final tag = repo.upsertTag(name: 'Idea');
      repo.attachTag(noteId: text.id, tagId: tag.id);
      repo.insert(
        Note(
          id: newUuidV7(),
          type: NoteType.photo,
          mediaUri: mediaFile.path,
          mediaHash: sha256OfFile(mediaFile.path),
          createdAt: now,
          updatedAt: now,
          deviceId: 'test-device',
          rev: 1,
          syncState: SyncState.pending,
        ),
      );

      final archivePath = p.join(tmp.path, 'export.zip');
      final archive = await repo.exportArchive(
        outputPath: archivePath,
        mediaRoot: mediaDir.path,
      );
      final payload = SqliteNoteRepository.readExportJson(archive);
      final exportedNotes =
          (payload['notes'] as List).cast<Map<String, dynamic>>();
      expect(exportedNotes, hasLength(2));
      final exportedText =
          exportedNotes.firstWhere((n) => n['type'] == 'text');
      expect(exportedText['content'], 'export me');
      expect((exportedText['tags'] as List).first['name'], 'Idea');
      final exportedPhoto =
          exportedNotes.firstWhere((n) => n['type'] == 'photo');
      expect(exportedPhoto['media_hash'], sha256OfFile(mediaFile.path));
    });
  });

  group('1.10 backup & restore after corruption', () {
    test('restore recovers notes after simulated DB corruption', () {
      repo.insert(makeText('precious'));
      final backupDir = p.join(tmp.path, 'backups');
      final backup = repo.backup(backupDir);
      expect(backup.existsSync(), isTrue);

      // Simulate corruption: truncate live DB.
      db.close();
      File(p.join(tmp.path, 'nex.sqlite')).writeAsBytesSync([0, 1, 2]);

      NexDatabase.restoreFromBackup(
        liveDbPath: p.join(tmp.path, 'nex.sqlite'),
        backupFile: backup.path,
      );
      db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
      repo = SqliteNoteRepository(db);
      expect(repo.listTimeline().single.content, 'precious');
    });

    test('corrupt backup leaves live database intact (ADR-026)', () {
      repo.insert(makeText('must-survive'));
      db.close();

      final livePath = p.join(tmp.path, 'nex.sqlite');
      final liveBytesBefore = File(livePath).readAsBytesSync();
      expect(liveBytesBefore, isNotEmpty);

      final corruptBackup = File(p.join(tmp.path, 'corrupt.sqlite'))
        ..writeAsBytesSync([0x00, 0x01, 0x02, 0x03, 0xFF]);

      expect(
        () => NexDatabase.restoreFromBackup(
          liveDbPath: livePath,
          backupFile: corruptBackup.path,
        ),
        throwsA(isA<StateError>()),
      );

      // Live file must be byte-identical — never deleted on failed restore.
      expect(File(livePath).existsSync(), isTrue);
      expect(File(livePath).readAsBytesSync(), liveBytesBefore);
      expect(File('$livePath.restoring').existsSync(), isFalse);

      db = NexDatabase.open(livePath);
      repo = SqliteNoteRepository(db);
      expect(repo.listTimeline().single.content, 'must-survive');
    });
  });
}
