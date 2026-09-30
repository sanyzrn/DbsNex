@Tags(['budget'])
library;

import 'dart:io';
import 'dart:math';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// W2.3: retrieval at the size the principle is about — 50,000 notes.
///
/// "Finding information feels instantaneous" was protected only by nobody
/// having enough notes yet; the ordinary budget in
/// `performance_budget_test.dart` searches 2,000. This seeds 50,000 notes,
/// each with a 1,536-dimension embedding (the size of the most common cloud
/// model), and holds keyword, meaning and fused search to a p95.
///
/// The limits are for a CI runner, which is faster than a mid-range phone:
/// the phone budget in the roadmap (p95 fused < 300 ms) is roughly three
/// times these. The query's embedding is computed beforehand — a provider's
/// network time is not the library's to spend.
///
/// Tagged `budget` and run by its own CI job: seeding takes a minute, which
/// the ordinary suite should not pay on every change.
/// `dart test --tags budget` runs it locally.
void main() {
  const notes = 50000;
  const dims = 1536;
  const runs = 40;

  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;
  final rnd = Random(20260930);

  // A vocabulary with a long tail, so some query words are in thousands of
  // notes and some in a handful — the two shapes that stress FTS differently.
  final vocabulary = [for (var i = 0; i < 4000; i++) 'w${i.toRadixString(36)}'];
  String word() =>
      vocabulary[(pow(rnd.nextDouble(), 3) * vocabulary.length).floor()];
  List<double> vector() => List.generate(dims, (_) => rnd.nextDouble() * 2 - 1);

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('nex_retrieval_budget_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db, localDeviceId: 'budget');
    final start = DateTime.utc(2024);
    for (var batch = 0; batch < notes; batch += 1000) {
      db.db.beginImmediate();
      for (var i = batch; i < batch + 1000; i++) {
        final id = 'note-$i';
        final text = List.generate(
          12 + rnd.nextInt(30),
          (_) => word(),
        ).join(' ');
        final at = start.add(Duration(minutes: i * 20)).toIso8601String();
        db.db.execute(
          "INSERT INTO notes (id, type, content, created_at, updated_at, "
          "device_id, rev, sync_state) VALUES (?, 'text', ?, ?, ?, 'budget', "
          "1, 'pending')",
          [id, text, at, at],
        );
        db.db.execute(
          'INSERT INTO notes_fts (note_id, content) VALUES (?, ?)',
          [id, text],
        );
        repo.setEmbedding(id, vector());
      }
      db.db.execute('COMMIT');
    }
  });

  tearDownAll(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  /// The 95th percentile of [runs] timings of [body], in milliseconds.
  double p95(void Function(int run) body) {
    final times = <int>[];
    for (var run = 0; run < runs; run++) {
      final watch = Stopwatch()..start();
      body(run);
      times.add(watch.elapsedMicroseconds);
    }
    times.sort();
    return times[(times.length * 0.95).ceil() - 1] / 1000;
  }

  // Common, middling and rare words, and a two-word query.
  final queries = ['w0', 'w1', 'w5', 'w2s', 'wa0', 'w1k', 'w2 w9', 'w3 w7'];

  test('keyword search: p95 under 150 ms at 50,000 notes', () {
    repo.search(const SearchFilters(query: 'w1'));
    var found = 0;
    final ms = p95((run) {
      found += repo
          .search(SearchFilters(query: queries[run % queries.length]))
          .length;
    });
    expect(found, greaterThan(0));
    printOnFailure('keyword p95 $ms ms');
    print('keyword p95: $ms ms');
    expect(ms, lessThan(150));
  });

  test('meaning search: p95 under 150 ms, first search under 3 s', () {
    final build = Stopwatch()..start();
    expect(
      repo.nearestEmbeddings(vector(), limit: 20, minScore: -1),
      hasLength(20),
    );
    final first = build.elapsedMilliseconds;
    final probes = [for (var i = 0; i < runs; i++) vector()];
    final ms = p95((run) {
      repo.nearestEmbeddings(probes[run], limit: 20, minScore: -1);
    });
    print('meaning p95: $ms ms (first, building the index: $first ms)');
    expect(first, lessThan(3000));
    expect(ms, lessThan(150));
  });

  test('fused search: p95 under 250 ms', () {
    final probes = [for (var i = 0; i < runs; i++) vector()];
    final ms = p95((run) {
      final semantic = [
        for (final hit in repo.nearestEmbeddings(
          probes[run],
          limit: 100,
          minScore: -1,
        ))
          hit.noteId,
      ];
      repo.rankedSearch(
        SearchFilters(query: queries[run % queries.length]),
        semantic: semantic,
      );
    });
    print('fused p95: $ms ms');
    expect(ms, lessThan(250));
  });
}
