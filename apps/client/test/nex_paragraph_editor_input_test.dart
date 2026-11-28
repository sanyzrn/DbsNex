import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/widgets/nex_paragraph_editor.dart';
import 'package:super_editor/src/test/ime.dart';
import 'package:super_editor/super_editor.dart';

/// The editor driven the way a person drives it.
///
/// The other editor test writes into the controller — the *external write*
/// path (an AI rewrite, a recovered draft). This one uses the paths a person
/// actually takes:
///
/// * **the platform IME**, which is where typing arrives on every target:
///   Super Editor's `TextInputSource.ime` is its default, so Android's soft
///   keyboard and a Windows keyboard both deliver characters as editing
///   deltas. They are built here against the value the engine published to the
///   IME (it prefixes a placeholder so Backspace can cross a paragraph
///   boundary), never against the note's own offsets;
/// * **key events**, for the keys that are keys on a desktop — Backspace,
///   Enter, and the backend's undo;
/// * **the engine's own selection**, for a drag that starts below and ends
///   above, which no delta can express without the platform's own coordinates.
///
/// What is asserted is what a person sees: the note's plain string, the caret
/// in absolute offsets, and the direction every paragraph was laid out with.
void main() {
  Future<TextEditingController> pump(
    WidgetTester tester, {
    String text = '',
    TextSelection? selection,
    bool readOnly = false,
  }) async {
    final controller = TextEditingController(text: text);
    if (selection != null) controller.selection = selection;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: NexParagraphEditor(
              controller: controller,
              autofocus: true,
              readOnly: readOnly,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Editor engine(WidgetTester tester) =>
      tester.widget<SuperEditor>(find.byType(SuperEditor)).editor;

  List<ParagraphComponentViewModel> laidOut(WidgetTester tester) => [
    for (final element in find.byType(ParagraphComponent).evaluate())
      (element.widget as ParagraphComponent).viewModel,
  ];

  List<TextDirection> directions(WidgetTester tester) => [
    for (final line in laidOut(tester)) line.textDirection,
  ];

  List<TextAlign?> alignments(WidgetTester tester) => [
    for (final line in laidOut(tester)) line.textAlignment,
  ];

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    String? character,
  }) async {
    await simulateKeyDownEvent(key, character: character);
    await simulateKeyUpEvent(key);
    await tester.pumpAndSettle();
  }

  /// Where an absolute offset sits in the document the editor built.
  DocumentPosition positionAt(Editor editor, int offset) {
    var remaining = offset;
    for (final node in editor.context.document) {
      final length = node is TextNode ? node.text.length : 0;
      if (remaining <= length) {
        return DocumentPosition(
          nodeId: node.id,
          nodePosition: TextNodePosition(offset: remaining),
        );
      }
      remaining -= length + 1;
    }
    throw RangeError.value(offset, 'offset', 'past the end of the document');
  }

  /// A drag or a shift-arrow, as the engine records one: [base] is the end the
  /// finger holds, [extent] the end it moved to.
  void select(WidgetTester tester, {required int base, required int extent}) {
    final editor = engine(tester);
    editor.context.composer.setSelectionWithReason(
      DocumentSelection(
        base: positionAt(editor, base),
        extent: positionAt(editor, extent),
      ),
      SelectionReason.userInteraction,
    );
  }

  /// The value the engine last published to the IME.
  TextEditingValue imeValue(WidgetTester tester) {
    final state = tester.testTextInput.editingState;
    expect(
      state,
      isNotNull,
      reason: 'the engine publishes its text to the IME',
    );
    return TextEditingValue(
      text: state!['text']! as String,
      selection: TextSelection(
        baseOffset: (state['selectionBase'] as int?) ?? -1,
        extentOffset: (state['selectionExtent'] as int?) ?? -1,
      ),
    );
  }

  void insertThroughIme(
    WidgetTester tester,
    DeltaTextInputClient client,
    String inserted,
  ) {
    final value = imeValue(tester);
    final at = value.selection.isValid
        ? value.selection.end
        : value.text.length;
    client.updateEditingValueWithDeltas([
      TextEditingDeltaInsertion(
        oldText: value.text,
        textInserted: inserted,
        insertionOffset: at,
        selection: TextSelection.collapsed(offset: at + inserted.length),
        composing: TextRange.empty,
      ),
    ]);
  }

  testWidgets('typing through the IME appends at the caret and keeps the note '
      'a plain string', (tester) async {
    final controller = await pump(
      tester,
      text: 'سلام\nHello',
      selection: const TextSelection.collapsed(offset: 10),
    );

    insertThroughIme(tester, imeClientGetter(), ' دنیا');
    await tester.pumpAndSettle();

    expect(controller.text, 'سلام\nHello دنیا');
    expect(controller.selection, const TextSelection.collapsed(offset: 15));
    expect(directions(tester), [TextDirection.rtl, TextDirection.ltr]);
  });

  testWidgets('the newline the IME sends splits the paragraph, and the new '
      'line takes its own direction', (tester) async {
    final controller = await pump(
      tester,
      text: 'سلام',
      selection: const TextSelection.collapsed(offset: 4),
    );

    insertThroughIme(tester, imeClientGetter(), '\n');
    await tester.pumpAndSettle();
    expect(controller.text, 'سلام\n');
    expect(laidOut(tester), hasLength(2));

    insertThroughIme(tester, imeClientGetter(), 'Hello');
    await tester.pumpAndSettle();

    expect(controller.text, 'سلام\nHello');
    // The Persian line keeps its side; the English one takes the other, and
    // neither waits for the caret to move.
    expect(directions(tester), [TextDirection.rtl, TextDirection.ltr]);
    expect(alignments(tester), [TextAlign.right, TextAlign.left]);
  });

  testWidgets('backspace at the start of a paragraph joins it to the one '
      'above', (tester) async {
    final controller = await pump(
      tester,
      text: 'سلام\nHello',
      selection: const TextSelection.collapsed(offset: 5),
    );

    await press(tester, LogicalKeyboardKey.backspace);

    expect(controller.text, 'سلامHello');
    expect(controller.selection, const TextSelection.collapsed(offset: 4));
    // One paragraph now, and it is Persian: the joined line begins with one.
    expect(laidOut(tester), hasLength(1));
    expect(directions(tester).single, TextDirection.rtl);
  });

  testWidgets('a selection extended upwards keeps its anchor below its '
      'extent', (tester) async {
    final controller = await pump(
      tester,
      text: 'سلام\nHello',
      selection: const TextSelection.collapsed(offset: 10),
    );

    // The finger started at the bottom and moved up: base 10, extent 7.
    select(tester, base: 10, extent: 7);
    await tester.pumpAndSettle();

    // Reversed, exactly. Normalising these would send the next Shift+arrow to
    // the wrong end, and would put the editor's handles on the wrong ends.
    expect(controller.selection.baseOffset, 10);
    expect(controller.selection.extentOffset, 7);
    expect(controller.selection.isValid, isTrue);
  });

  testWidgets('moving the caret never changes a paragraph\'s direction', (
    tester,
  ) async {
    const note = 'سلام دنیا\nHello world\n۱۲۳ ۴۵۶\nنکس Nex را باز کن';
    await pump(
      tester,
      text: note,
      selection: const TextSelection.collapsed(offset: 0),
    );
    final before = directions(tester);
    final beforeAlign = alignments(tester);

    // Walk the caret over every paragraph, forwards and back — the movement
    // that used to turn the whole note.
    for (final offset in [3, 9, 12, 22, 30, 40, 30, 12, 4, 0]) {
      select(tester, base: offset, extent: offset);
      await tester.pumpAndSettle();
      expect(directions(tester), before, reason: 'caret at $offset');
      expect(alignments(tester), beforeAlign, reason: 'caret at $offset');
    }

    expect(before, [
      TextDirection.rtl,
      TextDirection.ltr,
      TextDirection.ltr,
      TextDirection.rtl,
    ]);
  });

  testWidgets('undo and redo reach the caret and the plain string', (
    tester,
  ) async {
    final controller = await pump(
      tester,
      text: 'سلام',
      selection: const TextSelection.collapsed(offset: 4),
    );

    insertThroughIme(tester, imeClientGetter(), 'د');
    await tester.pumpAndSettle();
    expect(controller.text, 'سلامد');
    expect(controller.selection, const TextSelection.collapsed(offset: 5));

    engine(tester).undo();
    await tester.pumpAndSettle();
    expect(controller.text, 'سلام');
    // The caret comes back with the text, so the next keystroke continues the
    // sentence it was in.
    expect(controller.selection, const TextSelection.collapsed(offset: 4));

    engine(tester).redo();
    await tester.pumpAndSettle();
    expect(controller.text, 'سلامد');
  });

  testWidgets('read-only has no input connection to type into', (tester) async {
    final controller = await pump(
      tester,
      text: 'متن ثابت\nFixed text',
      readOnly: true,
    );

    expect(find.byType(SuperReader), findsOneWidget);
    expect(find.byType(SuperEditor), findsNothing);
    // Nothing is listening: a key has nowhere to arrive, so the text that is
    // being shown cannot be edited while the AI rewrite works on it.
    expect(tester.testTextInput.isVisible, isFalse);
    await simulateKeyDownEvent(LogicalKeyboardKey.keyX, character: 'x');
    await simulateKeyUpEvent(LogicalKeyboardKey.keyX);
    await tester.pumpAndSettle();
    expect(controller.text, 'متن ثابت\nFixed text');
  });
}
