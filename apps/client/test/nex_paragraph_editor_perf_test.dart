import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/widgets/nex_paragraph_editor.dart';
import 'package:super_editor/src/test/ime.dart';
import 'package:super_editor/super_editor.dart';

/// What a long note costs.
///
/// A note of 500 lines, half Persian and half English — far longer than
/// anything typed in one sitting, short enough to lay out in a test.
///
/// The edits are applied without a frame between them on purpose. A frame
/// costs the same whichever way the note is mirrored (it lays the whole
/// document out), so measuring frames would hide the one thing this file is
/// about: the work a keystroke does *besides* the frame — rebuilding the
/// string, re-reading every paragraph, walking the document to place the
/// caret. The ceilings catch an order-of-magnitude regression, not a few
/// milliseconds on a shared machine.
void main() {
  const lines = 500;
  final note = [
    for (var i = 0; i < lines; i++)
      i.isEven
          ? 'خط فارسی شماره $i با چند واژه و یک Nex در میان'
          : 'English line number $i with a few words and سلام in it',
  ].join('\n');

  testWidgets('a $lines-line note opens, types and selects in bounded time', (
    tester,
  ) async {
    final controller = TextEditingController(text: note);
    controller.selection = TextSelection.collapsed(offset: note.length);

    final open = Stopwatch()..start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: NexParagraphEditor(controller: controller, autofocus: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    open.stop();

    final editor = tester.widget<SuperEditor>(find.byType(SuperEditor)).editor;
    expect(controller.text, note);

    // Typing at the end: the path a person takes when finishing a long note.
    const keystrokes = 60;
    final typing = Stopwatch()..start();
    for (var i = 0; i < keystrokes; i++) {
      final state = tester.testTextInput.editingState!;
      final text = state['text']! as String;
      final at = state['selectionExtent'] as int;
      imeClientGetter().updateEditingValueWithDeltas([
        TextEditingDeltaInsertion(
          oldText: text,
          textInserted: 'x',
          insertionOffset: at,
          selection: TextSelection.collapsed(offset: at + 1),
          composing: TextRange.empty,
        ),
      ]);
    }
    await tester.pump();
    typing.stop();
    expect(controller.text.length, note.length + keystrokes);

    // Moving the caret across the whole note: the drag a person makes before
    // formatting something near the top.
    const moves = 50;
    final nodes = editor.context.document.toList();
    final moving = Stopwatch()..start();
    for (var i = 0; i < moves; i++) {
      final node = nodes[(i * 7) % nodes.length] as TextNode;
      editor.context.composer.setSelectionWithReason(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: node.id,
            nodePosition: TextNodePosition(
              offset: (i * 3) % (node.text.length + 1),
            ),
          ),
        ),
      );
    }
    await tester.pump();
    moving.stop();

    final openMs = open.elapsedMilliseconds;
    final typeMs = typing.elapsedMicroseconds / keystrokes / 1000;
    final moveMs = moving.elapsedMicroseconds / moves / 1000;
    debugPrint(
      'PERF open=${openMs}ms '
      'type=${typeMs.toStringAsFixed(2)}ms/keystroke '
      'select=${moveMs.toStringAsFixed(2)}ms/move',
    );

    expect(openMs, lessThan(5000), reason: 'opening a 500-line note');
    expect(typeMs, lessThan(80), reason: 'one keystroke at the end');
    expect(moveMs, lessThan(60), reason: 'one caret move');
  });
}
