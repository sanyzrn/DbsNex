import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
