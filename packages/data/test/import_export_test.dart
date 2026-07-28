import 'dart:io';
import 'dart:typed_data';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// An export is only worth having if it can be read back.
///
/// These tests are the round trip: write a library out, open a fresh empty one,
/// read the archive in, and check that what comes back is the same library —
/// text, tags, enrichment and media alike.
void main() {
  late Directory tmp;
  late NexDatabase source;
  late SqliteNoteRepository sourceRepo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_roundtrip_');
    source = NexDatabase.open(p.join(tmp.path, 'source.sqlite'));
    sourceRepo = SqliteNoteRepository(source, localDeviceId: 'device-a');
  });

  tearDown(() {
    source.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Note text(String content) {
    final now = DateTime.now().toUtc();
    return Note(
      id: newUuidV7(),
      type: NoteType.text,
      content: content,
      createdAt: now,
      updatedAt: now,
      deviceId: 'device-a',
      rev: 1,
      syncState: SyncState.pending,
    );
  }

  /// A second, empty library, standing in for a new phone.
  (NexDatabase, SqliteNoteRepository) freshTarget(String name) {
    final db = NexDatabase.open(p.join(tmp.path, '$name.sqlite'));
    return (db, SqliteNoteRepository(db, localDeviceId: 'device-b'));
  }

  Future<File> exportSource() => sourceRepo.exportArchive(
        outputPath: p.join(tmp.path, 'export.zip'),
        mediaRoot: p.join(tmp.path, 'media'),
      );

  test('notes, tags and enrichment survive the round trip', () async {
    final note = sourceRepo.insert(text('the thing I wrote down'));
    sourceRepo.setCaption(note.id, 'a caption');
    final tag = sourceRepo.upsertTag(name: 'Work', color: '#F0A93B');
    sourceRepo.attachTag(noteId: note.id, tagId: tag.id);

    final archive = await exportSource();
    final (db, target) = freshTarget('target');
    addTearDown(db.close);

    final result = await target.importArchive(
      archiveFile: archive,
      mediaRoot: p.join(tmp.path, 'target-media'),
    );

    expect(result.imported, 1);
    expect(result.skipped, 0);
    final restored = target.getById(note.id)!;
    expect(restored.content, 'the thing I wrote down');
    // applyRemoteNote does not carry captions — they are not on the sync wire —
    // so an import that only used it would silently drop them.
    expect(restored.caption, 'a caption');
    expect(restored.tags.map((t) => t.name), ['Work']);
    expect(restored.tags.single.color, '#F0A93B');
  });

  test('media travels with the archive and lands in this device\'s folder',
      () async {
    final mediaDir = Directory(p.join(tmp.path, 'media'))..createSync();
    final photo = File(p.join(mediaDir.path, 'shot.jpg'))
      ..writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4, 5]));
    final now = DateTime.now().toUtc();
    final note = sourceRepo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.photo,
        mediaUri: photo.path,
        mediaHash: 'abc123',
        createdAt: now,
        updatedAt: now,
        deviceId: 'device-a',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );

    final archive = await exportSource();
    final (db, target) = freshTarget('target-media-db');
    addTearDown(db.close);
    final targetMedia = p.join(tmp.path, 'target-media');

    await target.importArchive(archiveFile: archive, mediaRoot: targetMedia);

    final restored = target.getById(note.id)!;
    // The old device's path means nothing here, so the stored one has to point
    // at the copy that just landed.
    expect(restored.mediaUri, isNot(photo.path));
    expect(p.dirname(restored.mediaUri!), targetMedia);
    expect(File(restored.mediaUri!).readAsBytesSync(), [1, 2, 3, 4, 5]);
  });

  test('importing the same archive twice changes nothing', () async {
    sourceRepo.insert(text('once'));
    final archive = await exportSource();
    final (db, target) = freshTarget('twice');
    addTearDown(db.close);
    final media = p.join(tmp.path, 'twice-media');

    final first =
        await target.importArchive(archiveFile: archive, mediaRoot: media);
    final second =
        await target.importArchive(archiveFile: archive, mediaRoot: media);

    expect(first.imported, 1);
    expect(second.imported, 0, reason: 'nothing new the second time');
    expect(second.skipped, 1);
    expect(target.listTimeline(limit: 50).length, 1);
  });

  test('an import never rolls an existing note back', () async {
    final note = sourceRepo.insert(text('original'));
    final archive = await exportSource();
    // The same note, edited after the export was taken.
    sourceRepo.updateContent(note.id, 'edited since the export');

    await sourceRepo.importArchive(
      archiveFile: archive,
      mediaRoot: p.join(tmp.path, 'media'),
    );

    expect(sourceRepo.getById(note.id)!.content, 'edited since the export');
  });

  test('a file that is not an export is refused, and nothing is written',
      () async {
    final junk = File(p.join(tmp.path, 'holiday.zip'))
      ..writeAsBytesSync([0x50, 0x4B, 0x05, 0x06, ...List.filled(18, 0)]);
    final (db, target) = freshTarget('junk');
    addTearDown(db.close);

    await expectLater(
      target.importArchive(
        archiveFile: junk,
        mediaRoot: p.join(tmp.path, 'junk-media'),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(target.listTimeline(limit: 50), isEmpty);
  });

  test('a note whose media is missing from the archive still comes in',
      () async {
    final now = DateTime.now().toUtc();
    final note = sourceRepo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.photo,
        // Points at a file that is not there, so the export has no media entry.
        mediaUri: p.join(tmp.path, 'media', 'gone.jpg'),
        caption: 'the caption is the whole note now',
        createdAt: now,
        updatedAt: now,
        deviceId: 'device-a',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );

    final archive = await exportSource();
    final (db, target) = freshTarget('missing-media');
    addTearDown(db.close);

    final result = await target.importArchive(
      archiveFile: archive,
      mediaRoot: p.join(tmp.path, 'missing-media-dir'),
    );

    expect(result.imported, 1);
    final restored = target.getById(note.id)!;
    expect(restored.mediaUri, isNull);
    expect(restored.caption, 'the caption is the whole note now');
  });
}
