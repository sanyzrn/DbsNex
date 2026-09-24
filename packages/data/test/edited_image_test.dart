import 'package:nex_data/nex_data.dart';
import 'package:test/test.dart';

void main() {
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    db = NexDatabase.openInMemory();
    repo = SqliteNoteRepository(db, localDeviceId: 'editor');
  });

  tearDown(() => db.close());

  Note imageNote(NoteType type, {String? mimeType}) {
    final now = DateTime.utc(2026, 9, 24);
    return repo.insert(
      Note(
        id: newUuidV7(),
        type: type,
        mediaUri: '/media/original.jpg',
        mediaHash: 'old-hash',
        mimeType: mimeType,
        caption: 'keep this caption',
        createdAt: now,
        updatedAt: now,
        deviceId: 'editor',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  for (final type in [NoteType.photo, NoteType.file]) {
    test('editing $type keeps the note and replaces its image metadata', () {
      final original = imageNote(type);
      repo.setOcrText(original.id, 'old image words');

      repo.updateImageMedia(original.id, '/media/edited.png', 'new-hash');

      final edited = repo.getById(original.id)!;
      expect(edited.type, type);
      expect(edited.mediaUri, '/media/edited.png');
      expect(edited.mediaHash, 'new-hash');
      expect(edited.mimeType, 'image/png');
      expect(edited.caption, 'keep this caption');
      expect(edited.createdAt, original.createdAt);
      expect(edited.rev, greaterThan(original.rev));
      expect(edited.ocrText, isNull);
    });
  }

  test('editing a non-image note is rejected without changing it', () {
    final now = DateTime.utc(2026, 9, 24);
    final text = repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.text,
        content: 'Original',
        createdAt: now,
        updatedAt: now,
        deviceId: 'editor',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );

    expect(
      () => repo.updateImageMedia(text.id, '/media/edited.png', 'hash'),
      throwsStateError,
    );
    expect(repo.getById(text.id)!.content, 'Original');
  });
}
