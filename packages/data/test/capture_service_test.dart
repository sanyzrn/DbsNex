import 'dart:typed_data';

import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:test/test.dart';

void main() {
  late NexDatabase db;
  late SqliteNoteRepository repo;
  late CaptureService capture;
  late TagService tags;
  late SearchService search;

  setUp(() {
    db = NexDatabase.openInMemory();
    repo = SqliteNoteRepository(db);
    capture = CaptureService(repo, deviceId: 'core-test');
    tags = TagService(repo);
    search = SearchService(repo);
  });

  tearDown(() => db.close());

  group('1.2 core use cases', () {
    test('submitTextCapture discards empty and saves non-empty', () {
      expect(capture.submitTextCapture(''), isNull);
      final note = capture.submitTextCapture('idea');
      expect(note, isNotNull);
      expect(note!.content, 'idea');
      expect(note.type, NoteType.text);
      expect(note.deviceId, 'core-test');
      expect(note.rev, 1);
    });

    test('submitVoiceCapture stores media_hash and duration', () {
      final bytes = Uint8List.fromList([9, 8, 7]);
      final note = capture.submitVoiceCapture(
        mediaUri: '/tmp/a.m4a',
        mediaHash: sha256OfBytes(bytes),
        durationMs: 1500,
      );
      expect(note.type, NoteType.voice);
      expect(note.mediaHash, sha256OfBytes(bytes));
      expect(note.durationMs, 1500);
      expect(note.content, isNull);
    });

    test('submitPhotoCapture stores media_hash', () {
      final bytes = Uint8List.fromList([1, 1, 1]);
      final note = capture.submitPhotoCapture(
        mediaUri: '/tmp/p.jpg',
        mediaHash: sha256OfBytes(bytes),
      );
      expect(note.type, NoteType.photo);
      expect(note.mediaHash, sha256OfBytes(bytes));
    });

    test('addTag and removeTag', () {
      final note = capture.submitTextCapture('n')!;
      final tag = tags.addTag(noteId: note.id, name: 'Work');
      expect(search.timeline().first.tags.map((t) => t.name), ['Work']);
      tags.removeTag(noteId: note.id, tagId: tag.id);
      expect(search.timeline().first.tags, isEmpty);
    });

    test('search filters by query and type', () {
      capture.submitTextCapture('findme please');
      capture.submitTextCapture('other');
      final hits = search.search(const SearchFilters(query: 'findme'));
      expect(hits, hasLength(1));
      expect(
        search.search(const SearchFilters(types: [NoteType.text])),
        hasLength(2),
      );
    });

    test('no Save concept — capture returns persisted note immediately', () {
      final before = DateTime.now().toUtc();
      final note = capture.submitTextCapture('instant')!;
      expect(
        note.createdAt.isBefore(before.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(repo.getById(note.id)?.content, 'instant');
    });

    test('a very large paste is stored and searchable, no truncation', () {
      // There is no capture-time length limit by design (FR: zero friction) —
      // this pins down that "no limit" does not silently mean "gets cut off"
      // or "the FTS index chokes" once someone actually pastes a few
      // megabytes of text into the capture field.
      final huge = 'needle ${'word ' * 500000}haystack';
      final note = capture.submitTextCapture(huge)!;
      expect(repo.getById(note.id)?.content, huge);
      expect(
        search.search(const SearchFilters(query: 'needle haystack')),
        hasLength(1),
      );
    });
  });
}
