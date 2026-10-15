import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:nex_core/nex_core.dart'
    show
        AiCapabilities,
        AudioRef,
        EnrichmentService,
        ImageRef,
        NullAIAdapter,
        OCRText,
        Transcript;
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

  group('reshaping', () {
    test(
      'editing keeps identity and order, clears old search words and keeps shared original',
      () {
        final text = note(NoteType.text, content: 'trip');
        final a = attach(text.id, 'ticket.jpg', caption: 'return ticket');
        final other = attach(text.id, 'other.jpg');
        attachments.setOcrResult(a.id, 'OLDSEAT 14C');
        attachments.rename(a.id, 'ticket.jpg');
        final before = attachments.byId(a.id)!;
        final replacement = file('edited.png', [8, 9]);
        expect(
          attachments.updateImageMedia(
            a.id,
            replacement,
            'new-hash',
            expectedMediaHash: a.mediaHash,
          ),
          isTrue,
        );
        final edited = attachments.byId(a.id)!;
        expect(edited.id, a.id);
        expect(edited.noteId, text.id);
        expect(edited.position, a.position);
        expect(edited.caption, 'return ticket');
        expect(edited.createdAt, a.createdAt);
        expect(edited.rev, before.rev + 1);
        expect(edited.mimeType, 'image/png');
        expect(edited.name, 'ticket.png');
        expect(edited.ocrText, isNull);
        expect(edited.mediaHash, 'new-hash');
        expect(attachments.forNote(text.id).map((a) => a.id), [a.id, other.id]);
        expect(ftsOf(text.id), isNot(contains('OLDSEAT')));
        expect(File(a.mediaUri).readAsStringSync(), 'ticket.jpg');
        // An older editor must not overwrite this replacement.
        expect(
          attachments.updateImageMedia(
            a.id,
            '/stale.png',
            'stale',
            expectedMediaHash: a.mediaHash,
          ),
          isFalse,
        );
        expect(attachments.byId(a.id)!.mediaUri, replacement);
        attachments.remove(a.id);
        expect(
          attachments.updateImageMedia(
            a.id,
            '/removed.png',
            'removed',
            expectedMediaHash: 'new-hash',
          ),
          isFalse,
        );
      },
    );

    test('file images can be edited, other files cannot', () {
      final text = note(NoteType.text, content: 'files');
      for (final ext in ['png', 'pdf']) {
        final a = attachments.add(
          text.id,
          kind: AttachmentKind.file,
          mediaUri: file('file.$ext', [1, 2]),
          mediaHash: ext,
        )!;
        expect(
          attachments.updateImageMedia(
            a.id,
            '/new.png',
            'new',
            expectedMediaHash: ext,
          ),
          ext == 'png',
        );
      }
    });

    test(
      'an old OCR response cannot repopulate an edited or removed photo',
      () async {
        final text = note(NoteType.text, content: 'screen');
        for (final remove in [false, true]) {
          final a = attach(text.id, 'screen-$remove.jpg');
          final reader = _DelayedReader();
          final service = EnrichmentService(
            repo: notes,
            adapter: reader,
            capabilities: AiCapabilities.allOn,
          );
          final pending = AttachmentTextReader(attachments, service).read(a.id);
          await reader.started.future;
          if (remove) {
            attachments.remove(a.id);
          } else {
            attachments.updateImageMedia(
              a.id,
              file('new.png', [7]),
              'new-hash',
              expectedMediaHash: a.mediaHash,
            );
          }
          reader.result.complete(const OCRText(text: 'STALEWORDS'));
          expect(await pending, isFalse);
          expect(attachments.byId(a.id)!.ocrText, isNull);
          expect(ftsOf(text.id), isNot(contains('STALEWORDS')));
        }
      },
    );

    test('a file can be renamed, and blank gives its own name back', () {
      final text = note(NoteType.text, content: 'contract');
      final a = attach(text.id, 'scan.jpg');
      attachments.rename(a.id, 'Annex B');
      expect(attachments.byId(a.id)!.name, 'Annex B');
      attachments.rename(a.id, '  ');
      expect(attachments.byId(a.id)!.name, isNull);
    });

    test('one becomes a note of its own, keeping its words', () {
      final text = note(NoteType.text, content: 'trip');
      final a = attach(text.id, 'ticket.jpg', caption: 'the return ticket');
      attachments.setOcrResult(a.id, 'SEAT 14C');
      final made = attachments.detach(a.id)!;
      expect(made.type, NoteType.photo);
      expect(made.mediaUri, a.mediaUri);
      expect(made.caption, 'the return ticket');
      expect(made.ocrText, 'SEAT 14C');
      expect(attachments.forNote(text.id), isEmpty);
      expect(notes.getById(text.id)!.attachmentCount, 0);
      expect(ftsOf(made.id), contains('14C'));
    });

    test('an attached photo can become the note\'s own, and back', () {
      final own = file('own.jpg', [9, 9]);
      final photo = note(NoteType.photo, mediaUri: own);
      db.db.execute('UPDATE notes SET media_hash = ? WHERE id = ?', [
        sha256OfBytes(File(own).readAsBytesSync()),
        photo.id,
      ]);
      notes.setCaption(photo.id, 'the front');
      final a = attach(photo.id, 'back.jpg', caption: 'the back');
      expect(attachments.promote(a.id), isTrue);
      final now = notes.getById(photo.id)!;
      expect(now.mediaUri, a.mediaUri);
      expect(now.caption, 'the back');
      final swapped = attachments.forNote(photo.id).single;
      expect(swapped.id, a.id);
      expect(swapped.mediaUri, own);
      expect(swapped.caption, 'the front');

      // A text note has no photo of its own to trade.
      final text = note(NoteType.text, content: 'words');
      final b = attach(text.id, 'c.jpg');
      expect(attachments.promote(b.id), isFalse);
    });
  });

  group('text in attached photos', () {
    test(
      'is read once, found by search, and leaves the note unedited',
      () async {
        final text = note(NoteType.text, content: 'warranty');
        final photo = attach(text.id, 'card.jpg');
        final editedBefore = notes.getById(text.id)!.updatedAt;
        final reader = _Reader('SERIAL 4471-B');
        final service = EnrichmentService(
          repo: notes,
          adapter: reader,
          capabilities: AiCapabilities.allOn,
        );
        final texts = AttachmentTextReader(attachments, service);

        expect(attachments.needingText().map((a) => a.id), [photo.id]);
        expect(await texts.read(photo.id), isTrue);
        expect(attachments.forNote(text.id).single.ocrText, 'SERIAL 4471-B');
        expect(ftsOf(text.id), contains('4471'));
        expect(notes.getById(text.id)!.updatedAt, editedBefore);

        // Read, so never asked again.
        expect(await texts.read(photo.id), isFalse);
        expect(reader.calls, 1);
        expect(attachments.needingText(), isEmpty);
      },
    );

    test('a photo with no words is read once and kept as read', () async {
      final text = note(NoteType.text, content: 'sky');
      final photo = attach(text.id, 'sky.jpg');
      final service = EnrichmentService(
        repo: notes,
        adapter: _Reader(''),
        capabilities: AiCapabilities.allOn,
      );
      expect(await AttachmentTextReader(attachments, service).backfill(), 1);
      expect(attachments.forNote(text.id).single.ocrText, '');
      expect(attachments.needingText(), isEmpty);
      expect(photo.ocrText, isNull);
    });

    test('an attached voice clip is transcribed and searched', () async {
      final text = note(NoteType.text, content: 'meeting');
      final clip = attachments.add(
        text.id,
        kind: AttachmentKind.voice,
        mediaUri: file('clip.m4a', [1, 2, 3]),
        mediaHash: sha256OfBytes(Uint8List.fromList([1, 2, 3])),
        durationMs: 4200,
      )!;
      final service = EnrichmentService(
        repo: notes,
        adapter: _Reader('budget for March'),
        capabilities: AiCapabilities.allOn,
      );
      expect(await AttachmentTextReader(attachments, service).backfill(), 1);
      expect(attachments.byId(clip.id)!.transcriptText, 'budget for March');
      expect(ftsOf(text.id), contains('budget'));
    });

    test('nothing is read while reading text in photos is off', () async {
      final text = note(NoteType.text, content: 'off');
      attach(text.id, 'a.jpg');
      final reader = _Reader('words');
      final service = EnrichmentService(repo: notes, adapter: reader);
      final texts = AttachmentTextReader(attachments, service);
      expect(await texts.backfill(), 0);
      expect(reader.calls, 0);
      expect(attachments.needingText(), hasLength(1));
    });
  });
}

/// Reads every image as [text], and counts the requests.
class _Reader extends NullAIAdapter {
  _Reader(this.text);

  final String text;
  var calls = 0;

  @override
  Future<OCRText>? ocr(ImageRef image) {
    calls++;
    return Future.value(OCRText(text: text));
  }

  @override
  Future<Transcript>? transcribe(AudioRef audio) {
    calls++;
    return Future.value(Transcript(text: text));
  }
}

class _DelayedReader extends NullAIAdapter {
  final started = Completer<void>();
  final result = Completer<OCRText>();
  @override
  Future<OCRText>? ocr(ImageRef image) {
    started.complete();
    return result.future;
  }
}
