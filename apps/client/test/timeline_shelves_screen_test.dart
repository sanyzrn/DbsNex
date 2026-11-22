import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/timeline_shelves.dart';
import 'package:nex_client/widgets/note_grid_card.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:nex_core/nex_core.dart';

import 'support/nex_harness.dart';

/// The home arranged by kind or by tag, as a person uses it (2.7.0): the
/// shelves and their headings, "See all", a note on two tag shelves, moving
/// a shelf, the grid, and Persian.
void main() {
  late NexTestHarness harness;

  Future<void> setUpLibrary({
    NexTimelineArrangement by = NexTimelineArrangement.type,
    Map<String, Object> preferences = const {},
  }) async {
    harness = await NexTestHarness.create(
      name: 'nex_shelves_',
      preferences: {'appearance.timeline_arrange': by.name, ...preferences},
    );
    for (var i = 0; i < 8; i++) {
      await harness.services.captureText('written $i');
    }
    await harness.services.captureLink('https://example.com/a');
    await harness.services.captureLink('https://example.com/b');
    await harness.services.refreshTimeline();
  }

  tearDown(() => harness.dispose());

  Future<void> open(WidgetTester tester, {bool tall = true}) async {
    tester.view.devicePixelRatio = 2.75;
    // Tall, so every shelf is laid out at once; a phone's height where the
    // list has to scroll.
    tester.view.physicalSize = Size(1080, tall ? 7000 : 2340);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
  }

  Finder heading(String text) => find.descendant(
    of: find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_GroupHeader',
    ),
    matching: find.text(text),
  );

  testWidgets('by kind: a shelf per kind, the newest six, and See all', (
    tester,
  ) async {
    await setUpLibrary();
    await open(tester);
    expect(heading('Writing'), findsOneWidget);
    expect(heading('Links'), findsOneWidget);
    expect(heading('Today'), findsNothing);
    expect(find.byType(NoteCard), findsNWidgets(8), reason: 'six and two');
    final more = find.byKey(const ValueKey('shelf-more-type:text'));
    expect(more, findsOneWidget);
    expect(
      find.descendant(of: more, matching: find.text('See all 8')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('shelf-more-type:link')), findsNothing);

    await tester.tap(more);
    await tester.pumpAndSettle();
    // The home narrowed to writing: one shelf, which is the whole list.
    expect(heading('Links'), findsNothing);
    expect(find.byType(NoteCard), findsNWidgets(8));
    expect(find.byKey(const ValueKey('shelf-more-type:text')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'by kind: code gets its own shelf and See all keeps only snippets',
    (tester) async {
      await setUpLibrary();
      for (var i = 0; i < 8; i++) {
        await harness.services.captureText(
          NexCodeSnippet(
            code: 'print($i)',
            language: NexCodeLanguage.dart,
          ).markdown,
        );
      }
      await harness.services.refreshTimeline();
      await open(tester);

      expect(heading('Writing'), findsOneWidget);
      expect(heading('Code'), findsOneWidget);
      final more = find.byKey(const ValueKey('shelf-more-type:code'));
      expect(
        find.descendant(of: more, matching: find.text('See all 8')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('shelf-more-type:text')),
        findsOneWidget,
      );
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(heading('Writing'), findsNothing);
      expect(heading('Links'), findsNothing);
      expect(heading('Code'), findsOneWidget);
      expect(find.byType(NoteCard), findsNWidgets(8));
      expect(
        tester
            .widgetList<NoteCard>(find.byType(NoteCard))
            .every((card) => card.note.snippetPreview != null),
        isTrue,
      );
    },
  );

  testWidgets('by tag: a note with two tags sits on both shelves', (
    tester,
  ) async {
    await setUpLibrary(by: NexTimelineArrangement.tag);
    final both = (await harness.services.captureText('the plan'))!;
    await harness.services.addTag(noteId: both.id, name: 'Garden');
    await harness.services.addTag(noteId: both.id, name: 'Errands');
    await harness.services.refreshTimeline();
    await open(tester);
    expect(heading('Garden'), findsOneWidget);
    expect(heading('Errands'), findsOneWidget);
    expect(heading('Untagged'), findsOneWidget);
    expect(find.text('the plan'), findsNWidgets(2));
    await tester.tap(heading('Garden'));
    await tester.pumpAndSettle();
    expect(find.text('the plan'), findsOneWidget);
    await tester.tap(heading('Garden'));
    await tester.pumpAndSettle();
    expect(find.text('the plan'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  for (final explicit in [true, false]) {
    testWidgets(
      'by tag: once every note is tagged, Untagged goes at once '
      '(2.8.1, ${explicit ? 'from the selection bar' : 'from a note\'s details'})',
      (tester) async {
        await setUpLibrary(by: NexTimelineArrangement.tag);
        await open(tester);
        expect(heading('Untagged'), findsOneWidget);
        // Tagged the way the selection bar does it, which refreshes after,
        // and the way a note's details or the assistant do it, which used to
        // leave the home holding a count of notes that were all tagged.
        for (final note in await harness.services.timeline(limit: 50)) {
          await harness.services.addTag(noteId: note.id, name: 'Errands');
        }
        if (explicit) await harness.services.refreshTimeline();
        await tester.pumpAndSettle();
        expect(heading('Untagged'), findsNothing);
        expect(heading('Errands'), findsOneWidget);
      },
    );
  }

  testWidgets('a shelf moved down stays moved', (tester) async {
    await setUpLibrary();
    await open(tester);
    final menu = find.descendant(
      of: find
          .ancestor(of: heading('Writing'), matching: find.byType(Row))
          .last,
      matching: find.byIcon(Icons.more_horiz),
    );
    await tester.tap(menu.first);
    await tester.pumpAndSettle();
    expect(find.text('Move up'), findsNothing, reason: 'it is first');
    await tester.tap(find.text('Move down'));
    await tester.pumpAndSettle();
    expect(
      harness.preferences.timelineShelfOrder(NexTimelineArrangement.type),
      ['type:link', 'type:text'],
    );
    expect(
      tester.getTopLeft(heading('Links')).dy,
      lessThan(tester.getTopLeft(heading('Writing')).dy),
    );
  });

  testWidgets('a shelf that shows only some of its notes cannot be deleted '
      'from its heading', (tester) async {
    await setUpLibrary();
    await open(tester);
    Future<void> openMenu(String shelf) async {
      await tester.tap(
        find
            .descendant(
              of: find
                  .ancestor(of: heading(shelf), matching: find.byType(Row))
                  .last,
              matching: find.byIcon(Icons.more_horiz),
            )
            .first,
      );
      await tester.pumpAndSettle();
    }

    await openMenu('Writing');
    expect(find.text('Delete this group'), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await openMenu('Links');
    expect(find.text('Delete this group'), findsOneWidget);
  });

  testWidgets('the grid shelves the same way', (tester) async {
    await setUpLibrary(preferences: {'appearance.timeline_grid': true});
    await open(tester);
    expect(heading('Writing'), findsOneWidget);
    expect(find.byType(NexNoteGridCard), findsNWidgets(8));
    expect(find.byKey(const ValueKey('shelf-more-type:text')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in Persian, dark and right to left', (tester) async {
    await setUpLibrary(
      preferences: {'appearance.locale': 'fa', 'appearance.theme': 'dark'},
    );
    await open(tester);
    expect(heading('نوشته‌ها'), findsOneWidget);
    expect(heading('لینک‌ها'), findsOneWidget);
    expect(find.text('دیدن همهٔ ۸ تا'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('time is the default, by day as always', (tester) async {
    await setUpLibrary(by: NexTimelineArrangement.time);
    await open(tester);
    expect(heading('Today'), findsOneWidget);
    expect(heading('Writing'), findsNothing);
    expect(find.byType(NoteCard), findsNWidgets(10));
  });

  group('the details, after the owner tried it on a phone (2.7.1)', () {
    Future<void> pinch(WidgetTester tester, {required bool together}) async {
      final point = tester.getCenter(find.byType(CustomScrollView).first);
      final near = const Offset(35, 0), far = const Offset(95, 0);
      final a = await tester.startGesture(
        point - (together ? far : near),
        pointer: together ? 11 : 13,
      );
      final b = await tester.startGesture(
        point + (together ? far : near),
        pointer: together ? 12 : 14,
      );
      await a.moveTo(point - (together ? near : far));
      await b.moveTo(point + (together ? near : far));
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
    }

    testWidgets('a pinch folds the shelves and a spread opens them', (
      tester,
    ) async {
      await setUpLibrary();
      await open(tester);
      await pinch(tester, together: true);
      expect(
        harness.preferences.collapsedTimelineGroups,
        containsAll(['type:text', 'type:link']),
      );
      expect(find.byType(NoteCard), findsNothing);
      await pinch(tester, together: false);
      expect(harness.preferences.collapsedTimelineGroups, isEmpty);
      expect(find.byType(NoteCard), findsNWidgets(8));
    });

    testWidgets('the list holds still under a pinch', (tester) async {
      await setUpLibrary();
      await open(tester, tall: false);
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final before = scroll.pixels;
      final point = tester.getCenter(find.byType(CustomScrollView).first);
      final a = await tester.startGesture(
        point - const Offset(0, 40),
        pointer: 21,
      );
      final b = await tester.startGesture(
        point + const Offset(0, 40),
        pointer: 22,
      );
      // Both fingers travel up the screen as they come together: a drag
      // the list used to follow.
      for (var i = 1; i <= 6; i++) {
        await a.moveBy(const Offset(0, -20));
        await b.moveBy(const Offset(0, -40));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      expect(scroll.pixels, before);
    });

    testWidgets('every chevron sits at the same place along its heading', (
      tester,
    ) async {
      await setUpLibrary(by: NexTimelineArrangement.tag);
      final note = (await harness.services.captureText('a long tag'))!;
      await harness.services.addTag(
        noteId: note.id,
        name: 'An unusually long tag name',
      );
      await harness.services.refreshTimeline();
      await open(tester);
      final chevrons = find.byIcon(Icons.expand_more);
      expect(chevrons, findsAtLeastNWidgets(2));
      final xs = {
        for (final e in chevrons.evaluate())
          tester.getCenter(find.byWidget(e.widget)).dx.round(),
      };
      expect(xs, hasLength(1));
    });

    testWidgets('folded, the chevron points along the line of reading', (
      tester,
    ) async {
      await setUpLibrary(preferences: {'appearance.locale': 'fa'});
      await open(tester);
      await tester.tap(heading('لینک‌ها'));
      await tester.pumpAndSettle();
      final turns = tester
          .widgetList<AnimatedRotation>(find.byType(AnimatedRotation))
          .map((r) => r.turns)
          .toSet();
      expect(turns, containsAll([0.0, 0.25]));
      expect(turns, isNot(contains(-0.25)));
    });

    testWidgets('See all fades the shelf in instead of cutting to it', (
      tester,
    ) async {
      await setUpLibrary();
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('shelf-more-type:text')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final fades = tester
          .widgetList<SliverFadeTransition>(find.byType(SliverFadeTransition))
          .map((f) => f.opacity.value);
      expect(fades.any((v) => v > 0 && v < 1), isTrue);
      await tester.pumpAndSettle();
      expect(heading('Links'), findsNothing);
    });
  });
}
