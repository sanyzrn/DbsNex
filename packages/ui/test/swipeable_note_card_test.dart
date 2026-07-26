import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  testWidgets('swipe reveal tap executes delete / add tag', (tester) async {
    var deleted = false;
    var tagged = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: SwipeableNoteCard(
              resolveAction: ({required bool isLeading}) =>
                  isLeading ? NexSwipeAction.addTag : NexSwipeAction.delete,
              onDelete: () => deleted = true,
              onAddTag: () => tagged = true,
              child: const SizedBox(
                height: 80,
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

    // Reveal trailing (delete) by dragging left past threshold.
    await tester.drag(find.text('Note'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(deleted, isFalse);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);

    // Reveal leading (add tag) by dragging right.
    await tester.drag(find.text('Note'), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(tagged, isFalse);
    await tester.tap(find.text('Add Tag'));
    await tester.pumpAndSettle();
    expect(tagged, isTrue);
  });
}
