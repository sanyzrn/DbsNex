@Tags(['budget'])
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/home_layout_sheet.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/screens/photo_crop_screen.dart';
import 'package:nex_client/widgets/capture_sheet.dart';
import 'package:nex_client/widgets/capture_flick.dart';
import 'package:nex_client/widgets/note_editor_sheet.dart';
import 'package:nex_client/widgets/note_grid_card.dart';
import 'package:nex_data/nex_data.dart';
import 'package:nex_ui/nex_ui.dart';

import '../support/nex_harness.dart';

/// A frame-by-frame diagnostic for everything the home screen starts
/// (W7.1): the same mixed library as the fold profile, but the interactions
/// profiled are the ordinary ones — scrolling in both views, the menus the
/// home offers, creating a note, opening and closing note details, editing
/// and saving text and images, and coming back to the home screen.
///
/// Not a budget: nothing is asserted about the times. The value is the
/// printed profile — for each interaction, the tap-to-first-visible-response
/// latency, the per-frame cost, how much of the card tree each frame rebuilt
/// (fresh cards are the reveal of new ones; rebuilt cards are work the
/// interaction should not ask for), and any stall that arrives after the
/// interaction has visually settled.
/// The profile of one interaction: the gesture, every 16ms frame after it,
/// the settle, and a quiet spell that catches late work — an image finishing
/// its decode, a write coming back from the database — as stalls after the
/// settled frame.
class FlowProfile {
  int tapMs = 0;
  int responseFrame = -1;
  int responseMs = -1;
  final frames = <int, (int, int, int, int)>{}; // index -> ms/dirty/fresh/rbt
  int settleMs = 0;
  final postStalls = <String>[];
  Map<Type, int> worstTypes = const {};
}

int _worstOf(List<(int, int, int)> frames) => frames.isEmpty
    ? 0
    : frames.map((f) => f.$1).reduce((a, b) => a > b ? a : b);

