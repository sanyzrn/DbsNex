import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/timeline_shelves.dart';
import 'package:nex_client/widgets/note_grid_card.dart';
import 'package:nex_ui/nex_ui.dart';

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

  Future<void> open(WidgetTester tester) async {
    tester.view.devicePixelRatio = 2.75;
    // Tall, so every shelf is laid out at once.
    tester.view.physicalSize = const Size(1080, 7000);
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
    expect(tester.takeException(), isNull);
  });

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
}
