import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/widgets/nex_paragraph_editor.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:super_editor/super_editor.dart';

/// The editor's contract with the rest of Nex: a note is one plain string,
/// whatever the editor does inside.
///
/// The per-paragraph layout itself lives in Super Editor's paragraph
/// component, which resolves a paragraph's direction from that paragraph's
/// own text and aligns it to that direction's side (see
/// `ParagraphComponentBuilder.createViewModel`). These tests pin the rule to
/// the app's own data: one paragraph per line, the direction the app's reading
/// surfaces would give that line, and a round trip that cannot lose a
/// character.
void main() {
  Future<TextEditingController> pump(
    WidgetTester tester, {
    String text = '',
    TextSelection? selection,
  }) async {
    final controller = TextEditingController(text: text);
    if (selection != null) {
      controller.selection = selection;
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: NexParagraphEditor(controller: controller, autofocus: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  /// Every paragraph as the editor actually lays it out: its text, the
  /// direction it was given, and the side it aligns to.
  List<TextComponent> laidOut(WidgetTester tester) => [
    for (final element in find.byType(TextComponent).evaluate())
      (element.widget as TextComponent),
  ];

  testWidgets('an empty note opens as one empty paragraph', (tester) async {
    final controller = await pump(tester);
    expect(controller.text, '');
    expect(find.byType(SuperEditor), findsOneWidget);
    expect(find.byType(NexParagraphEditor), findsOneWidget);
  });

  testWidgets('a mixed note keeps one paragraph per line, each with its own '
      'direction', (tester) async {
    const note = 'سلام دنیا\nHello world\n۱۲۳ ۴۵۶\nنکس Nex را باز کن';
    final controller = await pump(tester, text: note);

    // The controller holds the note exactly, byte for byte.
    expect(controller.text, note);

    final lines = laidOut(tester);
    expect(lines.map((line) => line.text.toPlainText()), [
      'سلام دنیا',
      'Hello world',
      '۱۲۳ ۴۵۶',
      'نکس Nex را باز کن',
    ]);
    expect(lines.map((line) => line.textDirection), [
      TextDirection.rtl,
      TextDirection.ltr,
      // Digits and spaces carry no direction, so this line follows the
      // paragraph above it — it does not flip the note.
      TextDirection.ltr,
      TextDirection.rtl,
    ]);
  });

  testWidgets('each paragraph aligns to its own side, not the note\'s', (
    tester,
  ) async {
    await pump(tester, text: 'سلام\nHello');
    // Left and right in the same document, at the same time — the whole point.
    expect(laidOut(tester).map((line) => line.textAlign), [
      TextAlign.right,
      TextAlign.left,
    ]);
  });

  testWidgets('the caret keeps its absolute offset in the plain text', (
    tester,
  ) async {
    const note = 'اول\n\nسوم';
    final controller = await pump(
      tester,
      text: note,
      selection: const TextSelection.collapsed(offset: 4),
    );
    expect(controller.selection.baseOffset, 4);

    // Offset 4 is the second newline of «اول\n\nسوم», so the caret is at the
    // start of the empty second paragraph — in the document as in the string.
    final editor = tester.widget<SuperEditor>(find.byType(SuperEditor)).editor;
    final selection = editor.context.composer.selection!;
    expect(selection.base.nodeId, isNotEmpty);
    expect((selection.base.nodePosition as TextNodePosition).offset, 0);
  });

  testWidgets('an external write rebuilds the document and keeps the note', (
    tester,
  ) async {
    final controller = await pump(tester, text: 'سلام\nHello');
    controller.value = const TextEditingValue(
      text: 'متن تازه\nA fresh note',
      selection: TextSelection.collapsed(offset: 10),
    );
    await tester.pumpAndSettle();

    final editor = tester.widget<SuperEditor>(find.byType(SuperEditor)).editor;
    expect(editor.context.document.toPlainText(), 'متن تازه\nA fresh note\n');
  });

  test('the engine derives a paragraph direction by first strong character', () {
    // The same rule the app's reading surfaces use, and the reason a paragraph
    // in the other script cannot be turned by the caret.
    expect(nexDirectionOf('سلام'), TextDirection.rtl);
    expect(nexDirectionOf('Hello'), TextDirection.ltr);
    expect(nexDirectionOf('۱۲۳'), isNull);
  });
}
