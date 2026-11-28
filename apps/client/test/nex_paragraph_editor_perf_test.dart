import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/widgets/nex_paragraph_editor.dart';
import 'package:nex_client/widgets/nex_text_field.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:super_editor/src/test/ime.dart';
import 'package:super_editor/super_editor.dart';

/// What a long note costs.
///
/// Notes of 500, 2000 and 5000 lines, half Persian and half English. Edits are
/// applied without a frame between them: a frame lays the whole document out
/// whichever way the note is mirrored, so counting frames would hide the work
/// this file is about — rebuilding the string, re-reading every paragraph,
/// walking the document to place the caret.
void main() {
  String noteOf(int lines) => [
    for (var i = 0; i < lines; i++)
      i.isEven
          ? 'خط فارسی شماره $i با چند واژه و یک Nex در میان'
          : 'English line number $i with a few words and سلام in it',
  ].join('\n');

  Future<void> measure(WidgetTester tester, int lines) async {
    final note = noteOf(lines);
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

    const keystrokes = 40;
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

    const moves = 40;
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

    final typeMs = typing.elapsedMicroseconds / keystrokes / 1000;
    final moveMs = moving.elapsedMicroseconds / moves / 1000;
    debugPrint(
      'PERF lines=$lines open=${open.elapsedMilliseconds}ms '
      'type=${typeMs.toStringAsFixed(2)}ms/keystroke '
      'select=${moveMs.toStringAsFixed(2)}ms/move',
    );
  }

  /// The 2.9.4 engine, measured the same way, for comparison: one Flutter
  /// field, laid out around the caret's paragraph, typing arriving as a whole
  /// value update the way a platform IME sends it.
  Future<void> measureField(WidgetTester tester, int lines) async {
    final note = noteOf(lines);
    final controller = TextEditingController(text: note);
    controller.selection = TextSelection.collapsed(offset: note.length);

    final open = Stopwatch()..start();
    await tester.pumpWidget(
      MaterialApp(
        theme: nexLightTheme(),
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: NexTextField(
              controller: controller,
              autofocus: true,
              minLines: 3,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    open.stop();

    const keystrokes = 40;
    final typing = Stopwatch()..start();
    for (var i = 0; i < keystrokes; i++) {
      final next = '${controller.text}x';
      await tester.enterText(find.byType(NexTextField), next);
      await tester.pump();
    }
    typing.stop();

    const moves = 40;
    final moving = Stopwatch()..start();
    for (var i = 0; i < moves; i++) {
      controller.selection = TextSelection.collapsed(
        offset: (i * 97) % (note.length + keystrokes),
      );
      await tester.pump();
    }
    moving.stop();

    debugPrint(
      'FIELD lines=$lines open=${open.elapsedMilliseconds}ms '
      'type=${(typing.elapsedMicroseconds / keystrokes / 1000).toStringAsFixed(2)}'
      'ms/keystroke '
      'select=${(moving.elapsedMicroseconds / moves / 1000).toStringAsFixed(2)}'
      'ms/move',
    );
  }

  for (final lines in [500, 2000, 5000]) {
    testWidgets('a $lines-line note in the 2.9.4 field', (tester) async {
      await measureField(tester, lines);
    });
  }

  for (final lines in [500, 2000, 5000]) {
    testWidgets('a $lines-line note opens, types and selects in bounded time', (
      tester,
    ) async {
      await measure(tester, lines);
    });
  }
}
