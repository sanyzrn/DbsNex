import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/widgets/nex_text_field.dart';

/// Horizontal arrows move where the eye moves, not where the string goes.
///
/// Flutter's own movement is logical: in a Persian paragraph the right arrow
/// moved the caret to the left of the letter it was on, and at a boundary
/// between two directions it ignored the run it was standing in. These tests
/// hold the field to the movement every platform's own text view gives: the
/// next caret to the right or left **on screen**, found from the laid-out
/// text (see `nex_caret_movement.dart`), and the same rule for Shift.
void main() {
  Future<TextEditingController> pump(
    WidgetTester tester,
    String text, {
    TextDirection ambient = TextDirection.ltr,
    double width = 360,
  }) async {
    final controller = TextEditingController(text: text);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: ambient,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: NexTextField(
                  controller: controller,
                  maxLines: 5,
                  autofocus: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> place(
    WidgetTester tester,
    TextEditingController controller,
    int offset,
  ) async {
    controller.selection = TextSelection.collapsed(offset: offset);
    await tester.pump();
  }

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool shift = false,
  }) async {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
  }

  testWidgets('a Persian paragraph moves the way it is drawn', (tester) async {
    // «سلام hello» in a right-to-left field. The Persian letters run from the
    // right edge toward the left, so the right arrow goes *back* in the
    // string: from the second letter it reaches the first. Flutter's own
    // movement did the opposite.
    final controller = await pump(tester, 'سلام hello');
    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.rtl,
    );

    await place(tester, controller, 2);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(controller.selection.baseOffset, 1);
    expect(controller.selection.isCollapsed, isTrue);

    await place(tester, controller, 2);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(controller.selection.baseOffset, 3);
  });

  testWidgets('an English word inside a Persian paragraph keeps its own way', (
    tester,
  ) async {
    // The whole field is laid out right to left, but these letters are drawn
    // left to right. A rule that flipped the whole paragraph would reverse
    // the arrows inside the English word; the caret's own geometry does not.
    final controller = await pump(tester, 'سلام hello');

    await place(tester, controller, 6);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(
      controller.selection.baseOffset,
      7,
      reason: 'the eye moves right through "hello"',
    );

    await place(tester, controller, 6);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(controller.selection.baseOffset, 5);
  });

  testWidgets('a Persian word inside an English paragraph runs backward', (
    tester,
  ) async {
    // The mirror image: a left-to-right field whose Persian word is drawn
    // from right to left. Inside it, the right arrow moves to the *earlier*
    // character, as it does in any right-to-left text.
    final controller = await pump(tester, 'hello سلام');
    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.ltr,
    );

    await place(tester, controller, 8);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(controller.selection.baseOffset, 7);

    await place(tester, controller, 8);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(controller.selection.baseOffset, 9);
  });

  testWidgets('Shift selects in the same direction the arrows move', (
    tester,
  ) async {
    final controller = await pump(tester, 'سلام hello');
    await place(tester, controller, 6);

    await press(tester, LogicalKeyboardKey.arrowRight, shift: true);
    expect(controller.selection.baseOffset, 6);
    expect(controller.selection.extentOffset, 7);

    await place(tester, controller, 6);
    await press(tester, LogicalKeyboardKey.arrowLeft, shift: true);
    expect(controller.selection.baseOffset, 6);
    expect(controller.selection.extentOffset, 5);
  });

  testWidgets('a plain arrow collapses a selection to the side it points at', (
    tester,
  ) async {
    // The selection from the second Persian letter to the end of "hello"
    // covers the whole right-hand part of the line; its *right* end is the
    // Persian one. Pressing right must collapse there, not to the logical
    // end of the selection, which is drawn on the left.
    final controller = await pump(tester, 'سلام hello');
    controller.selection = const TextSelection(baseOffset: 2, extentOffset: 6);
    await tester.pump();

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.baseOffset, 2);
  });

  testWidgets('the left arrow keeps its ordinary meaning in English', (
    tester,
  ) async {
    // The change must be invisible in a single-language left-to-right note.
    final controller = await pump(tester, 'hello world');
    await place(tester, controller, 5);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(controller.selection.baseOffset, 4);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(controller.selection.baseOffset, 5);
  });

  testWidgets('an arrow at the end of the line does not get stuck', (
    tester,
  ) async {
    final controller = await pump(tester, 'hello');
    await place(tester, controller, 0);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(controller.selection.baseOffset, 0);
    await place(tester, controller, 5);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(controller.selection.baseOffset, 5);
  });

  testWidgets('moving across paragraphs keeps the editor, focus and keyboard', (
    tester,
  ) async {
    // The direction turns as the caret crosses into the English paragraph.
    // That is a rebuild of the layout, never of the editor: the same element
    // keeps the focus, the selection and the one input connection.
    final controller = await pump(tester, 'سلام\nhello');
    final editor = find.byType(EditableText);
    final before = tester.state<EditableTextState>(editor);
    final log = tester.testTextInput.log;
    log.clear();

    await place(tester, controller, 4);
    await press(tester, LogicalKeyboardKey.arrowDown);

    expect(tester.state<EditableTextState>(editor), same(before));
    expect(before.widget.focusNode.hasFocus, isTrue);
    expect(controller.selection.isValid, isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.ltr,
      reason: 'the caret crossed into the English paragraph',
    );
    expect(
      log.map((call) => call.method),
      isNot(contains('TextInput.hide')),
      reason: 'a caret move is not an editor handoff',
    );
  });

  testWidgets('the caret can be moved back and forth without drifting', (
    tester,
  ) async {
    // Every step is the neighbouring caret on screen, so a right then a left
    // from the same place returns to it — including across a direction
    // boundary, where a logical rule would have left the caret elsewhere.
    final controller = await pump(tester, 'سلام hello');
    for (final start in [1, 3, 4, 5, 6, 8, 9]) {
      await place(tester, controller, start);
      await press(tester, LogicalKeyboardKey.arrowRight);
      final afterRight = controller.selection.baseOffset;
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(
        controller.selection.baseOffset,
        start,
        reason:
            'right then left did not return to $start (went to $afterRight)',
      );
    }
  });
}
