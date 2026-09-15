import 'dart:io';

import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// An embedding is only comparable to embeddings from the same model at the
/// same endpoint. Change either and every stored vector becomes a number from
/// a different space — and cosine similarity will still return a number,
/// confidently, which is the worst way for this to fail.
///
/// So the library holds one space at a time. This is the record of it.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_embed_space_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db);
  });

  tearDown(() {
    db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Note note(String id) {
    final now = DateTime.now().toUtc();
    return Note(
      id: id,
      type: NoteType.text,
      content: 'note $id',
      createdAt: now,
      updatedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    );
  }

  test('the first space is recorded and keeps the vectors', () {
    // Nothing on file is not a mismatch — it is a library that has not
    // embedded anything yet. Clearing here would throw away the vectors
    // written moments earlier by the very backfill that prompted this.
    repo.insert(note('n1'));
    repo.setEmbedding('n1', [0.1, 0.2, 0.3]);

    expect(repo.embeddingSpace, isNull);
    expect(repo.setEmbeddingSpace('openai|https://api.openai.com/v1|small'),
        isFalse);
    expect(repo.embeddingSpace, 'openai|https://api.openai.com/v1|small');
    expect(repo.getEmbedding('n1'), isNotNull, reason: 'nothing changed');
  });

  test('the same space twice changes nothing', () {
    repo.insert(note('n1'));
    repo.setEmbeddingSpace('openai|https://api.openai.com/v1|small');
    repo.setEmbedding('n1', [0.1, 0.2, 0.3]);

    // Every launch calls this. If it cleared on a match, the library would
    // re-embed itself from scratch on every single start.
    expect(repo.setEmbeddingSpace('openai|https://api.openai.com/v1|small'),
        isFalse);
    expect(repo.getEmbedding('n1'), isNotNull);
  });

  test('a changed space throws the old vectors away', () {
    repo.insert(note('n1'));
    repo.insert(note('n2'));
    repo.setEmbeddingSpace('openai|https://api.openai.com/v1|small');
    repo.setEmbedding('n1', [0.1, 0.2, 0.3]);
    repo.setEmbedding('n2', [0.4, 0.5, 0.6]);

    expect(repo.setEmbeddingSpace('gemini|https://g|004'), isTrue);

    expect(repo.getEmbedding('n1'), isNull);
    expect(repo.getEmbedding('n2'), isNull);
    expect(repo.listEmbeddings(), isEmpty);
    expect(repo.embeddingSpace, 'gemini|https://g|004');
  });

  test('the notes themselves are untouched', () {
    // An embedding is derived and re-derivable; a note is neither. Clearing
    // one must never touch the other, and the foreign key with its cascade
    // runs the other way.
    repo.insert(note('n1'));
    repo.setEmbeddingSpace('a|b|c');
    repo.setEmbedding('n1', [0.1, 0.2]);

    repo.setEmbeddingSpace('x|y|z');

    expect(repo.getById('n1')?.content, 'note n1');
  });

  test('a vector from another space is refused, not scored', () async {
    // The backstop behind the clearing above, and the reason the clearing is
    // the real fix rather than this: cosine used to truncate to the shorter
    // of the two and score what was left, which turns "these are from
    // different models" into a confident number.
    // Named, now that the constructor's default is `allOff`. Without it
    // `relatedNotes` refuses before it reaches a vector at all, and the
    // control below — the half of this test that makes the empty result
    // underneath mean "refused" rather than "never works" — fails first.
    final service = EnrichmentService(
      repo: repo,
      adapter: const _NoAdapter(),
      capabilities: AiCapabilities.allOn,
    );

    // First the control, without which this test proves nothing: same space,
    // identical vectors, and the machinery does find the match. An empty
    // result below has to mean "refused", not "related notes never works
    // here".
    repo.insert(note('n1'));
    repo.insert(note('same'));
    repo.setEmbedding('n1', [1, 0, 0]);
    repo.setEmbedding('same', [1, 0, 0]);

    expect(
      (await service.relatedNotes('n1')).map((hit) => hit.noteId),
      ['same'],
    );

    // Now the mismatch. Same leading values, four dimensions: under
    // truncation this scored a perfect 1.0 and came back as the closest
    // possible match.
    repo.insert(note('other'));
    repo.setEmbedding('other', [1, 0, 0, 0]);

    expect(
      (await service.relatedNotes('n1')).map((hit) => hit.noteId),
      ['same'],
      reason: 'different dimensions are not a similarity of 1.0',
    );
  });

  test('cleared notes come back through the backfill', () {
    // What makes discarding them acceptable: the queue that re-embeds picks
    // up exactly the notes with no vector, so a cleared library refills
    // itself without anything else having to notice.
    repo.insert(note('n1'));
    repo.setEmbeddingSpace('a|b|c');
    repo.setEmbedding('n1', [0.1, 0.2]);
    expect(repo.listNeedingEmbedding(), isEmpty);

    repo.setEmbeddingSpace('x|y|z');

    expect(repo.listNeedingEmbedding().map((n) => n.id), ['n1']);
  });
}

/// Never asked anything: these tests are about the vectors already stored.
class _NoAdapter implements AIAdapter {
  const _NoAdapter();

  @override
  Future<Vector>? embed(String text) => null;

  @override
  Future<Transcript>? transcribe(AudioRef audio) => null;

  @override
  Future<OCRText>? ocr(ImageRef image) => null;

  @override
  Future<Summary>? summarize(Note note) => null;

  @override
  Future<List<TagSuggestion>>? suggestTags(Note note) => null;
}
