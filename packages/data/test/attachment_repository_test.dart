import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Several files on one note — `docs/14-attachments.md`, step 1: the data,
/// behind no screen.
void main() {
  late Directory tmp;
  late String dbPath;
  late String mediaDir;
  late NexDatabase db;
  late SqliteNoteRepository notes;
  late SqliteAttachmentRepository attachments;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_attach_');
    dbPath = p.join(tmp.path, 'nex.sqlite');
    mediaDir = p.join(tmp.path, 'media');
    Directory(mediaDir).createSync(recursive: true);
    db = NexDatabase.open(dbPath);
    notes = SqliteNoteRepository(db, localDeviceId: 'device-a');
    attachments = SqliteAttachmentRepository(notes, localDeviceId: 'device-a');
  });

  tearDown(() {
    try {
      db.close();
    } catch (_) {}
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Note note(NoteType type, {String? content, String? mediaUri}) {
    final now = DateTime.now().toUtc();
    return notes.insert(
      Note(
        id: newUuidV7(),
        type: type,
        content: content,
        mediaUri: mediaUri,
        createdAt: now,
        updatedAt: now,
        deviceId: 'device-a',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  String file(String name, List<int> bytes) {
    final path = p.join(mediaDir, name);
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  NoteAttachment attach(String noteId, String name, {String? caption}) {
    final path = file(name, name.codeUnits);
    return attachments.add(
      noteId,
      kind: AttachmentKind.photo,
      mediaUri: path,
      mediaHash: sha256OfBytes(File(path).readAsBytesSync()),
      mimeType: 'image/jpeg',
      caption: caption,
    )!;
  }

  String ftsOf(String noteId) =>
      (db.db.select('SELECT content FROM notes_fts WHERE note_id = ?', [
            noteId,
          ]).firstOrNull?['content']
          as String?) ??
      '';

  group('the table', () {
    test('a library from before attachments upgrades with nothing moved', () {
      final own = file('own.jpg', [1, 2, 3]);
      final photo = note(NoteType.photo, mediaUri: own);
      // An older build's library: no table at all.
      db.db.execute('DROP TABLE note_attachments');
      db.close();

      db = NexDatabase.open(dbPath);
      notes = SqliteNoteRepository(db, localDeviceId: 'device-a');
      attachments = SqliteAttachmentRepository(
        notes,
        localDeviceId: 'device-a',
      );
      expect(notes.getById(photo.id)!.mediaUri, own);
      expect(attachments.forNote(photo.id), isEmpty);
      expect(
        db.db.select('SELECT COUNT(*) AS n FROM note_attachments').first['n'],
        0,
      );
    });
  });

  group('one note, several files', () {
    test('they come back in order, after the note\'s own, from 1', () {
      final photo = note(NoteType.photo, mediaUri: file('own.jpg', [0]));
      final a = attach(photo.id, 'b.jpg');
      final b = attach(photo.id, 'c.jpg');
      expect(attachments.forNote(photo.id).map((x) => x.id), [a.id, b.id]);
      expect(a.position, 1);
      expect(b.position, 2);
      // The note's own file is where it was.
      expect(notes.getById(photo.id)!.mediaUri, p.join(mediaDir, 'own.jpg'));
      expect(attachments.countsFor([photo.id, 'other']), {photo.id: 2});
    });

    test('a text note can carry files, though it has none of its own', () {
      final text = note(NoteType.text, content: 'receipt for the fridge');
      attach(text.id, 'receipt.jpg');
      expect(attachments.forNote(text.id), hasLength(1));
      expect(notes.getById(text.id)!.mediaUri, isNull);
    });

    test('reordered, captioned and removed', () {
      final photo = note(NoteType.photo);
      final a = attach(photo.id, 'a.jpg');
      final b = attach(photo.id, 'b.jpg');
      final c = attach(photo.id, 'c.jpg');

      attachments.reorder(photo.id, [c.id, a.id]);
      expect(attachments.forNote(photo.id).map((x) => x.id), [
        c.id,
        a.id,
        b.id,
      ]);
      expect(attachments.forNote(photo.id).map((x) => x.position), [1, 2, 3]);

      attachments.setCaption(b.id, 'the side panel');
      expect(attachments.forNote(photo.id).last.caption, 'the side panel');
      attachments.setCaption(b.id, '   ');
      expect(attachments.forNote(photo.id).last.caption, isNull);

      attachments.remove(a.id);
      expect(attachments.forNote(photo.id).map((x) => x.id), [c.id, b.id]);
      // A tombstone stays, for sync.
      final row = db.db.select(
        'SELECT deleted_at, rev FROM note_attachments WHERE id = ?',
        [a.id],
      ).first;
      expect(row['deleted_at'], isNotNull);
      expect(row['rev'], greaterThan(1));
    });

    test('a removed one comes back at the end, and the count follows', () {
      final photo = note(NoteType.photo);
      final text = note(NoteType.text, content: 'no files');
      final a = attach(photo.id, 'a.jpg');
      final b = attach(photo.id, 'b.jpg');
      expect(attachments.countsFor([photo.id, text.id]), {photo.id: 2});

      attachments.remove(a.id);
      expect(attachments.countsFor([photo.id])[photo.id], 1);
      expect(notes.getById(photo.id)!.attachmentCount, 1);

      expect(attachments.restore(a.id), isTrue);
      expect(attachments.forNote(photo.id).map((x) => x.id), [b.id, a.id]);
      expect(notes.getById(photo.id)!.attachmentCount, 2);
      // Restoring one that is live, or gone, changes nothing.
      expect(attachments.restore(a.id), isFalse);
      expect(attachments.restore('missing'), isFalse);
    });

    test('nothing attaches to a note that is not there', () {
      expect(
        attachments.add(
          'missing',
          kind: AttachmentKind.file,
          mediaUri: file('x.pdf', [1]),
          mediaHash: 'h',
        ),
        isNull,
      );
    });

    test('a word in the third photo finds the note', () {
      final photo = note(NoteType.photo);
      attach(photo.id, 'a.jpg');
      final b = attach(photo.id, 'b.jpg', caption: 'serial number');
      attachments.setOcrText(b.id, 'SN-48213 warranty');
      expect(ftsOf(photo.id), contains('48213'));
      expect(ftsOf(photo.id), contains('serial'));

      attachments.remove(b.id);
      expect(ftsOf(photo.id), isNot(contains('48213')));
    });
  });

  group('files are kept and freed with their rows', () {
    late LibraryMaintenance maintenance;
    setUp(() => maintenance = LibraryMaintenance(notes, mediaRoot: mediaDir));

    test('purging a note from the trash takes its attachments\' files', () {
      final photo = note(NoteType.photo, mediaUri: file('own.jpg', [1]));
      final a = attach(photo.id, 'a.jpg');
      notes.softDelete(photo.id);
      maintenance.purgeNote(photo.id);
      expect(File(a.mediaUri).existsSync(), isFalse);
      expect(File(p.join(mediaDir, 'own.jpg')).existsSync(), isFalse);
      expect(
        db.db.select('SELECT 1 FROM note_attachments WHERE id = ?', [a.id]),
        isEmpty,
      );
    });

    test('a file another note still holds is not deleted', () {
      final first = note(NoteType.photo);
      final second = note(NoteType.photo);
      final shared = attach(first.id, 'shared.jpg');
      attachments.add(
        second.id,
        kind: AttachmentKind.photo,
        mediaUri: shared.mediaUri,
        mediaHash: shared.mediaHash,
      );
      notes.softDelete(first.id);
      maintenance.purgeAllDeleted();
      expect(File(shared.mediaUri).existsSync(), isTrue);
    });

    test('the sweep keeps live attachments and frees removed ones', () {
      final photo = note(NoteType.photo);
      final kept = attach(photo.id, 'kept.jpg');
      final gone = attach(photo.id, 'gone.jpg');
      attachments.remove(gone.id);
      final removed = maintenance.sweepOrphanMedia(minAge: Duration.zero);
      expect(removed, 1);
      expect(File(kept.mediaUri).existsSync(), isTrue);
      expect(File(gone.mediaUri).existsSync(), isFalse);
    });

    test('a trashed note keeps its attachments, to be restored', () {
      final photo = note(NoteType.photo);
      final a = attach(photo.id, 'a.jpg');
      notes.softDelete(photo.id);
      maintenance.sweepOrphanMedia(minAge: Duration.zero);
      expect(File(a.mediaUri).existsSync(), isTrue);
    });
  });

  group('round trips', () {
    test('an export carries the attachments, and an import brings them '
        'back with their words', () async {
      final photo = note(NoteType.photo, mediaUri: file('own.jpg', [9]));
      final a = attach(photo.id, 'side.jpg', caption: 'the left side');
      // Same name as the note's own file: the export keeps both.
      attachments.add(
        photo.id,
        kind: AttachmentKind.photo,
        mediaUri: p.join(tmp.path, 'elsewhere', 'own.jpg'),
        mediaHash: 'other',
      );
      Directory(p.join(tmp.path, 'elsewhere')).createSync();
      File(p.join(tmp.path, 'elsewhere', 'own.jpg')).writeAsBytesSync([7, 7]);

      final archive = await notes.exportArchive(
        outputPath: p.join(tmp.path, 'export.zip'),
        mediaRoot: mediaDir,
      );

      final targetDb = NexDatabase.open(p.join(tmp.path, 'target.sqlite'));
      addTearDown(targetDb.close);
      final targetNotes = SqliteNoteRepository(
        targetDb,
        localDeviceId: 'device-b',
      );
      final targetMedia = p.join(tmp.path, 'target-media');
      await targetNotes.importArchive(
        archiveFile: archive,
        mediaRoot: targetMedia,
      );
      final back = SqliteAttachmentRepository(
        targetNotes,
        localDeviceId: 'device-b',
      ).forNote(photo.id);
      expect(back, hasLength(2));
      expect(back.first.id, a.id);
      expect(back.first.caption, 'the left side');
      expect(p.isWithin(targetMedia, back.first.mediaUri), isTrue);
      expect(File(back.first.mediaUri).readAsStringSync(), 'side.jpg');
      expect(File(back.last.mediaUri).readAsBytesSync(), [7, 7]);
      expect(File(targetNotes.getById(photo.id)!.mediaUri!).readAsBytesSync(), [
        9,
      ]);
      final fts = targetDb.db.select(
        'SELECT content FROM notes_fts WHERE note_id = ?',
        [photo.id],
      ).first['content'];
      expect(fts, contains('left'));

      // Importing again changes nothing.
      await targetNotes.importArchive(
        archiveFile: archive,
        mediaRoot: targetMedia,
      );
      expect(
        targetDb.db
            .select('SELECT COUNT(*) AS n FROM note_attachments')
            .first['n'],
        2,
      );
    });

    test('a complete backup packs attachment files and restores them', () {
      final photo = note(NoteType.photo, mediaUri: file('own.jpg', [1]));
      final a = attach(photo.id, 'second.jpg');
      final backup = notes.backup(
        p.join(tmp.path, 'backups'),
        mediaDir: mediaDir,
      );
      db.close();
      File(a.mediaUri).deleteSync();

      NexBackupArchive.restore(
        liveDbPath: dbPath,
        mediaDir: mediaDir,
        backupFile: backup.path,
      );
      db = NexDatabase.open(dbPath);
      notes = SqliteNoteRepository(db, localDeviceId: 'device-a');
      final restored = SqliteAttachmentRepository(
        notes,
        localDeviceId: 'device-a',
      ).forNote(photo.id).single;
      expect(File(restored.mediaUri).readAsStringSync(), 'second.jpg');
    });
  });
}
