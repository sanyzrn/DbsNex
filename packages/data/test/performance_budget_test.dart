import 'dart:io';

import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The two engineering budgets from `02-product-specification.md` that can
/// honestly be gated on a shared CI runner.
///
/// The document named four and said all four were "enforced in CI". None of
/// them was: no job in the pipeline timed anything. Two of the four are now
/// enforced here, and the other two — cold start, and the capture sheet
/// reaching a typable state — have been rewritten as usability-validated
/// targets, because measuring them needs a real device and a shared runner
/// would be timing the runner rather than the app. A gate that goes red at
/// random teaches people to re-run it, which is worse than no gate.
///
/// **Why these two can be gated honestly.** Both are pure Dart against a
/// local SQLite file: no Flutter, no emulator, no network. And both have
/// roughly two orders of magnitude of headroom — a synchronous SQLite insert
/// is well under a millisecond against a 300 ms budget — so the thresholds
/// catch an algorithmic regression (a lost index, a full-table scan, a write
/// moved off the fast path) without being sensitive to how loaded the
/// machine is.
///
/// The runs take the **best** of several rather than an average, deliberately.
/// The question is what the code costs, and a scheduling hiccup on a shared
/// runner is not that. A regression makes every run slow, so the best one
/// moves too.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;
  late CaptureService capture;
  late SearchService search;

  setUp(() {
    // On disk, not in memory: durability is the thing being measured, and an
    // in-memory database would report the cost of not doing it.
    tmp = Directory.systemTemp.createTempSync('nex_perf_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db);
    capture = CaptureService(repo, deviceId: 'perf-test');
    search = SearchService(repo);
  });

  tearDown(() {
    db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// The fastest of [runs] passes of [body], in microseconds.
  int fastest(int runs, void Function(int pass) body) {
    var best = -1;
    for (var pass = 0; pass < runs; pass++) {
      final watch = Stopwatch()..start();
      body(pass);
      watch.stop();
      if (best < 0 || watch.elapsedMicroseconds < best) {
        best = watch.elapsedMicroseconds;
      }
    }
    return best;
  }

  test('a capture is durable well inside 300ms', () {
    // 02-product-specification, NFR: "local write durable within 300 ms of
    // content change". The capture path is the one thing in this app that is
    // never allowed to get slower.
    final best = fastest(20, (pass) {
      final note = capture.submitTextCapture('a captured thought $pass');
      expect(note, isNotNull);
    });

    expect(
      best,
      lessThan(300 * 1000),
      reason: 'capture took ${best / 1000}ms against a 300ms budget',
    );
  });

  test('a capture stays durable inside the budget on a full library', () {
    // The budget says "regardless of corpus size at personal scale". A write
    // that is fast on an empty database and slow on a real one is the
    // regression this is for — an index dropped, or a trigger that rewrites
    // more than it needs to.
    for (var i = 0; i < 2000; i++) {
      capture.submitTextCapture('seeded note $i about groceries and plumbers');
    }

    final best = fastest(20, (pass) {
      expect(capture.submitTextCapture('one more thought $pass'), isNotNull);
    });

    expect(
      best,
      lessThan(300 * 1000),
      reason: 'capture into a 2000-note library took ${best / 1000}ms',
    );
  });

  test('search answers well inside 200ms over a real corpus', () {
    // 02-product-specification, NFR: "local query latency < 200 ms,
    // index-backed (FTS5), regardless of corpus size at personal scale".
    // Two thousand notes is a heavy personal library and a light test.
    for (var i = 0; i < 2000; i++) {
      capture.submitTextCapture(
        'note $i about the boiler, the plumber and the shopping list',
      );
    }
    capture.submitTextCapture('the needle: a stroopwafel from Amsterdam');

    // Warm, so the first query's one-off costs are not charged to the budget.
    expect(
      search.search(const SearchFilters(query: 'stroopwafel')),
      isNotEmpty,
    );

    late List<Note> hits;
    final best = fastest(10, (_) {
      hits = search.search(const SearchFilters(query: 'stroopwafel'));
    });

    // The result is asserted as well as the time. A search that got fast by
    // returning nothing is not a search that got fast.
    expect(hits, hasLength(1));
    expect(hits.single.content, contains('stroopwafel'));
    expect(
      best,
      lessThan(200 * 1000),
      reason: 'search over 2001 notes took ${best / 1000}ms against 200ms',
    );
  });
}
