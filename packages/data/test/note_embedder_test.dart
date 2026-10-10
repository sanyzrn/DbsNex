import 'dart:async';
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

  test('each model\'s own floor decides what counts as a match', () async {
    // EmbeddingGemma scores unrelated text around 0.5, so the cloud floor of
    // 0.3 returned the whole library for any search (AI-05, AI-12).
    final strict = _FixedScoreEmbedder(floor: 0.5);
    final service = EnrichmentService(repo: repo, capabilities: searching)
      ..updateEmbedder(strict);
    repo.insert(note('n1', 'related'));
    repo.insert(note('n2', 'unrelated'));
    await service.backfillEmbeddings();

    final hits = await service.semanticSearch('query');
    expect(hits.map((h) => h.noteId), ['n1']);

    service.updateEmbedder(_FixedScoreEmbedder(floor: 0.3));
    final loose = await service.semanticSearch('query');
    expect(loose.map((h) => h.noteId).toSet(), {'n1', 'n2'});
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

  test('a very long note is embedded from its opening (AI-06)', () async {
    // A provider refuses an input past its limit, and one refused note
    // stopped the whole backfill behind it.
    final embedder = _RecordingEmbedder();
    final service = EnrichmentService(
      repo: repo,
      adapter: _CountingAdapter(),
      capabilities: searching,
    )..updateEmbedder(embedder);
    repo.insert(note('n1', 'word ' * 3000));
    await service.enrichNote('n1');
    expect(
      embedder.documents.single.length,
      EnrichmentService.embedCharacterLimit,
    );
    expect(repo.listEmbeddings(), hasLength(1));
  });

  test('a vector that arrives after an edit is not kept for the new text '
      '(AI-09)', () async {
    final embedder = _HeldEmbedder();
    final service = EnrichmentService(
      repo: repo,
      adapter: _CountingAdapter(),
      capabilities: searching,
    )..updateEmbedder(embedder);

    repo.insert(note('n1', 'dentist appointment'));
    final asked = service.enrichNote('n1');
    await embedder.asked.future;
    repo.updateContent('n1', 'buy bread');
    embedder.answer.complete([1.0, 0.0]);
    await asked;

    expect(repo.listEmbeddings(), isEmpty);
    expect(repo.listNeedingEmbedding().single.id, 'n1');
  });

  test('nor one asked of a model that has since been replaced', () async {
    final held = _HeldEmbedder();
    final service = EnrichmentService(
      repo: repo,
      adapter: _CountingAdapter(),
      capabilities: searching,
    )..updateEmbedder(held);

    repo.insert(note('n1', 'dentist appointment'));
    final asked = service.enrichNote('n1');
    await held.asked.future;
    service.updateEmbedder(_RecordingEmbedder());
    held.answer.complete([1.0, 0.0]);
    await asked;

    expect(repo.listEmbeddings(), isEmpty);
  });
}

/// A tiny bag-of-letters "model": deterministic, and close for texts that
/// share words, which is all a search test needs.
class _RecordingEmbedder implements NoteEmbedder {
  @override
  double get minSimilarity => 0.3;

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
  double get minSimilarity => 0.3;

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

/// Answers only when told to: the await an edit can land in.
class _HeldEmbedder implements NoteEmbedder {
  @override
  double get minSimilarity => 0.3;

  final asked = Completer<void>();
  final answer = Completer<List<double>>();

  @override
  String get space => 'test|held';

  @override
  Future<List<double>> embedDocument(String text) {
    if (!asked.isCompleted) asked.complete();
    return answer.future;
  }

  @override
  Future<List<double>> embedQuery(String text) => answer.future;
}

/// Vectors chosen so the query scores 0.8 against "related" and 0.45
/// against "unrelated" — the second the kind of score EmbeddingGemma gives
/// text with nothing in common.
class _FixedScoreEmbedder implements NoteEmbedder {
  _FixedScoreEmbedder({required this.floor});

  final double floor;

  @override
  double get minSimilarity => floor;

  @override
  String get space => 'test|fixed';

  @override
  Future<List<double>> embedDocument(String text) async => switch (text) {
    'related' => [0.8, 0.6],
    _ => [0.45, 0.893],
  };

  @override
  Future<List<double>> embedQuery(String text) async => [1, 0];
}
