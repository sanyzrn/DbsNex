import 'dart:io';

import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The on-device adapter does not claim to understand anything.
///
/// It used to. `embed()` returned 32 doubles derived from the SHA-256 of the
/// text — deterministic, correctly normalised, and carrying no similarity
/// structure at all. Those numbers were stored, and then surfaced in search
/// under their own heading, "semantic matches", whenever a keyword search came
/// back empty. It was reachable with no provider configured, because that is
/// exactly when the worker falls back to this adapter.
///
/// So the failure was not "semantic search is poor". It was that somebody who
/// searched, found nothing, and was shown three results under a label
/// asserting the app had understood their notes, had been told something
/// untrue by a hash function.
///
/// These tests hold the honest version: with nothing but local heuristics,
/// there are no vectors, and therefore no matches by meaning to offer.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;
  late EnrichmentService enrichment;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_on_device_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db, localDeviceId: 'test');
    enrichment = EnrichmentService(
      repo: repo,
      adapter: const OnDeviceAIAdapter(),
      // Everything switched on, which is the point: the refusal below is the
      // adapter's, not a capability gate's.
      capabilities: AiCapabilities.allOn,
    );
  });

  tearDown(() {
    db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Note write(String id, String content) {
    final now = DateTime.now().toUtc();
    return repo.insert(
      Note(
        id: id,
        type: NoteType.text,
        content: content,
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  test('it reports embeddings unavailable rather than inventing one', () {
    expect(const OnDeviceAIAdapter().embed('soup recipe'), isNull);
  });

  test('a backfill writes no vectors and does not spin', () async {
    write('a', 'my grandmother soup recipe for winter');
    write('b', 'quarterly budget review');
    // In the backlog, so the pass really does reach the adapter. As a set:
    // the query orders by `created_at DESC` and both of these are written in
    // the same millisecond, so which comes first is not something to assert.
    expect(repo.listNeedingEmbedding(limit: 10).map((n) => n.id).toSet(), {
      'a',
      'b',
    });

    expect(await enrichment.backfill(), 0);
    expect(repo.getEmbedding('a'), isNull);
    expect(repo.getEmbedding('b'), isNull);
    // Still in the backlog — nothing was written, so nothing was claimed.
    // The backfill's own "stop when nothing was written" check is what keeps
    // this one query per pass instead of a loop over the whole library.
    expect(repo.listNeedingEmbedding(limit: 10), hasLength(2));
  });

  test('nothing is offered as a match by meaning', () async {
    write('a', 'my grandmother soup recipe for winter');
    write('b', 'quarterly budget review');
    await enrichment.backfill();

    // The query that used to produce the lie: a word in neither note, so the
    // keyword index finds nothing and the semantic heading is what the user
    // is shown instead.
    expect(await enrichment.semanticSearch('dinner'), isEmpty);
    expect(await enrichment.relatedNotes('a'), isEmpty);
  });

  test('the local heuristics it can actually do still work', () async {
    // The adapter is not being disabled — it is being made honest about the
    // one thing it cannot do. Tag hints come from the note's own words and
    // are unaffected.
    final note = write('a', 'learning flutter widgets today');
    final suggestions = await enrichment.suggestTags(note.id);
    expect(suggestions, isNotEmpty);
  });
}
