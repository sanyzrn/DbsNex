import 'dart:typed_data';

import 'package:nex_ai/nex_ai.dart';
import 'package:nex_data/nex_data.dart';
import 'package:test/test.dart';

void main() {
  late NexDatabase db;
  late SqliteNoteRepository repo;
  late EnrichmentService enrichment;

  setUp(() {
    db = NexDatabase.openInMemory();
    repo = SqliteNoteRepository(db, localDeviceId: 'test');
    enrichment = EnrichmentService(
      repo: repo,
      adapter: const OnDeviceAIAdapter(),
      capabilities: const AiCapabilities(),
    );
  });

  tearDown(() => db.close());

  Note insertVoice() {
    final now = DateTime.now().toUtc();
    return repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.voice,
        mediaUri: '/tmp/voice.m4a',
        mediaHash: 'abc123hash',
        durationMs: 1000,
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  Note insertPhoto() {
    final now = DateTime.now().toUtc();
    return repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.photo,
        mediaUri: '/tmp/photo.jpg',
        mediaHash: 'def456hash',
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  test('transcription stores transcript_text and enables FTS', () async {
    final note = insertVoice();
    await enrichment.enrichNote(note.id);
    final updated = repo.getById(note.id)!;
    expect(updated.transcriptText, isNotNull);
    expect(updated.transcriptText, contains('voice transcript'));
    final hits = repo.search(SearchFilters(query: 'spoken'));
    expect(hits.map((n) => n.id), contains(note.id));
  });

  test('ocr stores ocr_text and enables FTS', () async {
    final note = insertPhoto();
    await enrichment.enrichNote(note.id);
    final updated = repo.getById(note.id)!;
    expect(updated.ocrText, isNotNull);
    final hits = repo.search(SearchFilters(query: 'readable'));
    expect(hits.map((n) => n.id), contains(note.id));
  });

  test('disabled transcription leaves note unchanged', () async {
    final note = insertVoice();
    enrichment.updateCapabilities(
      const AiCapabilities(transcription: false),
    );
    await enrichment.enrichNote(note.id);
    expect(repo.getById(note.id)!.transcriptText, isNull);
  });

  test('tag suggestions never auto-apply', () async {
    final now = DateTime.now().toUtc();
    final note = repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.text,
        content: 'learning flutter widgets today',
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
    final suggestions = await enrichment.suggestTags(note.id);
    expect(suggestions, isNotEmpty);
    expect(repo.getById(note.id)!.tags, isEmpty);
  });

  test('semantic search returns scored hits distinct from keyword', () async {
    final now = DateTime.now().toUtc();
    final a = repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.text,
        content: 'grocery shopping list milk eggs',
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
    final b = repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.text,
        content: 'buy food at the market',
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
    await enrichment.enrichNote(a.id);
    await enrichment.enrichNote(b.id);
    final hits = await enrichment.semanticSearch('purchase groceries');
    expect(hits, isNotEmpty);
    expect(hits.first.score, greaterThan(0));
  });

  test('related notes use embeddings', () async {
    final now = DateTime.now().toUtc();
    final a = repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.text,
        content: 'rust programming ownership borrow checker',
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
    final b = repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.text,
        content: 'rust lang memory safety ownership',
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
    await enrichment.enrichNote(a.id);
    await enrichment.enrichNote(b.id);
    final related = await enrichment.relatedNotes(a.id);
    expect(related.map((h) => h.noteId), contains(b.id));
  });

  test('cloud gate blocks when opt-in is false', () async {
    final gated = CloudGatedAIAdapter(
      inner: const OnDeviceAIAdapter(),
      cloudOptIn: false,
    );
    expect(gated.transcribe(const AudioRef(mediaUri: 'x')), isNull);
    expect(gated.ocr(const ImageRef(mediaUri: 'x')), isNull);
  });

  test('NullAIAdapter exposes no capabilities', () {
    const adapter = NullAIAdapter();
    expect(
      adapter.transcribe(AudioRef(mediaUri: 'a', bytes: Uint8List(0))),
      isNull,
    );
    expect(adapter.embed('hi'), isNull);
  });

  test('summarization is on-demand and stored as summary_text', () async {
    final now = DateTime.now().toUtc();
    final note = repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.text,
        content: 'A' * 200,
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
    final summary = await enrichment.summarizeOnDemand(note.id);
    expect(summary, isNotNull);
    expect(repo.getById(note.id)!.summaryText, isNotNull);
  });
}
