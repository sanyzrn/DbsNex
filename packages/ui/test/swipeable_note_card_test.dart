import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

/// The middle of a resting card no longer starts a swipe — only its outer
/// 30% edges, on both sides, do (every card here is 400px wide) — so these
/// tests begin each drag from inside whichever edge the direction implies
/// rather than from the finder's own centre. The accumulated distance
/// travelled is what every assertion here cares about, not where the touch
/// happened to land.
Future<void> _dragCard(WidgetTester tester, Finder finder, double dx) {
  final y = tester.getCenter(finder).dy;
  final x = dx < 0 ? 370.0 : 40.0;
  return tester.dragFrom(Offset(x, y), Offset(dx, 0));
}

void main() {
  testWidgets('swipe reveals an action and tapping it fires the callback', (
    tester,
  ) async {
    var deleted = false;
    var tagged = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: SwipeableNoteCard(
              deleteLabel: 'Delete',
              addTagLabel: 'Add Tag',
              resolveAction: ({required bool isLeading}) =>
                  isLeading ? NexSwipeAction.addTag : NexSwipeAction.delete,
              onDelete: () => deleted = true,
              onAddTag: () => tagged = true,
              child: const SizedBox(
                height: 80,
                width: double.infinity,
                child: ColoredBox(
                  color: Colors.white,
                  child: Center(child: Text('Note')),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Closed: Delete label must not leak / stay visible.
    expect(find.text('Delete'), findsNothing);

    await _dragCard(tester, find.text('Note'), -200);
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    expect(deleted, isFalse);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
    expect(find.text('Delete'), findsNothing);

    await _dragCard(tester, find.text('Note'), 200);
    await tester.pumpAndSettle();
    expect(tagged, isFalse);
    await tester.tap(find.text('Add Tag'));
    await tester.pumpAndSettle();
    expect(tagged, isTrue);
  });

  testWidgets(
    'a resting card only opens from its outer edges, not its middle',
    (tester) async {
      // Reported symptom: the whole card swiped, so scrolling or tapping near
      // the middle of a card had a real chance of being read as the start of a
      // swipe. Only the outer 30% on each side may open it now.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: SwipeableNoteCard(
                deleteLabel: 'Delete',
                addTagLabel: 'Add Tag',
                resolveAction: ({required bool isLeading}) =>
                    isLeading ? NexSwipeAction.addTag : NexSwipeAction.delete,
                onDelete: () {},
                onAddTag: () {},
                child: const SizedBox(
                  height: 80,
                  width: double.infinity,
                  child: ColoredBox(
                    color: Colors.white,
                    child: Center(child: Text('Note')),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Dead centre of a 400px card: inside the middle 40%, which starts
      // nothing.
      await tester.dragFrom(
        Offset(200, tester.getCenter(find.text('Note')).dy),
        const Offset(-150, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsNothing);

      // The same travel, but begun inside the trailing 30% (280-400 of 400),
      // opens it.
      await _dragCard(tester, find.text('Note'), -150);
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
    },
  );

  testWidgets('the trailing zone is the same width as the leading one', (
    tester,
  ) async {
    // Reported as asymmetric: 30% on the left, 20% on the right. x=300 on a
    // 400px card sits inside a 30% trailing zone (280-400) but outside a 20%
    // one (320-400) — so this only opens with both edges equal.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: SwipeableNoteCard(
              deleteLabel: 'Delete',
              addTagLabel: 'Add Tag',
              resolveAction: ({required bool isLeading}) =>
                  NexSwipeAction.delete,
              onDelete: () {},
              onAddTag: () {},
              child: const SizedBox(
                height: 80,
                width: double.infinity,
                child: ColoredBox(
                  color: Colors.white,
                  child: Center(child: Text('Note')),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.dragFrom(
      Offset(300, tester.getCenter(find.text('Note')).dy),
      const Offset(-150, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('a gesture cannot cross from one action into the other', (
    tester,
  ) async {
    var deleted = false;
    var tagged = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: SwipeableNoteCard(
              deleteLabel: 'Delete',
              addTagLabel: 'Add Tag',
              resolveAction: ({required bool isLeading}) =>
                  isLeading ? NexSwipeAction.addTag : NexSwipeAction.delete,
              onDelete: () => deleted = true,
              onAddTag: () => tagged = true,
              child: const SizedBox(
                height: 80,
                width: double.infinity,
                child: ColoredBox(
                  color: Colors.white,
                  child: Center(child: Text('Note')),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Open Delete, then drag back further than it travelled. It must close and
    // stop, not continue into Add Tag on the other side.
    await _dragCard(tester, find.text('Note'), -150);
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);

    await _dragCard(tester, find.text('Note'), 320);
    await tester.pumpAndSettle();
    expect(find.text('Add Tag'), findsNothing);
    expect(find.text('Delete'), findsNothing);
    expect(tagged, isFalse);
    expect(deleted, isFalse);

    // And the card is genuinely closed: the next swipe the other way works.
    await _dragCard(tester, find.text('Note'), 150);
    await tester.pumpAndSettle();
    expect(find.text('Add Tag'), findsOneWidget);
  });

  testWidgets('dragging most of the way across runs the action on release', (
    tester,
  ) async {
    var deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: SwipeableNoteCard(
              deleteLabel: 'Delete',
              addTagLabel: 'Add Tag',
              resolveAction: ({required bool isLeading}) =>
                  NexSwipeAction.delete,
              onDelete: () => deleted = true,
              onAddTag: () {},
              child: const SizedBox(
                height: 80,
                width: double.infinity,
                child: ColoredBox(
                  color: Colors.white,
                  child: Center(child: Text('Note')),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Past 62% of 400px, so releasing acts rather than parking the panel open.
    await _dragCard(tester, find.text('Note'), -300);
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
    expect(find.text('Delete'), findsNothing);
  });

  group('the panel is a capsule that belongs to the card', () {
    /// The panel, wherever it is: the only stadium-shaped Material on screen.
    final panel = find.byWidgetPredicate(
      (widget) => widget is Material && widget.shape is StadiumBorder,
    );

    Future<TestGesture> holdSwipe(WidgetTester tester, double dx) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: SwipeableNoteCard(
                deleteLabel: 'Delete',
                addTagLabel: 'Add Tag',
                resolveAction: ({required bool isLeading}) =>
                    NexSwipeAction.delete,
                onDelete: () {},
                onAddTag: () {},
                child: const SizedBox(
                  height: 80,
                  width: double.infinity,
                  child: ColoredBox(
                    color: Colors.white,
                    child: Center(child: Text('Note')),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // Held rather than released: a partial swipe is a state the user sees,
      // and letting go of it would snap the card shut before anything could be
      // measured. Started from the trailing edge zone — every call here drags
      // leftward — since the middle of a resting card no longer opens.
      final gesture = await tester.startGesture(
        Offset(370, tester.getCenter(find.text('Note')).dy),
      );
      await gesture.moveBy(Offset(dx / 2, 0));
      await tester.pump();
      await gesture.moveBy(Offset(dx / 2, 0));
      await tester.pump();
      return gesture;
    }

    testWidgets('it sits inside the card gutter, not against the screen edge', (
      tester,
    ) async {
      final gesture = await holdSwipe(tester, -120);
      addTearDown(gesture.up);

      final rect = tester.getRect(panel);
      // 400 wide, and the card's own gutter on every side — read from the
      // token rather than restated, so the two cannot drift apart.
      expect(rect.right, closeTo(400 - nexCardInsets.right, 0.5));
      expect(
        rect.left,
        closeTo(400 - nexCardInsets.right - 120, 0.5),
        reason: '120 of travel',
      );
      expect(rect.top, closeTo(nexCardInsets.top, 0.5));
      expect(rect.height, closeTo(80 - nexCardInsets.vertical, 0.5));
      // The old panel ran to x = 0 and the full height, past the card on every
      // side.
      expect(rect.left, greaterThan(0));
    });

    testWidgets('it is fully rounded at every width', (tester) async {
      final narrow = await holdSwipe(tester, -30);
      final atNarrow = tester.getRect(panel);
      expect(atNarrow.width, closeTo(30, 1));
      await narrow.up();
      await tester.pumpAndSettle();

      final wide = await holdSwipe(tester, -200);
      addTearDown(wide.up);
      expect(tester.getRect(panel).width, closeTo(200, 1));

      // One shape at both sizes: a vertical pill when narrow, a lozenge when
      // wide, and never a rectangle.
      expect(
        tester.widgetList<Material>(panel).map((m) => m.shape),
        everyElement(isA<StadiumBorder>()),
      );
    });

    testWidgets('the glyph waits until there is room, then sits centred', (
      tester,
    ) async {
      final narrow = await holdSwipe(tester, -40);
      double glyphOpacity() => tester
          .widgetList<FadeTransition>(
            find.descendant(of: panel, matching: find.byType(FadeTransition)),
          )
          .first
          .opacity
          .value;

      await tester.pumpAndSettle();
      expect(glyphOpacity(), 0, reason: 'no room for it yet');
      await narrow.up();
      await tester.pumpAndSettle();

      final wide = await holdSwipe(tester, -160);
      addTearDown(wide.up);
      await tester.pumpAndSettle();
      expect(glyphOpacity(), 1);

      // Centred in the panel, not in the space the swipe opened up.
      expect(
        tester.getCenter(find.byIcon(Icons.delete_outline)).dx,
        closeTo(tester.getRect(panel).center.dx, 0.5),
      );
    });
  });

  testWidgets('a real card still swipes, tag marks and all', (tester) async {
    // The tags are dots down the trailing edge now. They sit exactly where a
    // horizontal swipe starts and ends, so if they ever claimed the gesture —
    // by becoming a scrollable, a button, or anything else in the arena — the
    // card would stop swiping on precisely the notes that have tags.
    final now = DateTime.utc(2026, 7, 28);
    var deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: SwipeableNoteCard(
              deleteLabel: 'Delete',
              addTagLabel: 'Add Tag',
              resolveAction: ({required bool isLeading}) =>
                  NexSwipeAction.delete,
              onDelete: () => deleted = true,
              onAddTag: () {},
              child: NoteCard(
                note: Note(
                  id: 'n1',
                  type: NoteType.text,
                  content: 'a note with several tags on it',
                  createdAt: now,
                  updatedAt: now,
                  deviceId: 'test',
                  rev: 1,
                  syncState: SyncState.pending,
                  tags: [
                    for (final name in ['Work', 'Idea', 'Flutter', 'Learning'])
                      Tag(id: 't-$name', name: name, createdAt: now),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Started right at the trailing edge — exactly where the dots sit, and
    // now the only place a rightward-opening swipe may begin at all — and
    // dragged back across them.
    await _dragCard(tester, find.text('a note with several tags on it'), -150);
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
  });

  testWidgets('swipe below threshold snaps closed without sticking', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: SwipeableNoteCard(
              deleteLabel: 'Delete',
              addTagLabel: 'Add Tag',
              resolveAction: ({required bool isLeading}) =>
                  NexSwipeAction.delete,
              onDelete: () {},
              onAddTag: () {},
              child: const SizedBox(
                height: 80,
                width: double.infinity,
                child: ColoredBox(
                  color: Colors.white,
                  child: Center(child: Text('Note')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _dragCard(tester, find.text('Note'), -20);
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing);
  });

  group('a long press on the middle zone reorders the list', () {
    /// Three 80px cards in a real [SliverReorderableList], the way the
    /// timeline wires them — [SwipeableNoteCard.reorderIndex] only does
    /// anything with one of these as an ancestor.
    ///
    /// A sliver list gives every item a tight width equal to its own cross
    /// axis extent, so a `SizedBox(width: 400)` around one item is ignored —
    /// the 400px card the zone maths below assume only exists if the whole
    /// scroll view is that wide.
    Widget harness(void Function(int, int) onReorder) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: CustomScrollView(
            slivers: [
              SliverReorderableList(
                itemCount: 3,
                onReorder: onReorder,
                itemBuilder: (context, index) => SizedBox(
                  key: ValueKey(index),
                  child: SwipeableNoteCard(
                    reorderIndex: index,
                    deleteLabel: 'Delete',
                    addTagLabel: 'Add Tag',
                    resolveAction: ({required bool isLeading}) =>
                        NexSwipeAction.delete,
                    onDelete: () {},
                    onAddTag: () {},
                    child: SizedBox(
                      height: 80,
                      width: double.infinity,
                      child: ColoredBox(
                        color: Colors.white,
                        child: Center(child: Text('Note $index')),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    testWidgets(
      'held past the long-press delay, then dragged, moves the item',
      (tester) async {
        final reordered = <(int, int)>[];
        await tester.pumpWidget(
          harness((from, to) => reordered.add((from, to))),
        );

        // Well inside the middle 40% of a 400px card.
        final gesture = await tester.startGesture(
          Offset(200, tester.getCenter(find.text('Note 0')).dy),
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await gesture.moveBy(const Offset(0, 200));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(reordered, isNotEmpty);
      },
    );

    testWidgets('the same hold-and-drag from an edge zone does not reorder', (
      tester,
    ) async {
      final reordered = <(int, int)>[];
      await tester.pumpWidget(harness((from, to) => reordered.add((from, to))));

      // Trailing 30% of a 400px card — a swipe zone, not the reorder zone.
      final gesture = await tester.startGesture(
        Offset(370, tester.getCenter(find.text('Note 0')).dy),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 200));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(reordered, isEmpty);
    });

    testWidgets('a quick tap on the middle zone still reaches the child', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverReorderableList(
                  itemCount: 1,
                  onReorder: (_, __) {},
                  itemBuilder: (context, index) => SizedBox(
                    key: const ValueKey(0),
                    width: 400,
                    child: SwipeableNoteCard(
                      reorderIndex: 0,
                      deleteLabel: 'Delete',
                      addTagLabel: 'Add Tag',
                      resolveAction: ({required bool isLeading}) =>
                          NexSwipeAction.delete,
                      onDelete: () {},
                      onAddTag: () {},
                      child: GestureDetector(
                        onTap: () => tapped = true,
                        child: const SizedBox(
                          height: 80,
                          width: double.infinity,
                          child: ColoredBox(
                            color: Colors.white,
                            child: Center(child: Text('Note')),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('Note'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });
  });
}
