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
