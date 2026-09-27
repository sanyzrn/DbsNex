import 'package:nex_data/nex_data.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Markdown round trip retains identity and metadata and is searchable',
    () {
      final db = NexDatabase.openInMemory();
      addTearDown(db.close);
      final repo = SqliteNoteRepository(db, localDeviceId: 'test');
      final now = DateTime.utc(2026);
      final note = repo.insert(
        Note(
          id: newUuidV7(),
          type: NoteType.text,
          content: '# فارسی Generator',
          title: 'Keep title',
          caption: 'Keep caption',
          createdAt: now,
          updatedAt: now,
          deviceId: 'test',
          rev: 1,
          syncState: SyncState.pending,
        ),
      );
      repo.pinNote(note.id);
      repo.convertMarkdown(note.id, note.content!, '/media/note.md', 'hash');
      final file = repo.getById(note.id)!;
      expect(file.type, NoteType.file);
      expect(file.originalFilename, 'note.md');
      expect(file.ocrText, note.content);
      expect(file.title, 'Keep title');
      expect(file.pinnedAt, isNotNull);
      expect(
        repo.search(const SearchFilters(query: 'tor')).map((n) => n.id),
        contains(note.id),
      );
      repo.convertMarkdown(note.id, note.content!, null, null);
      final restored = repo.getById(note.id)!;
      expect(restored.type, NoteType.text);
      expect(restored.content, note.content);
      expect(restored.caption, 'Keep caption');
      expect(restored.mediaUri, isNull);
      expect(restored.createdAt, now);
      expect(restored.rev, 3);
      expect(
        repo.search(const SearchFilters(query: 'tor')).map((n) => n.id),
        contains(note.id),
      );
      expect(
        () => repo.convertMarkdown(note.id, 'no', null, null),
        throwsStateError,
      );
      expect(repo.getById(note.id)!.content, note.content);
    },
  );
}
