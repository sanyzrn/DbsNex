@Tags(['budget'])
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/screens/timeline/timeline_model.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_data/nex_data.dart';
import 'package:nex_ui/nex_ui.dart';

import '../support/nex_harness.dart';

/// The content axis of the timeline budget: the same library W6.3 holds, but
/// the notes are not all six words long. Thirty of them are; the rest are the
/// mix a phone actually carries — notes past a hundred kilobytes, Markdown
/// documents, files, links.
///
/// W6.3 covers count: five thousand short notes, one window at a time. It
/// never meets the cost this file pins down, because a card's price is a
/// function of its note's *length*, not of how many notes there are — a
/// 128KB note used to spend its whole text being stripped of Markdown
/// markers on every build of its two-line card, on the UI thread, four
/// times per build. That is the regression this file exists to catch again:
/// with the scan capped and the answer memoized, none of these frames has a
/// reason to cost more than its short-note twin.
///
/// Same limits and the same trust as W6.3: counts are exact, times are
/// CPU time in a debug-mode test VM — roughly two and a half times a phone —
/// catching an order-of-magnitude slip rather than noise.
///
/// Tagged `budget`, so the ordinary suite skips it; its own CI job runs
///
///     flutter test --tags budget --run-skipped test/performance/
void main() {
  late NexTestHarness harness;
  // The mixed library: 30 short notes, then the heavy half of the phone —
  // five long notes (8KB..128KB), five Markdown documents (16KB..64KB),
  // five files with attachments, five links — and five more shorts at the
  // bottom so the heavy group is not the end of the list.
  const shorts = 30;
  const heavy = 20;
  const notes = shorts + heavy + 5;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_content_budget_');
    final db = NexDatabase.open(harness.dbPath);
    final now = DateTime.now();

    String shortNote(int i) {
      const en = [
        'remember to call the dentist tomorrow',
        'meeting notes: ship the release on friday',
        'idea: offline-first capture app with no save button',
        'groceries: milk bread eggs',
        'quote from the podcast about attention',
      ];
      const fa = [
        'یادم باشد فردا صبح زنگ بزنم',
        'جلسه ساعت ۱۰ صبح است',
        'ایده‌ی اپلیکیشن جدید برای یادداشت سریع',
        'خرید: شیر نان تخم‌مرغ',
        'این جمله برای تست است',
      ];
      return i.isEven ? en[i % en.length] : fa[i % fa.length];
    }

    String paragraph(Random r) {
      const words = [
        'capture',
        'memory',
        'timeline',
        'یادداشت',
        'جست‌وجو',
        'برنامه',
        'local-first',
        'پروژه',
        'sync',
        'تقویم',
        'reminder',
        'یادآوری',
        'note',
        'یادگاری',
        'search',
        'پیداکردن',
      ];
      return List.generate(
        12 + r.nextInt(18),
        (w) => words[r.nextInt(words.length)],
      ).join(' ');
    }

    /// A long note: many paragraphs, mixed Persian and English, list lines
    /// and blank lines between them — the shape a note takes when someone
    /// writes in it for an hour, or pastes a transcript into it.
    String longNote(int kb, int seed) {
      final r = Random(seed);
      final buf = StringBuffer();
      while (buf.length < kb * 1024) {
        buf.write(paragraph(r));
        buf.write('\n\n');
        if (r.nextBool()) buf.write('- ${paragraph(r)}\n');
      }
      return buf.toString();
    }

    /// A Markdown document with the works, as a converted `.md` file leaves it.
    String markdownDoc(int kb, int seed) {
      final r = Random(seed + 7);
      final buf = StringBuffer('# Document\n\n');
      var section = 0;
      while (buf.length < kb * 1024) {
        section++;
        buf
          ..write('## Section $section\n\n')
          ..write('${paragraph(r)}\n\n')
          ..write('- item one\n- item two\n- item three\n\n')
          ..write('> a quoted line with یک جمله‌ی فارسی\n\n')
          ..write('```\nfn main() {\n    println!("hello");\n}\n```\n\n')
          ..write('| a | b |\n|---|---|\n| 1 | 2 |\n\n')
          ..write(
            'Some **bold**, _italic_ and `code` plus a '
            '[link](https://example.com/page?x=1).\n\n',
          )
          ..write('${paragraph(r)}\n\n');
      }
      return buf.toString();
    }

    void insertNote(String id, String type, String? content, {DateTime? at}) {
      final when = (at ?? now).toIso8601String();
      db.db.execute(
        'INSERT INTO notes (id, type, content, created_at, updated_at, '
        "device_id, rev, sync_state) VALUES (?, ?, ?, ?, ?, 'budget', 1, "
        "'synced')",
        [id, type, content, when, when],
      );
    }

    db.db.execute('BEGIN IMMEDIATE');
    // Today and yesterday: thirty short notes, an hour and a half apart.
    for (var i = 0; i < shorts; i++) {
      insertNote(
        'short-$i',
        'text',
        shortNote(i),
        at: now.subtract(Duration(minutes: 90 * (i + 1))),
      );
    }
    // Two to four days back: the heavy group, same spacing — one date group
    // in the timeline, so folding it exercises all twenty rows at once.
    final longSizes = [8, 16, 32, 64, 128];
    for (var i = 0; i < 5; i++) {
      insertNote(
        'long-$i',
        'text',
        longNote(longSizes[i], 300 + i),
        at: now.subtract(Duration(hours: 24 * 2 + 90 * (i + 1) ~/ 60)),
      );
    }
    final docSizes = [16, 24, 32, 48, 64];
    for (var i = 0; i < 5; i++) {
      insertNote(
        'doc-$i',
        'text',
        markdownDoc(docSizes[i], 400 + i),
        at: now.subtract(Duration(hours: 24 * 2 + 90 * (6 + i) ~/ 60)),
      );
    }
    for (var i = 0; i < 5; i++) {
      final at = now.subtract(Duration(hours: 24 * 2 + 90 * (12 + i) ~/ 60));
      insertNote('file-$i', 'file', 'quarterly-report-$i.md', at: at);
      final when = at.toIso8601String();
      db.db.execute(
        'INSERT INTO note_attachments (id, note_id, position, kind, '
        "media_uri, media_hash, name, mime_type, created_at, updated_at, "
        "device_id, rev, sync_state) VALUES (?, ?, 0, 'file', ?, ?, ?, ?, ?, "
        "?, 'budget', 1, 'synced')",
        [
          'attach-$i',
          'file-$i',
          'file:///media/quarterly-report-$i.md',
          'hash-$i',
          'quarterly-report-$i.md',
          'text/markdown',
          when,
          when,
        ],
      );
    }
    for (var i = 0; i < 5; i++) {
      insertNote(
        'link-$i',
        'link',
        'https://www.example$i.com/a/b?utm=1',
        at: now.subtract(Duration(hours: 24 * 2 + 90 * (18 + i) ~/ 60)),
      );
    }
    // And five short notes at the bottom, so the heavy group is a group in
    // the middle of the list rather than the end of it.
    for (var i = 0; i < 5; i++) {
      insertNote(
        'short-more-$i',
        'text',
        shortNote(i + 3),
        at: now.subtract(Duration(days: 20, minutes: 90 * i)),
      );
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
  /// took in CPU time — the second open, after the first has compiled.
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

  testWidgets('the timeline opens on the mixed library in one window', (
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
    debugPrint('W6.10 mixed open: $ms ms');

    expect(model(tester).notes, hasLength(notes), reason: 'one window read');
    expect(
      find.byType(NoteCard).evaluate().length,
      lessThanOrEqualTo(12),
      reason: 'only what is on screen is built',
    );
    expect(ms, lessThan(1000), reason: 'first card on screen, in CPU time');
    await tester.pumpAndSettle();
  });

  testWidgets('scrolling through the heavy content builds rows in budget', (
    tester,
  ) async {
    phone(tester);
    // Every element that builds is remembered from the first frame on, so
    // one that builds again later is a rebuild — the same instrument W6.3
    // uses, pointed at the same drag over different contents.
    final built = <Element>{};
    var counting = false;
    var rebuilds = 0;
    var frameRebuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (!built.add(element) && counting && !_inStickyDay(element)) {
        frameRebuilds++;
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    await open(tester);
    await tester.pumpAndSettle();
    counting = true;

    // A steady drag from the top of the library through the heavy group:
    // 80px a frame for 60 frames is 4,800px — past every long note and
    // Markdown document (they end around 3,800px) without reaching the
    // bottom of the list, so no overscroll stretch muddies the frames.
    // The first ten frames are warm-up either way: the recap card folds on
    // the first scroll on purpose, which rebuilds the screen once.
    const frames = 60;
    final scroll = <int>[];
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    final watch = Stopwatch();
    for (var i = 0; i < frames; i++) {
      frameRebuilds = 0;
      watch
        ..reset()
        ..start();
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump(const Duration(milliseconds: 16));
      watch.stop();
      if (i >= 10) {
        scroll.add(watch.elapsedMicroseconds);
        rebuilds += frameRebuilds;
      }
    }
    await gesture.up();
    debugOnRebuildDirtyWidget = null;
    await tester.pumpAndSettle();

    scroll.sort();
    final p90 = percentile(scroll, .9) ~/ 1000;
    final p99 = percentile(scroll, .99) ~/ 1000;
    final worst = scroll.last ~/ 1000;
    debugPrint(
      'W6.10 mixed scroll: p90 $p90 ms, p99 $p99 ms, worst $worst ms, '
      '$rebuilds rebuilds',
    );

    expect(
      rebuilds,
      0,
      reason:
          'a widget already built, other than the sticky day, rebuilt '
          'while scrolling',
    );
    expect(
      find.byType(NoteCard).evaluate().length,
      lessThanOrEqualTo(20),
      reason: 'cards scrolled past are let go',
    );
    expect(p90, lessThan(50));
    // Tighter than W6.3's p99 because this library is a twentieth of the
    // size: the frames here are card builds, not window loads. A long
    // note's card entering the viewport used to spend its whole text on
    // the UI thread — a 128KB note alone was a 70ms frame in this VM, and
    // the phone is two and a half times that.
    expect(p99, lessThan(45));
    expect(worst, lessThan(50), reason: 'a frame that builds a heavy card');
  });

  testWidgets('folding the heavy group stays inside its animation budget', (
    tester,
  ) async {
    phone(tester);
    await open(tester);
    await tester.pumpAndSettle();
    final timeline = model(tester);
    expect(timeline.notes, hasLength(notes));

    // Scroll down past the shorts into the heavy group, until the group's
    // own heading is on screen to be tapped. The heading's text is the
    // finder: it is what the row says, and it is stable where its widget
    // types are an implementation detail.
    final header = find.text('Last week');
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    // A row can be built and still be below the screen: the list's cache
    // extent reaches 900px past the viewport. Scroll until the heading is
    // actually on it, mid-screen where the sticky day does not sit over it.
    var headerVisible = false;
    for (var i = 0; i < 90 && !headerVisible; i++) {
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump(const Duration(milliseconds: 16));
      if (header.evaluate().isNotEmpty) {
        final top = tester.getRect(header).top;
        headerVisible = top > 0 && top < 600;
      }
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(header, findsOneWidget, reason: 'the heavy group is on screen');
    expect(
      headerVisible,
      isTrue,
      reason: 'the heading is on the screen itself',
    );
    expect(
      find.byType(NoteCard).evaluate(),
      isNotEmpty,
      reason: 'the heavy group is on screen to be folded',
    );

    // Fold it closed: the rows stay for one 400ms animation while they
    // shrink away. Pumps, not pumpAndSettle, so what is measured is CPU —
    // the whole animation, and the one frame that does the work.
    await tester.tap(header);
    var watch = Stopwatch()..start();
    var worstClosedFrame = 0;
    for (var i = 0; i < 32; i++) {
      final frame = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 16));
      frame.stop();
      if (frame.elapsedMilliseconds > worstClosedFrame) {
        worstClosedFrame = frame.elapsedMilliseconds;
      }
    }
    watch.stop();
    final closedMs = watch.elapsedMilliseconds;
    await tester.pumpAndSettle();
    expect(timeline.collapsedGroups, contains('week'));

    // Open it again: every row of the group is inserted and built inside the
    // fold animation — the burst that used to freeze the list for the better
    // part of a second with this content.
    await tester.tap(header);
    watch = Stopwatch()..start();
    var worstOpenFrame = 0;
    for (var i = 0; i < 32; i++) {
      final frame = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 16));
      frame.stop();
      if (frame.elapsedMilliseconds > worstOpenFrame) {
        worstOpenFrame = frame.elapsedMilliseconds;
      }
    }
    watch.stop();
    await tester.pumpAndSettle();
    final openMs = watch.elapsedMilliseconds;
    debugPrint(
      'W6.10 mixed fold: closed $closedMs ms, open $openMs ms, '
      'worst frames $worstClosedFrame / $worstOpenFrame ms',
    );

    // Calibrated against the fixed path in this VM: the fold is animation
    // frames plus the two that do the work — the insert burst on the tap,
    // and the cleanup rebuild the 400ms timer fires. A long note's card
    // paying its whole text again on each of them is what these ceilings
    // are for: uncapped, the same fold measured a frame and a half again
    // as much CPU.
    expect(closedMs, lessThan(1000), reason: 'closing the heavy group');
    expect(openMs, lessThan(800), reason: 'opening the heavy group');
    expect(
      worstClosedFrame,
      lessThan(400),
      reason: 'the one frame that folds the heavy group away',
    );
    expect(
      worstOpenFrame,
      lessThan(400),
      reason: 'the insert burst — every heavy row built in one frame',
    );
    expect(
      find.byType(NoteCard).evaluate(),
      isNotEmpty,
      reason: 'the group came back',
    );
  });
}

/// The sticky day (W7.1) is the one thing meant to change while scrolling:
/// it names the day passing under the filter row. Nothing else may rebuild.
bool _inStickyDay(Element element) =>
    element.widget is TimelineStickyDay ||
    element.findAncestorWidgetOfExactType<TimelineStickyDay>() != null;
