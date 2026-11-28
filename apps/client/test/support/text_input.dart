import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/widgets/nex_paragraph_editor.dart';
import 'package:nex_client/widgets/nex_text_field.dart';
import 'package:super_editor/src/test/ime.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor/super_editor_test.dart' show SuperEditorRobot;

/// Finds editable inputs in their screen order.
Finder nexInputs({String? hintText}) => find.byWidgetPredicate(
  (widget) => switch (widget) {
    TextField(:final decoration) =>
      hintText == null || decoration?.hintText == hintText,
    NexParagraphEditor(:final decoration) =>
      hintText == null || decoration.hintText == hintText,
    _ => false,
  },
);

TextEditingController nexInputController(WidgetTester tester, Finder field) =>
    switch (tester.widget(field)) {
      TextField(:final controller) => controller!,
      EditableText(:final controller) => controller,
      NexTextField(:final controller) => controller,
      NexParagraphEditor(:final controller) => controller,
      _ => throw ArgumentError('The finder must point to a text field'),
    };

Finder _editor(Finder root) => find.descendant(
  of: root,
  matching: find.byType(SuperEditor),
  matchRoot: true,
);

/// Invokes the touch gesture that opens the contextual toolbar.
Future<void> selectNexWord(WidgetTester tester, int offset) async {
  final finder = find.byType(SuperEditor);
  final node = tester.widget<SuperEditor>(finder).editor.document.first;
  await tester.doubleTapAtDocumentPosition(
    DocumentPosition(
      nodeId: node.id,
      nodePosition: TextNodePosition(offset: offset),
    ),
    finder,
  );
  await tester.pumpAndSettle();
}

Future<void> chooseNexFormat(WidgetTester tester, String command) async {
  await tester.tap(find.byTooltip('Formatting'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.ancestor(
      of: find.text(command),
      matching: find.byType(PopupMenuItem<ContextMenuButtonItem>),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> showNexKeyboard(WidgetTester tester, Finder field) async {
  final editor = _editor(field);
  if (editor.evaluate().isEmpty) {
    await tester.showKeyboard(field);
    return;
  }
  await tester.ensureVisible(field);
  tester.widget<SuperEditor>(editor).focusNode!.requestFocus();
  await tester.pump();
}

/// Replaces a field's value through its active Flutter input client.
Future<void> enterNexText(
  WidgetTester tester,
  Finder field,
  String text,
) async {
  final editor = _editor(field);
  if (editor.evaluate().isEmpty) {
    await tester.enterText(field, text);
    return;
  }
  await showNexKeyboard(tester, field);
  final owner = find.descendant(
    of: editor,
    matching: find.byType(SuperEditorImeInteractor),
  );
  final client = imeClientGetter(owner);
  final controller = nexInputController(
    tester,
    find.ancestor(of: editor, matching: find.byType(NexParagraphEditor)),
  );
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: controller.text.length,
  );
  await tester.pump();
  final current = client.currentTextEditingValue!;
  final start = current.selection.start;
  client.updateEditingValueWithDeltas([
    TextEditingDeltaReplacement(
      oldText: current.text,
      replacementText: text,
      replacedRange: current.selection,
      selection: TextSelection.collapsed(offset: start + text.length),
      composing: TextRange.empty,
    ),
  ]);
  await tester.idle();
}
