@Tags(['budget'])
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/timeline/timeline_model.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_client/widgets/note_grid_card.dart';
import 'package:nex_data/nex_data.dart';
import 'package:nex_ui/nex_ui.dart';

import '../support/nex_harness.dart';

/// A diagnostic companion to W6.10: the same mixed library, but every frame
/// of a fold is timed and counted individually, and the fold is exercised in
/// every grouping the home offers — by day, by kind and by tag, in the list
/// and in the grid — with photos in the library as well as links, files and
/// long notes.
///
/// Not a budget: nothing is asserted about the times. The value is the
/// printed profile — which frame of a fold costs what, and whether the
/// widgets that pay for it are being built for the first time (a reveal
/// laying out new cards) or rebuilt (work a fold should not ask for at all).
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
    harness = await NexTestHarness.create(name: 'nex_fold_profile_');
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
    // The tag the heavy notes carry, and one for the shorts.
    db.db.execute(
      "INSERT INTO tags (id, name, created_at) VALUES "
      "('tag-work', 'work', ?), ('tag-journal', 'journal', ?)",
      [now.toIso8601String(), now.toIso8601String()],
    );

    // Thirty short notes today and yesterday.
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

    // Three long notes today, so the "Writing" shelf of a home arranged by
    // kind holds heavy cards rather than only shorts.
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

    // The heavy date group, two to four days back: long notes, Markdown
    // documents, files, links and photos.
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
    // Five photos with real pictures, each with a second picture to collage.
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
    // And five short notes at the bottom, so no group is the end of the list.
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

  TimelineModel model(WidgetTester tester) =>
      tester.state<TimelineScreenState>(find.byType(TimelineScreen)).model;

  double offset(WidgetTester tester) {
    // The outermost Scrollable is the timeline itself; the tag row's
    // horizontal one sits inside it.
    final state = tester.state<ScrollableState>(find.byType(Scrollable).first);
    final position = state.position;
    return position.hasContentDimensions ? position.pixels : 0;
  }

  /// Whether [element] sits inside the pinned tag row, which names the
  /// same tags the shelves do — only a shelf heading folds.
  bool underPinnedTagRow(Element element) {
    const filterKey = ValueKey('filter-header');
    var found = false;
    element.visitAncestorElements((ancestor) {
      if (identical(ancestor.widget.key, filterKey)) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  /// The heading with [text] that sits in the list body rather than in the
  /// pinned tag row — by tag, both say "work", and only the heading folds.
  Element? headingElement(WidgetTester tester, String text) {
    final candidates =
        find
            .text(text)
            .evaluate()
            .where((element) => !underPinnedTagRow(element))
            .map(
              (element) => (
                element,
                tester
                    .getTopLeft(
                      find.byElementPredicate(
                        (other) => identical(other, element),
                      ),
                    )
                    .dy,
              ),
            )
            .toList()
          ..sort((a, b) => a.$2.compareTo(b.$2));
    // The lowest match in the body: the shelves stack in the scroll, and the
    // one being looked for is the last of its name on the screen.
    return candidates.isEmpty ? null : candidates.last.$1;
  }

  Finder headingFinder(Element element) =>
      find.byElementPredicate((other) => identical(other, element));

  /// Scrolls until the [text] heading is on screen, tap-sized.
  Future<Element> scrollTo(WidgetTester tester, String text) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    var visible = false;
    Element? heading;
    for (var i = 0; i < 160 && !visible; i++) {
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump(const Duration(milliseconds: 16));
      heading = headingElement(tester, text);
      if (heading != null) {
        final top = tester.getTopLeft(headingFinder(heading)).dy;
        visible = top > 60 && top < 600;
      }
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(heading, isNotNull, reason: 'the target heading is on screen');
    expect(visible, isTrue, reason: 'the heading is tap-sized on the screen');
    return heading!;
  }

  /// One fold, timed frame by frame. Prints the profile; asserts only that
  /// the fold happened.
  Future<void> fold(
    WidgetTester tester, {
    required Element header,
    required String label,
  }) async {
    final mountedCards = find
        .byWidgetPredicate(isCard, skipOffstage: false)
        .evaluate()
        .toSet();
    var freshCards = 0;
    var rebuiltCards = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (!isCard(element.widget)) return;
      if (!mountedCards.add(element)) {
        rebuiltCards++;
      } else {
        freshCards++;
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    final offsetBefore = offset(tester);
    final tapWatch = Stopwatch()..start();
    await tester.tap(headingFinder(header), warnIfMissed: false);
    tapWatch.stop();

    final frames = <(int, int, int)>[];
    for (var i = 0; i < 44; i++) {
      freshCards = rebuiltCards = 0;
      final watch = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 16));
      watch.stop();
      frames.add((watch.elapsedMilliseconds, freshCards, rebuiltCards));
    }
    final settleWatch = Stopwatch()..start();
    await tester.pumpAndSettle();
    settleWatch.stop();
    debugOnRebuildDirtyWidget = null;

    final total = frames.map((f) => f.$1).fold(0, (a, b) => a + b);
    final rebuilt = frames.fold(0, (sum, frame) => sum + frame.$3);
    final worst = frames.reduce((a, b) => a.$1 >= b.$1 ? a : b);
    final heavy = <String>[
      for (final (i, f) in frames.indexed)
        if (f.$1 >= 24 || f.$2 + f.$3 > 0)
          'f${i.toString().padLeft(2, '0')}=${f.$1}ms(c+${f.$2}/~${f.$3})',
    ];
    debugPrint(
      '$label: tap ${tapWatch.elapsedMilliseconds}ms | total $total ms | '
      'worst ${worst.$1}ms at f${frames.indexOf(worst)} '
      '(fresh cards +${worst.$2}, rebuilt ~${worst.$3}) | '
      'rebuilt cards $rebuilt | settle ${settleWatch.elapsedMilliseconds}ms | '
      'offset ${offsetBefore.toStringAsFixed(0)}'
      '->${offset(tester).toStringAsFixed(0)} | '
      '${heavy.join(' ')}',
    );
  }

  for (final grid in [false, true]) {
    for (final arrange in ['time', 'type', 'tag']) {
      final view = grid ? 'grid' : 'list';
      testWidgets('fold profile: $view by $arrange', (tester) async {
        phone(tester);
        await harness.preferences.setTimelineArrangement(
          NexTimelineArrangement.fromWire(arrange),
        );
        if (grid) {
          await harness.preferences.setTimelineGrid(true);
        }
        final openMs = await open(tester);
        await tester.pumpAndSettle();
        debugPrint('PROFILE $view/$arrange screen open: $openMs ms');

        final text = switch (arrange) {
          'time' => 'Last week',
          'type' => 'Writing',
          _ => 'work',
        };
        final header = await scrollTo(tester, text);

        await fold(
          tester,
          header: header,
          label: 'PROFILE $view/$arrange CLOSE',
        );
        expect(
          model(tester).collapsedGroups,
          isNotEmpty,
          reason: 'the tap folded the group',
        );

        await fold(
          tester,
          header: header,
          label: 'PROFILE $view/$arrange OPEN',
        );
        expect(
          model(tester).collapsedGroups,
          isEmpty,
          reason: 'the second tap opened it again',
        );
      });
    }
  }
}