void main() {
  img.Image noiseImage(int seed, int width, int height) {
    final r = Random(seed);
    final image = img.Image(width: width, height: height);
    for (final pixel in image) {
      pixel
        ..r = 40 + r.nextInt(180)
        ..g = 40 + r.nextInt(180)
        ..b = 40 + r.nextInt(180);
    }
    return image;
  }

  late NexTestHarness harness;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_flow_profile_');
    final db = NexDatabase.open(harness.dbPath);
    final now = DateTime.now().toUtc();

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

    void insertNote(
      String id,
      String type,
      String? content, {
      DateTime? at,
      String? mediaUri,
    }) {
      final when = (at ?? now).toIso8601String();
      db.db.execute(
        'INSERT INTO notes (id, type, content, media_uri, media_hash, '
        'created_at, updated_at, device_id, rev, sync_state) VALUES '
        "(?, ?, ?, ?, ?, ?, ?, 'budget', 1, 'synced')",
        [
          id,
          type,
          content,
          mediaUri,
          mediaUri == null ? null : 'hash-$id',
          when,
          when,
        ],
      );
    }

    db.db.execute('BEGIN IMMEDIATE');
    db.db.execute(
      "INSERT INTO tags (id, name, created_at) VALUES "
      "('tag-work', 'work', ?), ('tag-journal', 'journal', ?)",
      [now.toIso8601String(), now.toIso8601String()],
    );

    for (var i = 0; i < 30; i++) {
      insertNote(
        'short-$i',
        'text',
        shortNote(i),
        at: now.subtract(Duration(minutes: 90 * (i + 1))),
      );
      if (i % 3 == 0) {
        db.db.execute(
          "INSERT INTO note_tags (note_id, tag_id) VALUES (?, 'tag-journal')",
          ['short-$i'],
        );
      }
    }

    const todaySizes = [32, 64, 128];
    for (var i = 0; i < 3; i++) {
      insertNote(
        'long-today-$i',
        'text',
        longNote(todaySizes[i], 500 + i),
        at: now.subtract(Duration(hours: 2 + i)),
      );
      db.db.execute(
        "INSERT INTO note_tags (note_id, tag_id) VALUES (?, 'tag-work')",
        ['long-today-$i'],
      );
    }

    const longSizes = [8, 16, 32, 64, 128];
    for (var i = 0; i < 5; i++) {
      insertNote(
        'long-$i',
        'text',
        longNote(longSizes[i], 300 + i),
        at: now.subtract(Duration(hours: 24 * 2 + 90 * (i + 1) ~/ 60)),
      );
      db.db.execute(
        "INSERT INTO note_tags (note_id, tag_id) VALUES (?, 'tag-work')",
        ['long-$i'],
      );
    }
    const docSizes = [16, 24, 32, 48, 64];
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
    for (var i = 0; i < 5; i++) {
      final seed = 600 + i;
      final first = '${harness.mediaDir}/fold-photo-$i-a.png';
      final second = '${harness.mediaDir}/fold-photo-$i-b.png';
      File(first).writeAsBytesSync(img.encodePng(noiseImage(seed, 960, 720)));
      File(second)
          .writeAsBytesSync(img.encodePng(noiseImage(seed + 50, 960, 720)));
      final at = now.subtract(Duration(hours: 24 * 3 + 90 * i ~/ 60));
      insertNote(
        'photo-$i',
        'photo',
        'site visit $i — the good light was behind the fence',
        at: at,
        mediaUri: first,
      );
      final when = at.toIso8601String();
      db.db.execute(
        'INSERT INTO note_attachments (id, note_id, position, kind, '
        "media_uri, media_hash, name, mime_type, created_at, updated_at, "
        "device_id, rev, sync_state) VALUES (?, ?, 0, 'photo', ?, ?, NULL, "
        "'image/png', ?, ?, 'budget', 1, 'synced')",
        ['photo-attach-$i', 'photo-$i', first, 'hash-photo-$i', when, when],
      );
      db.db.execute(
        'INSERT INTO note_attachments (id, note_id, position, kind, '
        "media_uri, media_hash, name, mime_type, created_at, updated_at, "
        "device_id, rev, sync_state) VALUES (?, ?, 1, 'photo', ?, ?, NULL, "
        "'image/png', ?, ?, 'budget', 1, 'synced')",
        ['photo-attach2-$i', 'photo-$i', second, 'hash-photo2-$i', when, when],
      );
    }
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

  bool isCard(Widget widget) => widget is NoteCard || widget is NexNoteGridCard;

  Future<int> open(WidgetTester tester) async {
    final watch = Stopwatch()..start();
    await tester.pumpWidget(harness.app());
    final cards = find.byWidgetPredicate(isCard);
    for (var i = 0; i < 200 && cards.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    watch.stop();
    expect(cards, findsWidgets);
    return watch.elapsedMilliseconds;
  }

  double offset(WidgetTester tester) {
    final state = tester.state<ScrollableState>(find.byType(Scrollable).first);
    final position = state.position;
    return position.hasContentDimensions ? position.pixels : 0;
  }

  /// A card whose note [matches], wherever it is in the tree.
  Finder cardWhere(bool Function(Note) matches) => find.byWidgetPredicate(
    (widget) =>
        isCard(widget) &&
        matches(switch (widget) {
          NoteCard card => card.note,
          NexNoteGridCard card => card.note,
          _ => throw StateError('not a card'),
        }),
  );

  /// Scrolls until a card whose note [matches] is built, the way the fold
  /// profile reaches its headings: one held gesture, short moves, a check
  /// after each. Returns the finder for the card.
  Future<Finder> scrollToCard(
    WidgetTester tester,
    bool Function(Note) matches,
  ) async {
    final target = cardWhere(matches);
    // The gesture is only started when there is scrolling to do: a gesture
    // that goes nowhere and comes back up is a tap, and a tap on the middle
    // of the timeline opens a note.
    if (target.evaluate().isEmpty) {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CustomScrollView)),
      );
      for (var i = 0; i < 500 && target.evaluate().isEmpty; i++) {
        await gesture.moveBy(const Offset(0, -60));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }
    expect(target, findsWidgets, reason: 'a card matching the profile\'s note');
    await tester.ensureVisible(target.first);
    await tester.pumpAndSettle();
    return target;
  }

  /// Waits, outside fake time, for [ready] — the way the photo tests do —
  /// while the frames that land meanwhile are timed. Returns the wall-clock
  /// wait and the per-frame times, so real-async work (file reads, isolate
  /// crops, database writes) is measured rather than frozen out.
  Future<(int, List<(int, int, int)>)> waitForReal(
    WidgetTester tester,
    Future<bool> Function() ready, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final frames = <(int, int, int)>[]; // ms, dirty, card rebuilds
    final mountedCards = find
        .byWidgetPredicate(isCard, skipOffstage: false)
        .evaluate()
        .toSet();
    var dirty = 0;
    var rebuilt = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      dirty++;
      if (isCard(element.widget) && !mountedCards.add(element)) rebuilt++;
    };
    final wall = Stopwatch()..start();
    await tester.runAsync(() async {
      while (!(await ready()) && wall.elapsed < timeout) {
        dirty = rebuilt = 0;
        final watch = Stopwatch()..start();
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 16));
        watch.stop();
        frames.add((watch.elapsedMilliseconds, dirty, rebuilt));
      }
    });
    wall.stop();
    debugOnRebuildDirtyWidget = null;
    await tester.pumpAndSettle();
    return (wall.elapsedMilliseconds, frames);
  }

  /// Times [act] the way a person lives it: the gesture itself, then every
  /// 16ms frame until [frames] have passed, then the settle, then a quiet
  /// spell that catches late work — an image finishing its decode, a write
  /// coming back from the database — as stalls after the settled frame.
  Future<FlowProfile> profile(
    WidgetTester tester, {
    required Future<void> Function() act,
    required bool Function() responded,
    int frames = 40,
    int quietFrames = 12,
  }) async {
    final result = FlowProfile();
    final mountedCards = find
        .byWidgetPredicate(isCard, skipOffstage: false)
        .evaluate()
        .toSet();
    var dirty = 0;
    var fresh = 0;
    var rebuilt = 0;
    var frameTypes = <Type, int>{};
    debugOnRebuildDirtyWidget = (element, _) {
      dirty++;
      frameTypes[element.widget.runtimeType] =
          (frameTypes[element.widget.runtimeType] ?? 0) + 1;
      if (!isCard(element.widget)) return;
      if (!mountedCards.add(element)) {
        rebuilt++;
      } else {
        fresh++;
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    final tapWatch = Stopwatch()..start();
    await act();
    tapWatch.stop();
    result.tapMs = tapWatch.elapsedMilliseconds;

    var elapsed = 0;
    var worstTypes = <Type, int>{};
    var worstSoFar = 0;
    for (var i = 0; i < frames; i++) {
      dirty = fresh = rebuilt = 0;
      frameTypes = <Type, int>{};
      final watch = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 16));
      watch.stop();
      result.frames[i] = (watch.elapsedMilliseconds, dirty, fresh, rebuilt);
      if (result.responseFrame < 0 && responded()) {
        result.responseFrame = i;
        result.responseMs = elapsed + watch.elapsedMilliseconds;
      }
      if (watch.elapsedMilliseconds > worstSoFar) {
        worstSoFar = watch.elapsedMilliseconds;
        worstTypes = frameTypes;
      }
      elapsed += 16;
    }
    result.worstTypes = worstTypes;

    final settleWatch = Stopwatch()..start();
    await tester.pumpAndSettle();
    settleWatch.stop();
    result.settleMs = settleWatch.elapsedMilliseconds;

    for (var i = 0; i < quietFrames; i++) {
      dirty = fresh = rebuilt = 0;
      final watch = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 16));
      watch.stop();
      if (watch.elapsedMilliseconds >= 24 || dirty > 0 || rebuilt > 0) {
        result.postStalls.add(
          'q${i.toString().padLeft(2, '0')}=${watch.elapsedMilliseconds}ms'
          '(d$dirty/c+$fresh/~$rebuilt)',
        );
      }
    }
    debugOnRebuildDirtyWidget = null;
    return result;
  }

  void report(String label, FlowProfile p) {
    final total = p.frames.values.map((f) => f.$1).fold(0, (a, b) => a + b);
    final rebuilt = p.frames.values.fold(0, (sum, f) => sum + f.$4);
    final fresh = p.frames.values.fold(0, (sum, f) => sum + f.$3);
    var worst = (0, 0, 0, 0);
    for (final f in p.frames.values) {
      if (f.$1 > worst.$1) worst = f;
    }
    final heavy = <String>[
      for (final entry in p.frames.entries)
        if (entry.value.$1 >= 24 || entry.value.$4 > 0)
          'f${entry.key.toString().padLeft(2, '0')}='
              '${entry.value.$1}ms(c+${entry.value.$3}/~${entry.value.$4})',
    ];
    final top =
        (p.worstTypes.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .take(8)
            .map((entry) => '${entry.key}:${entry.value}')
            .join(' ');
    debugPrint(
      '$label: tap ${p.tapMs}ms | response '
      '${p.responseFrame < 0 ? 'never' : 'f${p.responseFrame} '
                '${p.responseMs}ms'} | total $total ms | worst ${worst.$1}ms '
      '(fresh cards +${worst.$3}, rebuilt ~${worst.$4}) | fresh cards $fresh '
      '| rebuilt cards $rebuilt | settle ${p.settleMs}ms'
      '${p.postStalls.isEmpty ? '' : ' | AFTER SETTLE: '
                '${p.postStalls.join(' ')}'}'
      '${heavy.isEmpty ? '' : ' | ${heavy.join(' ')}'}'
      '${top.isEmpty ? '' : ' | worst-frame widgets: $top'}',
    );
  }

  Future<void> settleAndReport(String label, WidgetTester tester) async {
    final p = await profile(
      tester,
      act: () async {},
      responded: () => false,
      frames: 0,
      quietFrames: 24,
    );
    debugPrint(
      '$label: settle ${p.settleMs}ms'
      '${p.postStalls.isEmpty ? '' : ' | AFTER SETTLE: '
                '${p.postStalls.join(' ')}'}',
    );
  }

  group('scroll', () {
    for (final grid in [false, true]) {
      final view = grid ? 'grid' : 'list';
      testWidgets('scroll profile: $view', (tester) async {
        phone(tester);
        if (grid) await harness.preferences.setTimelineGrid(true);
        final openMs = await open(tester);
        await tester.pumpAndSettle();
        debugPrint('PROFILE scroll/$view screen open: $openMs ms');

        final down = await profile(
          tester,
          act: () async => tester.fling(
            find.byType(CustomScrollView),
            const Offset(0, -2200),
            3500,
          ),
          responded: () => offset(tester) > 400,
          frames: 90,
        );
        report('PROFILE scroll/$view DOWN', down);
        expect(offset(tester), greaterThan(1500));

        await tester.pumpAndSettle();

        final before = offset(tester);
        final up = await profile(
          tester,
          act: () async => tester.fling(
            find.byType(CustomScrollView),
            const Offset(0, 2600),
            3500,
          ),
          responded: () => offset(tester) < before - 200,
          frames: 90,
        );
        report('PROFILE scroll/$view UP', up);
      });
    }
  });

  group('menus', () {
    testWidgets('menu profile: hold menu on a card', (tester) async {
      phone(tester);
      final openMs = await open(tester);
      await tester.pumpAndSettle();
      debugPrint('PROFILE menu/hold screen open: $openMs ms');

      final card = find.byWidgetPredicate(isCard).first;
      final menu = await profile(
        tester,
        act: () async => tester.longPress(card),
        responded: () => find.byType(MenuItemButton).evaluate().isNotEmpty,
        frames: 30,
      );
      report('PROFILE menu/hold OPEN', menu);
      expect(find.byType(MenuItemButton), findsWidgets);

      // Dismissed the way a person does it: a tap away from the menu, on
      // the app bar's own ground (nothing tappable lives there between the
      // corner icons).
      final dismiss = await profile(
        tester,
        act: () async => tester.tapAt(const Offset(196, 40)),
        responded: () => find.byType(MenuItemButton).evaluate().isEmpty,
        frames: 30,
      );
      report('PROFILE menu/hold DISMISS', dismiss);
      expect(find.byType(MenuItemButton), findsNothing);
    });

    testWidgets('menu profile: home layout sheet', (tester) async {
      phone(tester);
      await open(tester);
      await tester.pumpAndSettle();

      final sheet = await profile(
        tester,
        act: () async => tester.tap(find.byTooltip('Home layout')),
        responded: () => find.byType(HomeLayoutSheet).evaluate().isNotEmpty,
        frames: 40,
      );
      report('PROFILE menu/layout OPEN', sheet);
      expect(find.byType(HomeLayoutSheet), findsOneWidget);

      final close = await profile(
        tester,
        act: () async =>
            Navigator.of(tester.element(find.byType(HomeLayoutSheet))).pop(),
        responded: () => find.byType(HomeLayoutSheet).evaluate().isEmpty,
        frames: 40,
      );
      report('PROFILE menu/layout CLOSE', close);
    });
  });

  group('note detail', () {
    for (final grid in [false, true]) {
      final view = grid ? 'grid' : 'list';
      testWidgets('detail profile: light note, $view', (tester) async {
        phone(tester);
        if (grid) await harness.preferences.setTimelineGrid(true);
        await open(tester);
        await tester.pumpAndSettle();

        // Scroll away from the top first, so closing the note has to land
        // the reader back where they were.
        await tester.fling(
          find.byType(CustomScrollView),
          const Offset(0, -700),
          3000,
        );
        await tester.pumpAndSettle();
        final offsetBefore = offset(tester);

        final rise = await profile(
          tester,
          act: () async =>
              tester.tap(find.byWidgetPredicate(isCard).hitTestable().first),
          responded: () => find.byType(NoteDetailSheet).evaluate().isNotEmpty,
          frames: 40,
        );
        report('PROFILE detail/$view OPEN light', rise);
        expect(find.byType(NoteDetailSheet), findsOneWidget);
        await tester.pumpAndSettle();

        final pop = await profile(
          tester,
          act: () async =>
              Navigator.of(tester.element(find.byType(NoteDetailSheet))).pop(),
          responded: () => find.byType(NoteDetailSheet).evaluate().isEmpty,
          frames: 40,
        );
        report('PROFILE detail/$view CLOSE light', pop);

        await settleAndReport('PROFILE detail/$view AFTER CLOSE', tester);
        expect(
          (offset(tester) - offsetBefore).abs(),
          lessThan(2),
          reason: 'closing a note leaves the list where it was',
        );
      });
    }

    testWidgets('detail profile: photo note with attachments', (tester) async {
      phone(tester);
      await open(tester);
      await tester.pumpAndSettle();

      final photoCard = await scrollToCard(
        tester,
        (note) => note.content?.contains('site visit 0') ?? false,
      );
      final rise = await profile(
        tester,
        act: () async => tester.tap(photoCard.first),
        responded: () => find.byType(NoteDetailSheet).evaluate().isNotEmpty,
        frames: 60,
      );
      report('PROFILE detail/list OPEN photo', rise);
      expect(find.byType(NoteDetailSheet), findsOneWidget);
      await tester.pumpAndSettle();
      await settleAndReport('PROFILE detail/list OPEN photo SETTLED', tester);

      final pop = await profile(
        tester,
        act: () async =>
            Navigator.of(tester.element(find.byType(NoteDetailSheet))).pop(),
        responded: () => find.byType(NoteDetailSheet).evaluate().isEmpty,
        frames: 40,
      );
      report('PROFILE detail/list CLOSE photo', pop);
    });

    testWidgets('detail profile: long note', (tester) async {
      phone(tester);
      await open(tester);
      await tester.pumpAndSettle();

      // A long note from today's writing: 32 KB of paragraphs.
      final longCard = await scrollToCard(
        tester,
        (note) => (note.content?.length ?? 0) > 20000,
      );
      final rise = await profile(
        tester,
        act: () async => tester.tap(longCard.first),
        responded: () => find.byType(NoteDetailSheet).evaluate().isNotEmpty,
        frames: 60,
      );
      report('PROFILE detail/list OPEN long', rise);
      await tester.pumpAndSettle();
      await settleAndReport('PROFILE detail/list OPEN long SETTLED', tester);

      final pop = await profile(
        tester,
        act: () async =>
            Navigator.of(tester.element(find.byType(NoteDetailSheet))).pop(),
        responded: () => find.byType(NoteDetailSheet).evaluate().isEmpty,
        frames: 40,
      );
      report('PROFILE detail/list CLOSE long', pop);
    });
  });

  group('capture', () {
    testWidgets('capture profile: type a note and close', (tester) async {
      phone(tester);
      await open(tester);
      await tester.pumpAndSettle();

      final sheet = await profile(
        tester,
        act: () async => tester.tap(find.byType(CaptureFlick)),
        responded: () => find.byType(CaptureSheet).evaluate().isNotEmpty,
        frames: 40,
      );
      report('PROFILE capture OPEN', sheet);
      expect(find.byType(CaptureSheet), findsOneWidget);
      await tester.pumpAndSettle();

      final field = find
          .descendant(
            of: find.byType(CaptureSheet),
            matching: find.byType(TextField),
          )
          .first;
      await tester.tap(field);
      await tester.pumpAndSettle();

      // Type the way a person does, a word at a time, and time the frame
      // each keystroke costs: this is the path that creates the note.
      final words = ['flow', 'flow profile', 'flow profile note created'];
      for (final (i, text) in words.indexed) {
        final stroke = await profile(
          tester,
          act: () async => tester.enterText(field, text),
          responded: () => true,
          frames: 1,
          quietFrames: 0,
        );
        debugPrint(
          'PROFILE capture KEYSTROKE $i: tap ${stroke.tapMs}ms | frame '
          '${stroke.frames.isEmpty ? 0 : stroke.frames[0]!.$1}ms',
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await settleAndReport('PROFILE capture TYPED SETTLED', tester);

      final close = await profile(
        tester,
        act: () async =>
            Navigator.of(tester.element(find.byType(CaptureSheet))).pop(),
        responded: () => find.byType(CaptureSheet).evaluate().isEmpty,
        frames: 60,
      );
      report('PROFILE capture CLOSE (commit)', close);
      await settleAndReport('PROFILE capture AFTER COMMIT', tester);
      final saved = await harness.services.timeline();
      expect(
        saved.any(
          (note) =>
              note.content?.contains('flow profile note created') ?? false,
        ),
        isTrue,
        reason: 'typing then closing left a note behind',
      );
    });
  });

  group('editing', () {
    testWidgets('edit profile: text note edit and save', (tester) async {
      phone(tester);
      await open(tester);
      await tester.pumpAndSettle();

      const noteId = 'short-0';
      final textCard = await scrollToCard(tester, (note) => note.id == noteId);
      await tester.tap(textCard.first);
      await tester.pumpAndSettle();
      expect(find.byType(NoteDetailSheet), findsOneWidget);
      final editor = await profile(
        tester,
        act: () async => tester.tap(
          find.descendant(
            of: find.byType(NoteDetailSheet),
            matching: find.byIcon(Icons.edit_outlined),
          ),
        ),
        responded: () => find.byType(NoteEditorSheet).evaluate().isNotEmpty,
        frames: 40,
      );
      report('PROFILE edit/EDITOR OPEN', editor);
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditorSheet), findsOneWidget);

      final field = find
          .descendant(
            of: find.byType(NoteEditorSheet),
            matching: find.byType(TextField),
          )
          .first;
      await tester.tap(field);
      await tester.pumpAndSettle();
      final original = tester.widget<TextField>(field).controller!.text;
      final typed = await profile(
        tester,
        act: () async => tester.enterText(field, '$original\nedited by hand'),
        responded: () => true,
        frames: 3,
        quietFrames: 0,
      );
      debugPrint(
        'PROFILE edit/KEYSTROKE: tap ${typed.tapMs}ms | frame '
        '${typed.frames.isEmpty ? 0 : typed.frames[0]!.$1}ms',
      );
      await tester.pump(const Duration(milliseconds: 100));

      final save = await profile(
        tester,
        act: () async => tester.tap(find.byTooltip('Save')),
        responded: () => find.byType(NoteEditorSheet).evaluate().isEmpty,
        frames: 60,
      );
      report('PROFILE edit/SAVE', save);
      await settleAndReport('PROFILE edit/AFTER SAVE', tester);

      final edited = await harness.services.getById(noteId);
      expect(
        edited?.content?.contains('edited by hand') ?? false,
        isTrue,
        reason: 'the saved note carries the edit',
      );
      final pop = await profile(
        tester,
        act: () async =>
            Navigator.of(tester.element(find.byType(NoteDetailSheet))).pop(),
        responded: () => find.byType(NoteDetailSheet).evaluate().isEmpty,
        frames: 40,
      );
      report('PROFILE edit/CLOSE DETAIL', pop);
    });

    testWidgets('edit profile: photo crop and save', (tester) async {
      phone(tester);
      await open(tester);
      await tester.pumpAndSettle();

      final photoCard = await scrollToCard(
        tester,
        (note) => note.content?.contains('site visit 1') ?? false,
      );
      // The note the sheet is about, read before the edit: the save is done
      // when its media moves to an "edited-" copy.
      final target = await harness.services.timeline();
      final photoNoteId = target
          .firstWhere((note) => note.content?.contains('site visit 1') ?? false)
          .id;
      Future<String?> mediaUriOf() async =>
          (await harness.services.getById(photoNoteId))?.mediaUri;

      await tester.tap(photoCard.first);
      await tester.pumpAndSettle();
      expect(find.byType(NoteDetailSheet), findsOneWidget);
      final mediaBefore = await mediaUriOf();

      // Reading the source photo is real file I/O: the crop route only
      // appears once it has come back, outside fake time.
      final editorTap = Stopwatch()..start();
      await tester.tap(find.byIcon(Icons.crop_rotate));
      final (cropOpenMs, cropOpenFrames) = await waitForReal(
        tester,
        () async => find.byType(PhotoCropScreen).evaluate().isNotEmpty,
      );
      editorTap.stop();
      debugPrint(
        'PROFILE edit-photo/CROP OPEN: tap+read ${cropOpenMs}ms | '
        'frames ${cropOpenFrames.length} | '
        '${cropOpenFrames.where((f) => f.$1 >= 24).length} over 24ms',
      );
      expect(find.byType(PhotoCropScreen), findsOneWidget);

      // The crop parser and the preview decoder run in real isolates; wait
      // for the confirm button to be live, not merely present: a tap on a
      // disabled button is the nonevent that cost this test its first run.
      Finder confirmButton() => find.ancestor(
        of: find.byIcon(Icons.check),
        matching: find.byType(FilledButton),
      );

      bool confirmEnabled() {
        if (confirmButton().evaluate().isEmpty) return false;
        try {
          return tester.widget<FilledButton>(confirmButton()).onPressed != null;
        } catch (_) {
          return false;
        }
      }

      final (_, readyFrames) = await waitForReal(
        tester,
        () async => confirmEnabled(),
      );
      debugPrint(
        'PROFILE edit-photo/CROP READY: ${readyFrames.length} frames | '
        '${readyFrames.where((f) => f.$1 >= 24).length} over 24ms | '
        'worst ${_worstOf(readyFrames)}ms',
      );

      // Confirming runs the crop in an isolate and then pops: real-async
      // work again, timed as it lands.
      await tester.tap(find.byIcon(Icons.check));
      final (popMs, popFrames) = await waitForReal(
        tester,
        () async => find.byType(PhotoCropScreen).evaluate().isEmpty,
      );
      debugPrint(
        'PROFILE edit-photo/CROP SAVE (pop): ${popMs}ms | frames '
        '${popFrames.length} | rebuilt cards '
        '${popFrames.fold(0, (sum, f) => sum + f.$3)} | '
        'worst ${_worstOf(popFrames)}ms',
      );

      // The save after the pop — writing the file, hashing it, moving the
      // note's media, reloading the sheet, refreshing the timeline — is
      // real-async work as well; time it as it lands.
      final (saveMs, saveFrames) = await waitForReal(
        tester,
        () async => ((await mediaUriOf()) ?? mediaBefore) != mediaBefore,
      );
      final saveRebuilt = saveFrames.fold(0, (sum, f) => sum + f.$3);
      debugPrint(
        'PROFILE edit-photo/SAVE PATH: ${saveMs}ms | frames '
        '${saveFrames.length} | rebuilt cards $saveRebuilt | '
        'worst ${_worstOf(saveFrames)}ms',
      );
      await settleAndReport('PROFILE edit-photo/AFTER SAVE', tester);

      expect(find.byType(NoteDetailSheet), findsOneWidget);
      final pop = await profile(
        tester,
        act: () async =>
            Navigator.of(tester.element(find.byType(NoteDetailSheet))).pop(),
        responded: () => find.byType(NoteDetailSheet).evaluate().isEmpty,
        frames: 40,
      );
      report('PROFILE edit-photo/CLOSE DETAIL', pop);
      await settleAndReport('PROFILE edit-photo/BACK HOME', tester);
    });
  });

  group('search', () {
    testWidgets('search profile: reveal, type, land on results', (
      tester,
    ) async {
      phone(tester);
      await open(tester);
      await tester.pumpAndSettle();

      // The field is the first one on the screen; tapping it is the way a
      // reader arrives at search.
      final field = find.byType(TextField).first;
      final reveal = await profile(
        tester,
        act: () async => tester.tap(field),
        responded: () =>
            find.byKey(const ValueKey('timeline-recap')).evaluate().isEmpty,
        frames: 30,
      );
      report('PROFILE search/REVEAL', reveal);
      await tester.pumpAndSettle();

      final typed = await profile(
        tester,
        act: () async => tester.enterText(field, 'site visit'),
        responded: () => find
            .descendant(
              of: find.byType(TextField),
              matching: find.text('site visit'),
            )
            .evaluate()
            .isNotEmpty,
        frames: 40,
      );
      report('PROFILE search/TYPED', typed);
      await tester.pumpAndSettle();
      await settleAndReport('PROFILE search/RESULTS SETTLED', tester);

      // The second query is the steady state: the first one pays the
      // process's cold path for the whole search machinery.
      final again = await profile(
        tester,
        act: () async => tester.enterText(field, 'meeting notes'),
        responded: () => true,
        frames: 40,
      );
      report('PROFILE search/TYPED AGAIN', again);
      await tester.pumpAndSettle();
    });
  });

  group('return home', () {
    testWidgets('return profile: after detail, the list is where it was', (
      tester,
    ) async {
      phone(tester);
      await open(tester);
      await tester.pumpAndSettle();

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -1400),
        3200,
      );
      await tester.pumpAndSettle();
      final before = offset(tester);

      await tester.tap(find.byWidgetPredicate(isCard).hitTestable().first);
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(NoteDetailSheet))).pop();
      await tester.pumpAndSettle();

      final back = await profile(
        tester,
        act: () async {},
        responded: () => false,
        frames: 0,
        quietFrames: 30,
      );
      debugPrint(
        'PROFILE return/HOME: settle ${back.settleMs}ms'
        '${back.postStalls.isEmpty ? '' : ' | AFTER SETTLE: '
                  '${back.postStalls.join(' ')}'}',
      );
      expect(
        (offset(tester) - before).abs(),
        lessThan(2),
        reason: 'coming home leaves the scroll where the reader left it',
      );
    });
  });
}
