import 'dart:io';
import 'dart:typed_data';

import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Enrichment runs once, at capture. The intelligence layer is off by default,
/// so at the moment a user turns it on, every note they already have was
/// captured while nothing could read it — and without a backfill, none of them
/// ever would be.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_backfill_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db, localDeviceId: 'test');
  });

  tearDown(() {
    db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Note media(NoteType type, String name) {
    final file = File(p.join(tmp.path, name))
      ..writeAsBytesSync(Uint8List.fromList([1, 2, 3]));
    final now = DateTime.now().toUtc();
    return repo.insert(
      Note(
        id: newUuidV7(),
        type: type,
        mediaUri: file.path,
        mediaHash: 'hash-$name',
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  test(
    'a voice note with no transcript is pending; one with a transcript is not',
    () {
      final pending = media(NoteType.voice, 'a.m4a');
      final done = media(NoteType.voice, 'b.m4a');
      repo.setTranscriptText(done.id, 'already read');

      final found = repo.listNeedingEnrichment(limit: 10);

      expect(found.map((n) => n.id), [pending.id]);
    },
  );

  test('a text note is never pending — it is already its own text', () {
    final now = DateTime.now().toUtc();
    repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.text,
        content: 'a written thought',
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );

    expect(repo.listNeedingEnrichment(limit: 10), isEmpty);
  });

  test('a deleted note is not pending', () {
    final note = media(NoteType.photo, 'gone.jpg');
    repo.softDelete(note.id);

    expect(repo.listNeedingEnrichment(limit: 10), isEmpty);
  });

  test('backfill reads the notes captured before the layer existed', () async {
    final voice = media(NoteType.voice, 'clip.m4a');
    final photo = media(NoteType.photo, 'shot.jpg');
    final service = EnrichmentService(
      repo: repo,
      adapter: _WorkingAdapter(),
      capabilities: const AiCapabilities(),
    );

    final done = await service.backfill();

    expect(done, 2);
    expect(repo.getById(voice.id)!.transcriptText, 'transcribed');
    expect(repo.getById(photo.id)!.ocrText, 'read from the image');
    // And there is nothing left to do, so a second pass is free.
    expect(await service.backfill(), 0);
  });

  test('backfill stops at the first note that produces nothing', () async {
    // What an exhausted free-tier quota looks like from here. Spending the rest
    // of the backlog to learn the same thing is the failure mode to avoid.
    for (var i = 0; i < 5; i++) {
      media(NoteType.voice, 'clip$i.m4a');
    }
    final adapter = _FailingAdapter();
    final service = EnrichmentService(repo: repo, adapter: adapter);

    final done = await service.backfill();

    expect(done, 0);
    expect(adapter.calls, 1, reason: 'it did not walk the whole backlog');
  });

  test('backfill does nothing while the capabilities are off', () async {
    media(NoteType.voice, 'clip.m4a');
    final adapter = _WorkingAdapter();
    final service = EnrichmentService(
      repo: repo,
      adapter: adapter,
      capabilities: const AiCapabilities(transcription: false, ocr: false),
    );

    expect(await service.backfill(), 0);
    expect(adapter.calls, 0);
  });
}

class _WorkingAdapter implements AIAdapter {
  int calls = 0;

  @override
  Future<Transcript>? transcribe(AudioRef audio) async {
    calls++;
    return const Transcript(text: 'transcribed');
  }

  @override
  Future<OCRText>? ocr(ImageRef image) async {
    calls++;
    return const OCRText(text: 'read from the image');
  }

  @override
  Future<Vector>? embed(String text) => null;

  @override
  Future<List<TagSuggestion>>? suggestTags(Note note) => null;

  @override
  Future<Summary>? summarize(Note note) => null;
}

class _FailingAdapter implements AIAdapter {
  int calls = 0;

  @override
  Future<Transcript>? transcribe(AudioRef audio) async {
    calls++;
    throw StateError('429 rate limited');
  }

  @override
  Future<OCRText>? ocr(ImageRef image) async {
    calls++;
    throw StateError('429 rate limited');
  }

  @override
  Future<Vector>? embed(String text) => null;

  @override
  Future<List<TagSuggestion>>? suggestTags(Note note) => null;

  @override
  Future<Summary>? summarize(Note note) => null;
}
