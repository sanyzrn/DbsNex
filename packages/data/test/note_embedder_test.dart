import 'dart:io';

import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The on-device search model is a [NoteEmbedder]: it is asked for a note's
/// vector and for a search's vector separately, because EmbeddingGemma is
/// trained with a different prompt for each. What is tested here is that,
/// while one is set, every vector comes from it — and none from the
/// provider, which may be a cloud service the person no longer wants their
/// notes sent to for search.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_note_embedder_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db);
  });

  tearDown(() {
    db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Note note(String id, String content) {
    final now = DateTime.now().toUtc();
    return Note(
      id: id,
      type: NoteType.text,
      content: content,
      createdAt: now,
      updatedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    );
  }

  const searching = AiCapabilities(semanticSearch: true, relatedNotes: true);

  test('notes are embedded as documents, searches as queries', () async {
    final embedder = _RecordingEmbedder();
    final provider = _CountingAdapter();
    final service = EnrichmentService(
      repo: repo,
      adapter: provider,
      capabilities: searching,
    )..updateEmbedder(embedder);

    repo.insert(note('n1', 'dentist on Monday'));
    await service.enrichNote('n1');
    await service.semanticSearch('tooth doctor');

    expect(embedder.documents, ['dentist on Monday']);
    expect(embedder.queries, ['tooth doctor']);
    expect(repo.getEmbedding('n1'), isNotEmpty);
    // Not once: with the search model set, nothing about the notes goes to
    // the provider for search.
    expect(provider.embeds, 0);
  });

  test('a search finds the note it means', () async {
    final service = EnrichmentService(repo: repo, capabilities: searching)
      ..updateEmbedder(_RecordingEmbedder());
    repo.insert(note('n1', 'dentist on Monday'));
    repo.insert(note('n2', 'buy bread'));
    await service.backfillEmbeddings();

    final hits = await service.semanticSearch('dentist');
    expect(hits.first.noteId, 'n1');
  });

  test('clearing it hands embedding back to the provider', () async {
    final provider = _CountingAdapter();
    final service = EnrichmentService(
      repo: repo,
      adapter: provider,
      capabilities: searching,
    )..updateEmbedder(_RecordingEmbedder());
    service.updateEmbedder(null);

    repo.insert(note('n1', 'dentist on Monday'));
    await service.enrichNote('n1');
    expect(provider.embeds, 1);
  });

  test(
    'backfill embeds every note that has no vector, and only that',
    () async {
      final embedder = _RecordingEmbedder();
      final service = EnrichmentService(repo: repo, capabilities: searching)
        ..updateEmbedder(embedder);
      for (var i = 0; i < 3; i++) {
        repo.insert(note('n$i', 'note $i'));
      }

      expect(await service.backfillEmbeddings(limit: 10), 3);
      expect(await service.backfillEmbeddings(limit: 10), 0);
      expect(embedder.documents, hasLength(3));
    },
  );

  test('a model that fails leaves the note to be tried again', () async {
    final service = EnrichmentService(repo: repo, capabilities: searching)
      ..updateEmbedder(_FailingEmbedder());
    repo.insert(note('n1', 'dentist on Monday'));

    expect(await service.backfillEmbeddings(), 0);
    expect(repo.getEmbedding('n1'), isNull);
  });

  test('nothing is embedded while search by meaning is off', () async {
    final embedder = _RecordingEmbedder();
    final service = EnrichmentService(repo: repo)..updateEmbedder(embedder);
    repo.insert(note('n1', 'dentist on Monday'));

    await service.enrichNote('n1');
    expect(await service.backfillEmbeddings(), 0);
    expect(embedder.documents, isEmpty);
  });
}

/// A tiny bag-of-letters "model": deterministic, and close for texts that
/// share words, which is all a search test needs.
class _RecordingEmbedder implements NoteEmbedder {
  final documents = <String>[];
  final queries = <String>[];

  @override
  String get space => 'test|letters';

  @override
  Future<List<double>> embedDocument(String text) async {
    documents.add(text);
    return _letters(text);
  }

  @override
  Future<List<double>> embedQuery(String text) async {
    queries.add(text);
    return _letters(text);
  }

  static List<double> _letters(String text) {
    final counts = List<double>.filled(26, 0);
    for (final unit in text.toLowerCase().codeUnits) {
      if (unit >= 97 && unit <= 122) counts[unit - 97] += 1;
    }
    return counts;
  }
}

class _FailingEmbedder implements NoteEmbedder {
  @override
  String get space => 'test|failing';

  @override
  Future<List<double>> embedDocument(String text) =>
      Future.error(StateError('model would not load'));

  @override
  Future<List<double>> embedQuery(String text) =>
      Future.error(StateError('model would not load'));
}

class _CountingAdapter implements AIAdapter {
  int embeds = 0;

  @override
  Future<Vector>? embed(String text) async {
    embeds++;
    return const Vector([1, 0, 0]);
  }

  @override
  Future<Transcript>? transcribe(AudioRef audio) => null;

  @override
  Future<OCRText>? ocr(ImageRef image) => null;

  @override
  Future<List<TagSuggestion>>? suggestTags(Note note) => null;

  @override
  Future<Summary>? summarize(Note note) => null;
}
