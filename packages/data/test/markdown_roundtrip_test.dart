import 'dart:io';

import 'package:archive/archive.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:test/test.dart';

void main() {
  test(
    'actual exported Markdown preserves text, title, checklist, date and tags',
    () async {
      final tmp = Directory.systemTemp.createTempSync(
        'nex_markdown_roundtrip_',
      );
      addTearDown(() => tmp.deleteSync(recursive: true));
      final db = NexDatabase.open('${tmp.path}/source.sqlite');
      addTearDown(db.close);
      final repo = SqliteNoteRepository(db, localDeviceId: 'source');
      final at = DateTime.utc(2024, 3, 20, 10, 30);
      final original = <Note>[];
      for (final (type, body, title) in [
        (NoteType.text, '# This is content\nمتن اصلی', null),
        (
          NoteType.text,
          'decisions\n- keep dates and numbers: 42',
          'عنوان "ویژه"',
        ),
        (NoteType.checklist, '- [x] فقط یک مورد', null),
      ]) {
        final note = repo.insert(
          Note(
            id: newUuidV7(),
            type: type,
            content: body,
            title: title,
            createdAt: at,
            updatedAt: at,
            deviceId: 'source',
            rev: 1,
            syncState: SyncState.pending,
          ),
        );
        for (final name in ['کار, مهم', 'a "quoted" tag', 'تست [الف]']) {
          final tag = repo.upsertTag(name: name);
          repo.attachTag(noteId: note.id, tagId: tag.id);
        }
        original.add(repo.getById(note.id)!);
      }
      final file = await repo.exportArchive(
        outputPath: '${tmp.path}/export.zip',
        mediaRoot: '${tmp.path}/media',
      );
      final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
      final parsed = NoteImport.readEntries([
        for (final entry in archive.files)
          if (entry.isFile) (entry.name, entry.readBytes()!),
      ]);
      expect(
        parsed.unreadable,
        0,
        reason: 'notes.json is metadata, not an unreadable note',
      );
      expect(parsed.notes, hasLength(original.length));
      for (final note in original) {
        final imported = parsed.notes.singleWhere(
          (candidate) => candidate.text == note.content,
        );
        expect(imported.title, note.title);
        expect(imported.createdAt, at);
        expect(imported.type, note.type);
        expect(
          imported.tags,
          unorderedEquals(note.tags.map((tag) => tag.name)),
        );
      }
      final target = NexDatabase.open('${tmp.path}/target.sqlite');
      addTearDown(target.close);
      final targetRepo = SqliteNoteRepository(target, localDeviceId: 'target');
      final written = CaptureService(
        targetRepo,
        deviceId: 'target',
      ).importNotes(parsed.notes);
      for (final note in written) {
        final read = targetRepo.getById(note.id)!;
        expect(read.displayText, isNot(contains(note.id)));
        expect(read.createdAt, at);
        expect(read.tags, hasLength(3));
      }
    },
  );
}
