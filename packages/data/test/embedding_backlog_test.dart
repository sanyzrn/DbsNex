import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_embed_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db);
  });

  tearDown(() {
    db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Note note(String id, {String? content, String? ocr, NoteType? type}) {
    final now = DateTime.now().toUtc();
    return Note(
      id: id,
      type: type ?? NoteType.text,
      content: content,
      ocrText: ocr,
      mediaUri: type == NoteType.photo ? '/tmp/$id.jpg' : null,
      createdAt: now,
      updatedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    );
  }

  test('written notes are in the embedding backlog', () {
    // The gap this closes: a text note needs nothing derived from it, so it
    // never appeared in the enrichment backlog — and nothing else ever
    // embedded it. A library written before a provider was configured had no
    // vectors, and semantic search over it found nothing, forever.
    repo.insert(note('n1', content: 'the cooler is broken'));
    expect(repo.listNeedingEnrichment(), isEmpty);
    expect(repo.listNeedingEmbedding().single.id, 'n1');
  });

  test('a note leaves the backlog once it has a vector', () {
    repo.insert(note('n1', content: 'something'));
    repo.setEmbedding('n1', [0.1, 0.2, 0.3]);
    expect(repo.listNeedingEmbedding(), isEmpty);
  });

  test('a photo with nothing read out of it yet is not embedded', () {
    // Embedding it now would store a vector for an empty string and it would
    // never be reconsidered. It comes back round once OCR has run.
    repo.insert(note('n1', type: NoteType.photo));
    expect(repo.listNeedingEmbedding(), isEmpty);
    repo.setOcrText('n1', 'a receipt for the cooler');
    expect(repo.listNeedingEmbedding().single.id, 'n1');
  });

  test('deleted notes are not queued', () {
    repo.insert(note('n1', content: 'gone'));
    repo.softDelete('n1');
    expect(repo.listNeedingEmbedding(), isEmpty);
  });

  test('newest first, and bounded by the limit', () {
    for (var i = 0; i < 5; i++) {
      repo.insert(note('n$i', content: 'note $i'));
    }
    final page = repo.listNeedingEmbedding(limit: 2);
    expect(page.length, 2);
  });
}
