@Tags(['budget'])
library;

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/screens/timeline/timeline_model.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_data/nex_data.dart';
import 'package:nex_ui/nex_ui.dart';

import '../support/nex_harness.dart';

/// W6.3: the timeline at 5,000 notes — opening it, scrolling it, and a capture
/// reaching it — held to a budget in CI, next to the search budget in
/// `packages/data`.
///
/// Two kinds of limit, and they are not equally trusted:
///
/// - **Counts** are exact and would fail the same way on any machine: the first
///   read is one window, not the library; only what is on screen is built; and
///   scrolling rebuilds nothing that is already built. These are what catch a
///   regression — a `setState` on scroll, a list that stopped being lazy.
/// - **Times** are CPU time in a debug-mode test VM on a CI runner, with the
///   database in the same thread. They are roughly two and a half times what
///   they measured when written, so they catch an order-of-magnitude slip and
///   not ordinary noise. What a phone actually takes is what W3.4's local
///   measurements show, on the phone.
///
/// Tagged `budget`, so the ordinary suite skips it; its own CI job runs
///
///     flutter test --tags budget --run-skipped test/performance/
void main() {
  const notes = 5000;
  late NexTestHarness harness;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_timeline_budget_');
    final rnd = Random(20261001);
    final db = NexDatabase.open(harness.dbPath);
    final start = DateTime.utc(2024);
    db.db.execute('BEGIN IMMEDIATE');
    for (var t = 0; t < 12; t++) {
      db.db.execute(
        'INSERT INTO tags (id, name, created_at) VALUES (?, ?, ?)',
        ['tag-$t', 'tag $t', start.toIso8601String()],
      );
    }
    // One note every hour and a half or so, a seventh of them checklists and a
    // third tagged: enough date groups, card shapes and tag rows to be a
    // library rather than 5,000 copies of one card.
    for (var i = 0; i < notes; i++) {
      final at = start.add(Duration(minutes: i * 97)).toIso8601String();
      final checklist = i % 7 == 0;
      final content = checklist
          ? '- [x] bread\n- [ ] milk $i\n- [ ] eggs'
          : List.generate(6 + rnd.nextInt(40), (w) => 'word$w').join(' ');
      db.db.execute(
        'INSERT INTO notes (id, type, content, created_at, updated_at, '
        "device_id, rev, sync_state) VALUES (?, ?, ?, ?, ?, 'budget', 1, "
        "'synced')",
        ['note-$i', checklist ? 'checklist' : 'text', content, at, at],
      );
      if (i % 3 == 0) {
        db.db.execute('INSERT INTO note_tags (note_id, tag_id) VALUES (?, ?)', [
          'note-$i',
          'tag-${i % 12}',
        ]);
      }
    }
    db.db.execute('COMMIT');
    db.close();
    await harness.services.refreshTimeline();
  });

  tearDown(() => harness.dispose());

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
  }

  /// Pumps the app until the first card is on screen, and says how long it
  /// took in CPU time.
  Future<int> open(WidgetTester tester) async {
    final watch = Stopwatch()..start();
    await tester.pumpWidget(harness.app());
    for (var i = 0; i < 200 && find.byType(NoteCard).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    watch.stop();
    expect(find.byType(NoteCard), findsWidgets);
    return watch.elapsedMilliseconds;
  }

  TimelineModel model(WidgetTester tester) =>
      tester.state<TimelineScreenState>(find.byType(TimelineScreen)).model;

  int percentile(List<int> sorted, double p) =>
      sorted[min(sorted.length - 1, (sorted.length * p).floor())];

  testWidgets('the timeline opens on 5,000 notes with one window', (
    tester,
  ) async {
    phone(tester);
    // The first open in a test VM compiles the app; the second is the one
    // that says anything about the app.
    await open(tester);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final ms = await open(tester);
    debugPrint('W6.3 open: $ms ms');

    expect(model(tester).notes, hasLength(200), reason: 'one window read');
    expect(
      find.byType(NoteCard).evaluate().length,
      lessThanOrEqualTo(12),
      reason: 'only what is on screen is built',
    );
    expect(ms, lessThan(1000), reason: 'first card on screen, in CPU time');
    await tester.pumpAndSettle();
  });

  testWidgets('scrolling builds only what arrives and rebuilds nothing', (
    tester,
  ) async {
    phone(tester);
    // Every element that builds is remembered from the first frame on, so
    // one that builds again later is a rebuild. (The hook's own `builtOnce`
    // flag is only kept while rebuild printing is switched on.)
    final built = <Element>{};
    var counting = false;
    var rebuilds = 0;
    var frameRebuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (!built.add(element) && counting) frameRebuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    await open(tester);
    await tester.pumpAndSettle();
    final timeline = model(tester);
    counting = true;

    // 600 frames of a steady drag, about 400 cards: past the first window,
    // so the frames that load the next one are measured too — separately,
    // because in a test the database read happens on this thread, and
    // because those are the frames where the cards on screen rightly
    // rebuild with the new list.
    const frames = 600;
    final scroll = <int>[];
    final loads = <int>[];
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    final watch = Stopwatch();
    for (var i = 0; i < frames; i++) {
      final before = timeline.notes.length;
      frameRebuilds = 0;
      watch
        ..reset()
        ..start();
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump(const Duration(milliseconds: 16));
      watch.stop();
      if (timeline.notes.length == before) {
        scroll.add(watch.elapsedMicroseconds);
        // The first scroll folds the recap card away on purpose, which
        // rebuilds the screen once; a steady drag after that should
        // rebuild nothing at all.
        if (i >= 10) rebuilds += frameRebuilds;
      } else {
        // New notes arrived: the visible cards rebuild with them, which is
        // what a new window should do.
        loads.add(watch.elapsedMicroseconds);
      }
    }
    await gesture.up();
    debugOnRebuildDirtyWidget = null;
    await tester.pumpAndSettle();

    scroll.sort();
    final p90 = percentile(scroll, .9) ~/ 1000;
    final p99 = percentile(scroll, .99) ~/ 1000;
    final load = loads.isEmpty ? 0 : loads.reduce(max) ~/ 1000;
    debugPrint(
      'W6.3 scroll: p90 $p90 ms, p99 $p99 ms, ${loads.length} window loads, '
      'slowest $load ms, $rebuilds rebuilds',
    );

    expect(loads, isNotEmpty, reason: 'the drag went past the first window');
    expect(
      rebuilds,
      0,
      reason: 'a widget already built rebuilt while scrolling',
    );
    expect(
      find.byType(NoteCard).evaluate().length,
      lessThanOrEqualTo(20),
      reason: 'cards scrolled past are let go',
    );
    expect(p90, lessThan(50));
    expect(p99, lessThan(120));
    expect(load, lessThan(500), reason: 'a frame that loads the next window');
  });

  testWidgets('a capture reaches the top of a 5,000-note timeline', (
    tester,
  ) async {
    phone(tester);
    await open(tester);
    await tester.pumpAndSettle();
    final card = find.byWidgetPredicate(
      (w) => w is NoteCard && w.note.content == 'the budget note',
    );

    final watch = Stopwatch()..start();
    // What the capture sheet does: store, then refresh the timeline.
    await harness.services.captureText('the budget note');
    await harness.services.refreshTimeline();
    for (var i = 0; i < 200 && card.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    watch.stop();
    debugPrint('W6.3 capture: ${watch.elapsedMilliseconds} ms');

    expect(card, findsOneWidget);
    expect(watch.elapsedMilliseconds, lessThan(600));
  });
}
