import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  testWidgets('swipe reveals an action and tapping it fires the callback',
      (tester) async {
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

    await tester.drag(find.text('Note'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    expect(deleted, isFalse);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
    expect(find.text('Delete'), findsNothing);

    await tester.drag(find.text('Note'), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(tagged, isFalse);
    await tester.tap(find.text('Add Tag'));
    await tester.pumpAndSettle();
    expect(tagged, isTrue);
  });

  testWidgets('a gesture cannot cross from one action into the other',
      (tester) async {
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
    await tester.drag(find.text('Note'), const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);

    await tester.drag(find.text('Note'), const Offset(320, 0));
    await tester.pumpAndSettle();
    expect(find.text('Add Tag'), findsNothing);
    expect(find.text('Delete'), findsNothing);
    expect(tagged, isFalse);
    expect(deleted, isFalse);

    // And the card is genuinely closed: the next swipe the other way works.
    await tester.drag(find.text('Note'), const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(find.text('Add Tag'), findsOneWidget);
  });

  testWidgets('dragging most of the way across runs the action on release',
      (tester) async {
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
    await tester.drag(find.text('Note'), const Offset(-300, 0));
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
      // measured.
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Note')),
      );
      await gesture.moveBy(Offset(dx / 2, 0));
      await tester.pump();
      await gesture.moveBy(Offset(dx / 2, 0));
      await tester.pump();
      return gesture;
    }

    testWidgets('it sits inside the card gutter, not against the screen edge',
        (tester) async {
      final gesture = await holdSwipe(tester, -120);
      addTearDown(gesture.up);

      final rect = tester.getRect(panel);
      // 400 wide, 16 of gutter on each side, 5 above and below.
      expect(rect.right, closeTo(384, 0.5));
      expect(rect.left, closeTo(264, 0.5), reason: '120 of travel');
      expect(rect.top, closeTo(5, 0.5));
      expect(rect.height, closeTo(70, 0.5));
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

    testWidgets('the glyph waits until there is room, then sits centred',
        (tester) async {
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

  testWidgets('a real card still swipes, scroll view in its meta row and all',
      (tester) async {
    // The date-and-tags row is a horizontal scroll view now, so that a tag too
    // many is clipped instead of wrapping and making the card taller. A
    // scrollable that accepted drags would enter the gesture arena and take
    // the swipe away from the card.
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

    // Started on the tags themselves — the one place a stray scrollable would
    // have claimed the gesture.
    await tester.drag(find.text('Work'), const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
  });

  testWidgets('swipe below threshold snaps closed without sticking',
      (tester) async {
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
    await tester.drag(find.text('Note'), const Offset(-20, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing);
  });
}
