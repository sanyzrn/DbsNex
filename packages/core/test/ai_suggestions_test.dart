import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

void main() {
  Note textNote(String content) {
    final now = DateTime.now().toUtc();
    return Note(
      id: newUuidV7(),
      type: NoteType.text,
      content: content,
      createdAt: now,
      updatedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    );
  }

  Note photoWithOcr(String ocr) {
    final now = DateTime.now().toUtc();
    return Note(
      id: newUuidV7(),
      type: NoteType.photo,
      mediaUri: '/tmp/photo.jpg',
      mediaHash: '69cfddd4deadbeef',
      ocrText: ocr,
      createdAt: now,
      updatedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    );
  }

  group('OnDeviceAIAdapter.suggestTagNames', () {
    test('rejects hash-like, short, numeric, and stopword tokens', () {
      final suggestions = OnDeviceAIAdapter.suggestTagNames(
        photoWithOcr('photo text 69cfddd4 readable label'),
      );
      final names = suggestions.map((s) => s.name).toList();
      expect(names, isNot(contains('photo')));
      expect(names, isNot(contains('text')));
      expect(names, isNot(contains('69cfddd4')));
      expect(names, isNot(contains('readable')));
      expect(names, isNot(contains('label')));
      for (final name in names) {
        expect(name.length, greaterThanOrEqualTo(5));
        expect(RegExp(r'^[0-9a-f]{6,}$').hasMatch(name), isFalse);
        expect(RegExp(r'^\d+$').hasMatch(name), isFalse);
      }
    });

    test('extracts meaningful keywords from real content', () {
      final suggestions = OnDeviceAIAdapter.suggestTagNames(
        textNote('planning flutter widgets workshop tomorrow'),
      );
      final names = suggestions.map((s) => s.name).toSet();
      expect(names, contains('flutter'));
      expect(names, contains('widgets'));
      expect(names, contains('workshop'));
      expect(names, contains('planning'));
      expect(names, contains('tomorrow'));
    });
  });

  group('OnDeviceAIAdapter.summarize', () {
    test('short source yields empty summary (UI should hide)', () async {
      final future = const OnDeviceAIAdapter().summarize(
        textNote('short ocr line'),
      );
      expect(future, isNotNull);
      final summary = await future!;
      expect(summary.text, isEmpty);
    });

    test('long source yields visibly shorter reworded-ish summary', () async {
      final source = List.generate(
        8,
        (i) =>
            'Paragraph $i discusses capture latency budgets and offline search. ',
      ).join();
      expect(source.length, greaterThan(80));
      final future = const OnDeviceAIAdapter().summarize(
        textNote(source),
      );
      final text = (await future!).text;
      expect(text, isNotEmpty);
      expect(text, isNot(equals(source.trim())));
      expect(text.length, lessThan(source.trim().length));
    });
  });

  group('EnrichmentService tag suggestions never persist', () {
    late NexDatabase db;
    late NoteRepository repo;
    late EnrichmentService enrichment;

    setUp(() {
      db = NexDatabase.openInMemory();
      repo = NoteRepository(db, localDeviceId: 'test');
      enrichment = EnrichmentService(
        repo: repo,
        adapter: const OnDeviceAIAdapter(),
        capabilities: const AiCapabilities(),
      );
    });

    tearDown(() => db.close());

    test('suggestTags never writes tags table / search filters', () async {
      final now = DateTime.now().toUtc();
      final note = repo.insert(
        Note(
          id: newUuidV7(),
          type: NoteType.text,
          content: 'planning flutter widgets workshop tomorrow',
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
      expect(repo.listTags(), isEmpty);

      // Enrichment path also must not auto-apply.
      await enrichment.enrichNote(note.id);
      expect(repo.getById(note.id)!.tags, isEmpty);
      expect(repo.listTags(), isEmpty);
    });

    test('OCR stub suggestions exclude hash fragments and are not persisted',
        () async {
      final now = DateTime.now().toUtc();
      final note = repo.insert(
        Note(
          id: newUuidV7(),
          type: NoteType.photo,
          mediaUri: '/tmp/p.jpg',
          mediaHash: '69cfddd4deadbeefcafe',
          createdAt: now,
          updatedAt: now,
          deviceId: 'test',
          rev: 1,
          syncState: SyncState.pending,
        ),
      );
      await enrichment.enrichNote(note.id);
      final updated = repo.getById(note.id)!;
      expect(updated.ocrText, isNotNull);
      final suggestions = await enrichment.suggestTags(note.id);
      for (final s in suggestions) {
        expect(RegExp(r'^[0-9a-f]{6,}$').hasMatch(s.name), isFalse);
        expect(
          const {'photo', 'text', 'readable', 'label'}.contains(s.name),
          isFalse,
        );
      }
      expect(repo.listTags(), isEmpty);
      expect(updated.tags, isEmpty);
    });

    test('summarizeOnDemand refuses pass-through / short summaries', () async {
      final now = DateTime.now().toUtc();
      final short = repo.insert(
        Note(
          id: newUuidV7(),
          type: NoteType.text,
          content: 'too short',
          createdAt: now,
          updatedAt: now,
          deviceId: 'test',
          rev: 1,
          syncState: SyncState.pending,
        ),
      );
      expect(await enrichment.summarizeOnDemand(short.id), isNull);
      expect(repo.getById(short.id)!.summaryText, isNull);

      final longBody = List.generate(
        10,
        (i) => 'Sentence number $i about durable local capture. ',
      ).join();
      final long = repo.insert(
        Note(
          id: newUuidV7(),
          type: NoteType.text,
          content: longBody,
          createdAt: now,
          updatedAt: now,
          deviceId: 'test',
          rev: 1,
          syncState: SyncState.pending,
        ),
      );
      final summary = await enrichment.summarizeOnDemand(long.id);
      expect(summary, isNotNull);
      expect(summary!.text.length, lessThan(longBody.length));
      expect(repo.getById(long.id)!.summaryText, summary.text);
    });
  });
}
