import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// An exported note's Markdown links to the file the archive actually holds.
///
/// Two photos with the same file name are both kept — the second under its
/// note's id — but the second note's Markdown used to link to the bare name,
/// so opened outside Nex it showed the first note's photo.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_md_media_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db, localDeviceId: 'device');
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Note photo(String folder, String bytes) {
    final file = File(p.join(tmp.path, 'media', folder, 'IMG_0001.jpg'))
      ..createSync(recursive: true)
      ..writeAsStringSync(bytes);
    final now = DateTime.now().toUtc();
    return repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.photo,
        mediaUri: file.path,
        mediaHash: bytes,
        createdAt: now,
        updatedAt: now,
        deviceId: 'device',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  test('each photo note links to its own file in the archive', () async {
    final first = photo('a', 'first-photo');
    final second = photo('b', 'second-photo');
    final out = await repo.exportArchive(
      outputPath: p.join(tmp.path, 'export.zip'),
      mediaRoot: p.join(tmp.path, 'media'),
    );
    final archive = ZipDecoder().decodeBytes(out.readAsBytesSync());
    String text(String name) =>
        utf8.decode(archive.findFile(name)!.content as List<int>);

    for (final (note, bytes) in [
      (first, 'first-photo'),
      (second, 'second-photo'),
    ]) {
      final markdown = text('markdown/${note.id}.md');
      final link = RegExp(r'!\[photo\]\(\.\./media/([^)]+)\)')
          .firstMatch(markdown)!
          .group(1)!;
      expect(text('media/$link'), bytes, reason: 'note ${note.id}');
    }
  });

  test('a note whose file is missing still names it', () async {
    final now = DateTime.now().toUtc();
    final note = repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.photo,
        mediaUri: p.join(tmp.path, 'media', 'gone.jpg'),
        mediaHash: 'gone',
        createdAt: now,
        updatedAt: now,
        deviceId: 'device',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
    final out = await repo.exportArchive(
      outputPath: p.join(tmp.path, 'export.zip'),
      mediaRoot: p.join(tmp.path, 'media'),
    );
    final archive = ZipDecoder().decodeBytes(out.readAsBytesSync());
    final markdown = utf8.decode(
      archive.findFile('markdown/${note.id}.md')!.content as List<int>,
    );
    expect(markdown, contains('![photo](../media/gone.jpg)'));
  });
}
