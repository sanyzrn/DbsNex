import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/widgets/nex_paragraph_editor.dart';
import 'package:nex_client/widgets/note_editor_sheet.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_editor/super_editor.dart';

/// Selection in the note editor.
///
/// The editor is one document with one paragraph per line, and its selection
/// is the document's: a range with a paragraph and an offset at each end. The
/// editor exposes that selection as the absolute offsets the rest of the app
/// speaks, and nothing about it depends on the caret or on a paragraph's
/// direction — so moving the caret cannot relayout the note under a finger.
void main() {
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await NexPreferences.load();
  });

  Future<void> open(WidgetTester tester, {required String initial}) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: nexLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  await NoteEditorSheet.show(
                    context,
                    initial: initial,
                    preferences: preferences,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  NexParagraphEditor editor(WidgetTester tester) =>
      tester.widget<NexParagraphEditor>(find.byType(NexParagraphEditor));

  Editor engine(WidgetTester tester) =>
      tester.widget<SuperEditor>(find.byType(SuperEditor)).editor;

  testWidgets('a selection through several paragraphs survives a rebuild', (
    tester,
  ) async {
    const text = 'یادداشت فارسی\nEnglish 123\nخط سوم';
    await open(tester, initial: text);
    final controller = editor(tester).controller;
    const selection = TextSelection(baseOffset: 2, extentOffset: 24);
    controller.value = const TextEditingValue(text: text, selection: selection);
    await tester.pumpAndSettle();

    expect(editor(tester).controller, same(controller));
    expect(controller.selection, selection);
    expect(selection.textInside(controller.text), text.substring(2, 24));

    // And the document holds the same range: start in the first paragraph,
    // end in the second — a selection that spans paragraphs, not a caret.
    final documentSelection = engine(tester).context.composer.selection!;
    expect(documentSelection.isCollapsed, isFalse);
    expect(
      documentSelection.base.nodeId,
      isNot(documentSelection.extent.nodeId),
    );
  });

  testWidgets('moving the caret changes nothing but the selection', (
    tester,
  ) async {
    await open(tester, initial: 'the boiler is making a noise');
    final before = editor(tester);
    final controller = before.controller;
    final text = controller.text;

    controller.selection = const TextSelection(baseOffset: 4, extentOffset: 10);
    await tester.pump();

    // No rebuild, and the text is untouched: a caret move is a caret move.
    expect(identical(before, editor(tester)), isTrue);
    expect(controller.text, text);
  });

  testWidgets('each paragraph keeps its own direction through a selection', (
    tester,
  ) async {
    const text = 'خط فارسی\nEnglish line\nخط سوم';
    await open(tester, initial: text);

    final directions = [
      for (final element in find.byType(ParagraphComponent).evaluate())
        (element.widget as ParagraphComponent).viewModel.textDirection,
    ];
    expect(directions, [
      TextDirection.rtl,
      TextDirection.ltr,
      TextDirection.rtl,
    ]);

    // Selecting across all three changes none of them: direction is a property
    // of each paragraph's own text, not of the selection.
    final controller = editor(tester).controller;
    controller.value = const TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: 1, extentOffset: 30),
    );
    await tester.pumpAndSettle();
    final after = [
      for (final element in find.byType(ParagraphComponent).evaluate())
        (element.widget as ParagraphComponent).viewModel.textDirection,
    ];
    expect(after, directions);
  });
}
