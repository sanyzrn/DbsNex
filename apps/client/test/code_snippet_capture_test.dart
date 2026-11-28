import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/app.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/widgets/capture_sheet.dart';
import 'package:nex_client/widgets/code_editing_controller.dart';
import 'package:nex_client/widgets/nex_dialog.dart';
import 'package:nex_client/widgets/snippet_editor_sheet.dart';
import 'package:nex_client/widgets/code_input.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';
import 'support/text_input.dart';

import 'package:super_editor/super_editor.dart';

const _code =
    '\tif (ok) {\n\n  print("two  spaces");   \n}\n\n```inner\nx\n```\n';

final _field = find.descendant(
  of: find.byType(CaptureSheet),
  matching: find.byType(TextField),
);

void main() {
  late NexTestHarness harness;
  late NexServices services;
  late NexPreferences preferences;

  test(
    'code input indents and pairs typed characters without altering a paste',
    () {
      const formatter = NexCodeInputFormatter();
      const old = TextEditingValue(
        text: '  print',
        selection: TextSelection.collapsed(offset: 7),
      );
      const newline = TextEditingValue(
        text: '  print\n',
        selection: TextSelection.collapsed(offset: 8),
      );
      final indented = formatter.formatEditUpdate(old, newline);
      expect(indented.text, '  print\n  ');
      expect(indented.selection.extentOffset, 10);

      const insertion = TextEditingValue(
        text: '  print(',
        selection: TextSelection.collapsed(offset: 8),
      );
      final paired = formatter.formatEditUpdate(old, insertion);
      expect(paired.text, '  print()');
      expect(paired.selection.extentOffset, 8);

      const pasted = TextEditingValue(
        text: '  print(\narg)',
        selection: TextSelection.collapsed(offset: 13),
      );
      expect(formatter.formatEditUpdate(old, pasted), pasted);
    },
  );

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_code_snippet_');
    services = harness.services;
    preferences = harness.preferences;
  });

  tearDown(() => harness.dispose());

  test('the capture option is «کد» in Persian', () {
    final fa = lookupAppLocalizations(const Locale('fa'));
    expect(fa.code, 'کد');
  });

  Future<void> openComposer(WidgetTester tester) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(CaptureSheet)));
    await tester.tap(find.text(l10n.code));
    await tester.pumpAndSettle();
  }

  Future<void> chooseLanguage(
    WidgetTester tester,
    String label, {
    Key key = const ValueKey('capture-code-language'),
  }) async {
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('code captured with a language reopens as the same snippet', (
    tester,
  ) async {
    await openComposer(tester);
    await enterNexText(tester, _field, _code);
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(CaptureSheet)));
    await chooseLanguage(tester, l10n.codeLanguageDart);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    final notes = await services.timeline(limit: 5);
    expect(notes, hasLength(1));
    final note = notes.single;
    final expected = NexCodeSnippet(
      code: _code,
      language: NexCodeLanguage.dart,
    );
    expect(note.type, NoteType.text);
    expect(note.content, expected.markdown);
    // The wrapper and the language are storage; the clipboard is the code.
    expect(note.copyText, _code);
    expect(NexCodeSnippet.parse(note.content!)!.code, _code);
  });

  testWidgets('switching between Code and Note keeps text and keyboard focus', (
    tester,
  ) async {
    await openComposer(tester);
    await enterNexText(tester, _field, '   سلام');
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(CaptureSheet)));
    final editable = find.descendant(
      of: find.byType(CaptureSheet),
      matching: find.byType(EditableText),
    );
    final editor = tester.state<EditableTextState>(editable);
    expect(editor.widget.focusNode.hasFocus, isTrue);
    expect(editor.widget.textDirection, TextDirection.ltr);
    expect(
      tester.widget<TextField>(_field).textInputAction,
      TextInputAction.newline,
    );

    final focus = editor.widget.focusNode;
    final controller = editor.widget.controller;
    final selection = controller.selection;
    tester.testTextInput.log.clear();
    await tester.tap(find.text(l10n.captureKindNote));
    await tester.pumpAndSettle();
    final paragraph = tester.widget<ParagraphComponent>(
      find.byType(ParagraphComponent),
    );
    expect(paragraph.viewModel.textDirection, TextDirection.rtl);
    expect(focus.hasFocus, isTrue);
    expect(controller.text, '   سلام');
    expect(controller.selection, selection);

    await tester.tap(find.text(l10n.code));
    await tester.pumpAndSettle();
    final code = tester.state<EditableTextState>(editable).widget;
    expect(code.focusNode, same(focus));
    expect(code.focusNode.hasFocus, isTrue);
    expect(code.textDirection, TextDirection.ltr);
    expect(
      tester.testTextInput.log.map((call) => call.method),
      isNot(contains('TextInput.hide')),
    );
  });

  testWidgets('the language button changes what is saved', (tester) async {
    await openComposer(tester);
    await enterNexText(tester, _field, 'println("hi")');
    final l10n = AppLocalizations.of(tester.element(find.byType(CaptureSheet)));
    await chooseLanguage(tester, l10n.codeLanguagePython);
    // Changing the language is itself a note change: it must reach the note
    // without another keystroke.
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    final note = (await services.timeline(limit: 5)).single;
    expect(note.content, '```python\nprintln("hi")\n```');
  });

  testWidgets('capture puts Code last and detects the pasted language', (
    tester,
  ) async {
    await preferences.setLocale('en');
    await openComposer(tester);
    const source = 'def draw():\n  return 1\n';
    await enterNexText(tester, _field, source);
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(_field));
    final modeCenters =
        [l10n.captureKindNote, l10n.checklist, l10n.link, l10n.code].map((
          label,
        ) {
          final chip = find.descendant(
            of: find.byType(CaptureSheet),
            matching: find.text(label),
          );
          return tester.getCenter(chip).dx;
        }).toList();
    expect(modeCenters, orderedEquals([...modeCenters]..sort()));
    expect(find.byTooltip(l10n.codeIndent), findsOneWidget);
    expect(find.byTooltip(l10n.codeOutdent), findsOneWidget);
    expect(find.text(l10n.codeLanguagePython), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final note = (await services.timeline(limit: 1)).single;
    expect(note.snippetPreview?.language, NexCodeLanguage.python);
    expect(note.copyText, source);
    final glyph = tester.widget<NexCodeLanguageGlyph>(
      find.byType(NexCodeLanguageGlyph).first,
    );
    expect(glyph.language, NexCodeLanguage.python);
  });

  testWidgets(
    'the Persian language palette fits above a phone keyboard and returns to the same caret',
    (tester) async {
      await preferences.setLocale('fa');
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 780);
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openComposer(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await enterNexText(tester, _field, 'a + b');
      final input = tester.widget<TextField>(_field).controller!;
      input.selection = const TextSelection.collapsed(offset: 2);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('capture-code-language')));
      await tester.pumpAndSettle();
      expect(
        find.byType(ChoiceChip),
        findsNWidgets(NexCodeLanguage.selectable.length),
      );
      final php = find.widgetWithText(ChoiceChip, 'PHP');
      await tester.ensureVisible(php);
      await tester.tap(php);
      await tester.pumpAndSettle();
      expect(input.selection.extentOffset, 2);
      expect(input.text, 'a + b');
      expect(tester.widget<TextField>(_field).focusNode!.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the web languages are selectable and the PHP source is kept', (
    tester,
  ) async {
    await openComposer(tester);
    const code = r'<?php echo $name;';
    await enterNexText(tester, _field, code);
    await tester.tap(find.byKey(const ValueKey('capture-code-language')));
    await tester.pumpAndSettle();
    expect(find.text('HTML'), findsOneWidget);
    expect(find.text('CSS'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'PHP'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    final note = (await services.timeline(limit: 5)).single;
    expect(note.content, '```php\n$code\n```');
    expect(note.copyText, code);
  });

  testWidgets('the detail sheet copies, shows and edits the code exactly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final snippet = NexCodeSnippet(code: _code, language: NexCodeLanguage.dart);
    final note = (await services.captureText(snippet.markdown))!;
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NoteDetailSheet(
            services: services,
            preferences: preferences,
            noteId: note.id,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NoteDetailSheet)),
    );

    expect(find.byType(NexCodeText), findsOneWidget);
    expect(find.text(l10n.copyCode), findsOneWidget);
    expect(find.text(l10n.codeLanguageDart), findsOneWidget);

    await tester.tap(find.text(l10n.copyCode));
    await tester.pumpAndSettle();
    expect(copied, [_code]);

    await tester.tap(find.text(l10n.edit));
    await tester.pumpAndSettle();
    expect(find.byType(NexSnippetEditorSheet), findsOneWidget);
    final editor = find.descendant(
      of: find.byType(NexSnippetEditorSheet),
      matching: find.byType(TextField),
    );
    final controller = tester.widget<TextField>(editor).controller!;
    expect(controller.text, _code);
    controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: _code.length,
    );
    await tester.tap(find.byTooltip(l10n.codeIndent));
    await tester.pumpAndSettle();
    expect(controller.text, startsWith('  \tif (ok) {'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(l10n.unsavedChanges), findsOneWidget);
    await tester.tap(find.text(l10n.keepEditing));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.codeOutdent));
    await tester.pumpAndSettle();
    expect(controller.text, _code);
    expect(controller.selection.extentOffset, _code.length);

    const edited = '\tprint("سلام");   \n\n';
    await enterNexText(tester, editor, edited);
    await chooseLanguage(
      tester,
      l10n.codeLanguagePython,
      key: const ValueKey('snippet-code-language'),
    );
    await tester.tap(find.text(l10n.save));
    await tester.pumpAndSettle();

    final saved = (await services.getById(note.id))!;
    expect(
      saved.content,
      NexCodeSnippet(code: edited, language: NexCodeLanguage.python).markdown,
    );

    await tester.tap(find.byTooltip(l10n.codeFind));
    await tester.pumpAndSettle();
    await enterNexText(tester, nexInputs(), 'سلام');
    await tester.pumpAndSettle();
    expect(find.textContaining('print("سلام")'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // Change only the language while the same detail sheet is open.
    expect(
      tester.widget<NexCodeText>(find.byType(NexCodeText)).spans,
      isNotNull,
    );
    await tester.tap(find.text(l10n.edit));
    await tester.pumpAndSettle();
    await chooseLanguage(
      tester,
      l10n.codeLanguagePlainText,
      key: const ValueKey('snippet-code-language'),
    );
    await tester.tap(find.text(l10n.save));
    await tester.pumpAndSettle();
    final plain = tester.widget<NexCodeText>(find.byType(NexCodeText));
    expect(plain.code, edited);
    expect(plain.language, NexCodeLanguage.plainText);
    expect(plain.spans, isNull);
  });

  testWidgets(
    'HTML opens with source and colours it after the sheet animation',
    (tester) async {
      const code = '<p class="note">سلام</p>';
      final note = (await services.captureText(
        const NexCodeSnippet(
          code: code,
          language: NexCodeLanguage.html,
        ).markdown,
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => nexShowSheet<void>(
                  context: context,
                  builder: (_) => NoteDetailSheet(
                    services: services,
                    noteId: note.id,
                    initialNote: note,
                    preferences: preferences,
                  ),
                ),
                child: const Text('Open snippet'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open snippet'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final source = find.byType(NexCodeText);
      final first = tester.widget<NexCodeText>(source);
      expect(first.code, code);
      // Readable from the first frame; coloured once the sheet has opened.
      expect(first.spans, isNull);
      await tester.pumpAndSettle();
      final coloured = tester.widget<NexCodeText>(source).spans;
      expect(coloured, isNotNull);
      expect(coloured!.map((span) => span.text).join(), code);
      expect(coloured.any((span) => span.style?.color != null), isTrue);
    },
  );

  testWidgets('a comment that runs past a chunk boundary keeps its colour', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 48 lines end inside the comment: the chunk after the cut starts with
    // its middle, with no `/*` of its own.
    final code =
        '${List.generate(46, (i) => 'final v$i = $i;').join('\n')}\n'
        '/* start\n * middle\n * end */\nfinal done = true;\n'
        '${'// filler to exercise background highlighting\n' * 350}';
    final note = (await services.captureText(
      NexCodeSnippet(code: code, language: NexCodeLanguage.dart).markdown,
    ))!;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NoteDetailSheet(
            services: services,
            preferences: preferences,
            noteId: note.id,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('snippet-expand')));
    await tester.pumpAndSettle();
    Finder chunkContaining(String text) => find.byWidgetPredicate(
      (widget) => widget is NexCodeText && widget.code.contains(text),
    );
    final scrollable = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      chunkContaining(' * end */'),
      600,
      scrollable: scrollable,
    );
    final visibleChunk = chunkContaining(' * end */');
    final deadline = Stopwatch()..start();
    while (tester.widget<NexCodeText>(visibleChunk).spans == null &&
        deadline.elapsed < const Duration(seconds: 10)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    final chunk = tester.widget<NexCodeText>(visibleChunk);
    expect(chunk.spans, isNotNull);
    expect(
      chunk.spans!.any((span) => span.style?.fontStyle == FontStyle.italic),
      isTrue,
      reason: 'the middle of a block comment is still a comment',
    );
    expect(chunk.spans!.map((span) => span.text).join(), chunk.code);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing HTML shows syntax and preserves composing text', (
    tester,
  ) async {
    const source = '<p class="note">سلام</p>';
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NexSnippetEditorSheet(
            initial: const NexCodeSnippet(
              code: source,
              language: NexCodeLanguage.html,
            ),
            preferences: preferences,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final editable = find.byType(EditableText);
    final controller = tester.widget<EditableText>(editable).controller;
    controller.value = const TextEditingValue(
      text: source,
      selection: TextSelection.collapsed(offset: 21),
      composing: TextRange(start: 16, end: 20),
    );
    await tester.pump();
    final span = controller.buildTextSpan(
      context: tester.element(editable),
      style: const TextStyle(),
      withComposing: true,
    );
    final children = span.children!.whereType<TextSpan>().toList();
    expect(span.toPlainText(), source);
    expect(children.first.style?.color, isNotNull);
    expect(children.first.style?.color, isNot(children[2].style?.color));
    expect(
      children.any(
        (piece) => piece.style?.decoration == TextDecoration.underline,
      ),
      isTrue,
    );
    expect(controller.selection.baseOffset, 21);
  });

  testWidgets('large HTML is coloured off the UI isolate', (tester) async {
    final source = '<p class="note">سلام</p>\n' * 200;
    final controller = NexCodeEditingController(
      text: source,
      language: NexCodeLanguage.html,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox).last);
    await tester.runAsync(() async {
      final updated = Completer<void>();
      controller.addListener(() => updated.complete());
      final plain = controller.buildTextSpan(
        context: context,
        withComposing: false,
      );
      expect(plain.text, source);
      await updated.future.timeout(const Duration(seconds: 10));
      final coloured = controller.buildTextSpan(
        context: context,
        withComposing: false,
      );
      expect(coloured.children!.first.style?.color, isNotNull);
      expect(coloured.toPlainText(), source);
    });
  });

  testWidgets(
    'long source wraps and scrolls continuously with bounded rendering',
    (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final code =
          '${'a' * 3999}😀\r\n${List.generate(480, (i) => '  line $i').join('\n')}';
      final note = (await services.captureText(
        NexCodeSnippet(code: code).markdown,
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: NoteDetailSheet(
              services: services,
              preferences: preferences,
              noteId: note.id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final more = find.byKey(const ValueKey('snippet-expand'));
      final preview = tester.widget<NexCodeText>(find.byType(NexCodeText));
      expect(preview.code.length, lessThan(500));
      expect(preview.maxLines, 8);
      await tester.tap(more);
      await tester.pumpAndSettle();
      final source = find.byType(NexCodeText);
      final context = tester.element(source.first);
      final nav = MaterialLocalizations.of(context);
      expect(find.byTooltip(nav.nextPageTooltip), findsNothing);
      expect(find.byTooltip(nav.previousPageTooltip), findsNothing);
      expect(
        find.byTooltip(AppLocalizations.of(context).codeWrap),
        findsOneWidget,
      );
      final wrap = find.byTooltip(AppLocalizations.of(context).codeWrap);
      await tester.tap(wrap);
      await tester.pumpAndSettle();
      expect(tester.widget<NexCodeText>(source.first).softWrap, isFalse);
      await tester.tap(wrap);
      await tester.pumpAndSettle();
      final first = tester.widget<NexCodeText>(source.first);
      expect(first.code, 'a' * 3999);
      expect(first.softWrap, isTrue);
      expect(tester.getSize(source.first).height, greaterThan(200));
      expect(source.evaluate().length, lessThan(5));
      final scrollable = find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first;
      Finder codeContaining(String text) => find.byWidgetPredicate(
        (widget) => widget is NexCodeText && widget.code.contains(text),
      );
      await tester.scrollUntilVisible(
        codeContaining('😀'),
        480,
        scrollable: scrollable,
      );
      expect(
        tester.widget<NexCodeText>(codeContaining('😀')).code,
        startsWith('😀\r\n'),
      );
      await tester.scrollUntilVisible(
        codeContaining('  line 479'),
        520,
        scrollable: scrollable,
      );
      expect(codeContaining('  line 479'), findsOneWidget);
      expect(codeContaining('a' * 3999), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Find in code takes the reader to the chosen line, folded or not',
    (tester) async {
      tester.view.physicalSize = const Size(360, 660);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final code = [
        for (var i = 1; i <= 400; i++)
          if (i == 335)
            '${'prefix ' * 80}the needle line'
          else if (i >= 290 && i < 335)
            'line $i ${'wrapped words ' * 6}'
          else
            'line $i of many',
      ].join('\n');
      final note = (await services.captureText(
        NexCodeSnippet(code: code).markdown,
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: NoteDetailSheet(
              services: services,
              preferences: preferences,
              noteId: note.id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(NoteDetailSheet)),
      );
      final needle = find.textContaining('the needle line');

      // Folded to a preview: the deep line is not reachable by scrolling
      // the sheet as it opens.
      expect(find.byKey(const ValueKey('snippet-expand')), findsOneWidget);

      final reader = find.byType(CustomScrollView);
      Future<void> findAndCheck() async {
        await tester.tap(find.byTooltip(l10n.codeFind));
        await tester.pumpAndSettle();
        final search = find.byType(NexSearchField);
        final result = find.ancestor(
          of: needle,
          matching: find.byType(ListTile),
        );
        await enterNexText(tester, search, 'needle');
        await tester.pump(const Duration(milliseconds: 140));
        await tester.pumpAndSettle();
        expect(result, findsOneWidget);
        await enterNexText(tester, search, 'absent');
        await tester.pump(const Duration(milliseconds: 100));
        expect(result, findsNothing);
        expect(find.text(l10n.codeNoMatches), findsNothing);
        await enterNexText(tester, search, 'needle');
        await tester.pump(const Duration(milliseconds: 140));
        await tester.pumpAndSettle();
        // Choosing the excerpt itself must work, not just the gutter.
        await tester.tap(needle);
        for (var i = 0; i < 36; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pumpAndSettle();

        expect(find.byType(NexSearchField), findsNothing);
        final paragraph = tester.renderObject<RenderParagraph>(needle);
        final start = paragraph.text.toPlainText().indexOf('the needle line');
        final box = paragraph
            .getBoxesForSelection(
              TextSelection(baseOffset: start, extentOffset: start + 15),
            )
            .first
            .toRect();
        final point = paragraph.localToGlobal(box.center);
        final viewport = tester.getRect(reader);
        expect(
          viewport.contains(point),
          isTrue,
          reason: 'the matching text is visible at $point within $viewport',
        );
      }

      await findAndCheck();
      tester.widget<CustomScrollView>(reader).controller!.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l10n.codeWrap));
      await tester.tap(find.byTooltip(l10n.codeLineNumbers));
      await tester.pumpAndSettle();
      await findAndCheck();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'line numbers number every line of a snippet, and only while asked',
    (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const code = 'first\nsecond\nthird';
      final note = (await services.captureText(
        NexCodeSnippet(code: code, language: NexCodeLanguage.dart).markdown,
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: NoteDetailSheet(
              services: services,
              preferences: preferences,
              noteId: note.id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(NoteDetailSheet)),
      );
      Finder gutters() => find.byWidgetPredicate(
        (w) => w is Text && RegExp(r'^\s+\d+$').hasMatch(w.data ?? ''),
      );
      expect(gutters(), findsNothing);

      final numbers = find.byTooltip(l10n.codeLineNumbers);
      expect(numbers, findsOneWidget);
      await tester.tap(numbers);
      await tester.pumpAndSettle();

      // One gutter per line, counting the code's own lines.
      final labels = [
        for (final element in gutters().evaluate())
          (element.widget as Text).data!,
      ];
      expect(labels, ['  1', '  2', '  3']);
      // Numbering splits the code by line: each line keeps its own words.
      for (final line in ['first', 'second', 'third']) {
        expect(
          find.byWidgetPredicate((w) => w is NexCodeText && w.code == line),
          findsOneWidget,
        );
      }

      await tester.tap(numbers);
      await tester.pumpAndSettle();
      expect(gutters(), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a snippet reads LTR in a Persian detail sheet, in both themes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final note = (await services.captureText(
      NexCodeSnippet(
        code: '# کامنت فارسی\nprint("سلام"); // ${'x' * 300}',
        language: NexCodeLanguage.python,
      ).markdown,
    ))!;

    for (final theme in [nexSoftLightTheme(), nexSoftDarkTheme()]) {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fa'),
          theme: theme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: NoteDetailSheet(
              services: services,
              preferences: preferences,
              noteId: note.id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rich = tester.widget<RichText>(
        find
            .descendant(
              of: find.byType(NexCodeText),
              matching: find.byType(RichText),
            )
            .first,
      );
      expect(rich.textDirection, TextDirection.ltr);
      expect(rich.text.toPlainText(), contains('# کامنت فارسی'));
      final source = tester.widget<NexCodeText>(find.byType(NexCodeText));
      expect(source.softWrap, isTrue);
      expect(rich.text.toPlainText(), contains('x' * 300));
      expect(tester.takeException(), isNull);
    }
  });
}
