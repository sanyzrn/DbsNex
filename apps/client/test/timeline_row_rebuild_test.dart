import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/timeline_shelves.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_client/widgets/note_grid_card.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// What a timeline delivery is allowed to touch: the rows whose notes it
/// changed — and not one card more.
///
/// Every save, capture and delete re-delivers the whole window, and each
/// delivery used to rebuild every mounted card in one frame: the screen's
/// notification rebuilds the slivers, the new rows hand the list a fresh
/// delegate, and the framework rebuilds every visible child of it. One
/// note's edit cost a 100 ms-class frame — the same stutter the folds had
/// just learned not to make. Rows are now kept as the widgets they were,
/// reused while nothing they consumed has moved; these tests hold that
/// promise from both sides: a delivery rebuilds only the rows it must, and
/// the state a row cannot afford to miss — a selection, an edit's new
/// words, a second shelf's copy — still reaches it.
void main() {
  late NexTestHarness harness;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_row_rebuild_');
    for (var i = 0; i < 6; i++) {
      await harness.services.captureText('today note $i');
    }
    final older = await harness.services.captureText('yesterday note');
    (harness.db).backdate(
      older!.id,
      DateTime.now().subtract(const Duration(days: 1)),
    );
    await harness.services.refreshTimeline();
  });

  tearDown(() => harness.dispose());

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
  }

  Finder allCards() => find.byWidgetPredicate(
    (widget) => widget is NoteCard || widget is NexNoteGridCard,
    skipOffstage: false,
  );

  Finder card(String text) =>
      find.ancestor(of: find.text(text), matching: find.byType(NoteCard));

  /// Counts rebuilds of the cards that existed when it was installed —
  /// cached and offstage ones included, which is where a lazy list keeps
  /// its neighbourhood.
  int Function() watchCards(Set<Element> cards) {
    var rebuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (cards.contains(element)) rebuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    return () => rebuilds;
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
  }

  testWidgets('a delivery that edits one note rebuilds only its card', (
    tester,
  ) async {
    phone(tester);
    await open(tester);
    final before = allCards().evaluate().toSet();
    expect(before, isNotEmpty);
    final state = tester.state<TimelineScreenState>(
      find.byType(TimelineScreen),
    );
    final reuseBefore = state.debugRowReuse;

    final rebuilds = watchCards(before);
    // The top note: an edit bumps its updated-at, and the newest note stays
    // the newest, so its row keeps its place — the row that must rebuild,
    // and only it.
    await harness.db.updateNote(
      (await harness.services.timeline()).first.id,
      'today note 5, edited behind the screen',
    );
    await harness.services.refreshTimeline();
    await tester.pumpAndSettle();

    expect(find.text('today note 5, edited behind the screen'), findsOneWidget);
    // The other five cards on screen were reused as the widgets they
    // already were.
    expect(rebuilds(), 1, reason: 'a delivery rebuilt cards it did not change');
    expect(
      state.debugRowReuse,
      greaterThan(reuseBefore),
      reason: 'unchanged rows were served from the row cache',
    );
  });

  testWidgets(
    'a note edited from the bottom moves up without rebuilding the rest',
    (tester) async {
      phone(tester);
      await open(tester);
      final before = allCards().evaluate().toSet();

      final rebuilds = watchCards(before);
      // The oldest note: the same edit, but its updated-at carries it from
      // yesterday's run to the top of today's.
      await harness.db.updateNote(
        (await harness.services.timeline()).last.id,
        'yesterday note, edited behind the screen',
      );
      await harness.services.refreshTimeline();
      await tester.pumpAndSettle();

      expect(
        find.text('yesterday note, edited behind the screen'),
        findsOneWidget,
      );
      expect(rebuilds(), 0, reason: 'a move rebuilt cards it did not change');
    },
  );

  testWidgets('a captured note lands without rebuilding the cards on screen', (
    tester,
  ) async {
    phone(tester);
    await open(tester);
    final before = allCards().evaluate().toSet();

    final rebuilds = watchCards(before);
    await harness.services.captureText('a brand new note');
    // The sheet's own close is what carries a capture to the timeline —
    // see `openCapture` — so the test walks the same last step.
    await harness.services.refreshTimeline();
    await tester.pumpAndSettle();

    expect(find.text('a brand new note'), findsOneWidget);
    expect(rebuilds(), 0, reason: 'a capture rebuilt cards it did not change');
  });

  testWidgets('deleting a note animates it out without rebuilding the rest', (
    tester,
  ) async {
    phone(tester);
    await open(tester);
    final before = allCards().evaluate().toSet();

    final rebuilds = watchCards(before);
    await harness.services.deleteNote(
      (await harness.services.timeline()).last.id,
    );
    await harness.services.refreshTimeline();
    await tester.pumpAndSettle();

    expect(find.text('yesterday note'), findsNothing);
    expect(rebuilds(), 0, reason: 'a delete rebuilt cards it did not change');
  });

  testWidgets('an edited note rebuilds only its tile in the grid', (
    tester,
  ) async {
    phone(tester);
    await harness.preferences.setTimelineGrid(true);
    await open(tester);
    final before = allCards().evaluate().toSet();

    final rebuilds = watchCards(before);
    await harness.db.updateNote(
      (await harness.services.timeline()).first.id,
      'today note 5, edited behind the screen',
    );
    await harness.services.refreshTimeline();
    await tester.pumpAndSettle();

    expect(find.text('today note 5, edited behind the screen'), findsOneWidget);
    expect(rebuilds(), 1, reason: 'a delivery rebuilt tiles it did not change');
  });

  testWidgets('a capture keeps existing grid tiles mounted as they move', (
    tester,
  ) async {
    phone(tester);
    await harness.preferences.setTimelineGrid(true);
    await open(tester);
    final existing = find.ancestor(
      of: find.text('today note 5'),
      matching: find.byType(NexNoteGridCard),
    );
    final before = tester.element(existing);

    await harness.services.captureText('a new grid tile');
    await harness.services.refreshTimeline();
    await tester.pumpAndSettle();

    expect(find.text('a new grid tile'), findsOneWidget);
    expect(tester.element(existing), same(before));
  });

  testWidgets('selection still reaches a row that was reused', (tester) async {
    phone(tester);
    await open(tester);
    // A delivery first, so the rows on screen are the reused ones.
    await harness.db.updateNote(
      (await harness.services.timeline()).first.id,
      'today note 0, edited behind the screen',
    );
    await harness.services.refreshTimeline();
    await tester.pumpAndSettle();

    await tester.longPress(card('today note 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        ValueKey('pick-shield-${(await harness.services.timeline()).first.id}'),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<NoteCard>(card('today note 1')).selected, isTrue);
    expect(
      tester.widget<NoteCard>(card('today note 2')).selected,
      isFalse,
      reason: 'a reused row shows the ring the delivery did not freeze',
    );
  });

  testWidgets('an edit reaches both shelves of a twice-tagged note', (
    tester,
  ) async {
    phone(tester);
    await harness.preferences.setTimelineArrangement(
      NexTimelineArrangement.fromWire('tag'),
    );
    final twice = await harness.services.captureText('a note on two shelves');
    await harness.db.addTag(noteId: twice!.id, name: 'work');
    await harness.db.addTag(noteId: twice.id, name: 'home');
    await harness.services.refreshTimeline();
    await open(tester);
    final before = allCards().evaluate().toSet();

    final rebuilds = watchCards(before);
    await harness.db.updateNote(
      (await harness.services.timeline()).first.id,
      'a note on two shelves, edited',
    );
    await harness.services.refreshTimeline();
    await tester.pumpAndSettle();

    // The note sits on the work shelf and again on the home shelf, and the
    // edit must show in both copies — while the cards around them, one per
    // shelf of the other notes, are reused untouched.
    expect(find.text('a note on two shelves, edited'), findsNWidgets(2));
    expect(rebuilds(), 2);
  });
}
