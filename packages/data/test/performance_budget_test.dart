import 'dart:io';

import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The engineering budgets from `02-product-specification.md`, at the sizes
/// the app is actually used at.
///
/// **These are not the first.** `apps/client/test/app_smoke_test.dart` has
/// carried a search budget (1 000 notes, 200 ms) and a durable-write budget
/// (300 ms) for some time. A review of this repository reported the budgets
/// as entirely unenforced, having grepped the workflow files for a job named
/// after them — and the engineer verifying that claim repeated the same grep
/// and agreed. There is no such job; the tests are ordinary tests inside the
/// suites CI already runs. Both readings were wrong in the same way, which is
/// why the doc now says where to look.
///
/// What this file adds is size and stability:
///
/// - the durable-write budget on a **full library**. The existing one writes
///   into an empty database, so an index dropped or a trigger rewriting more
///   than it needs would not show there — and that is the shape a capture
///   regression actually takes.
/// - **best-of-N instead of a single run.** One stopwatch reading on a shared
///   runner is one sample of a machine somebody else is also using. A real
///   regression makes every run slow, so the best one moves too; a
///   scheduling hiccup does not.
/// - pure Dart, so these run in the Flutter-free job as well.
///
/// The two budgets that are *not* here — cold start, and the capture sheet
/// reaching a typable state — are device-bound. Timing them on a shared
/// runner measures the runner, and a gate that reddens at random teaches
/// people to re-run it, which is worse than no gate. They are validated by
/// usability testing, and the spec says so.
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
