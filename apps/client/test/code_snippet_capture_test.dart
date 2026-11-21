import 'dart:async';

import 'package:flutter/material.dart';
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
import 'package:nex_client/widgets/nex_text_field.dart';
import 'package:nex_client/widgets/snippet_editor_sheet.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

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
    await tester.enterText(_field, _code);
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
    await tester.enterText(_field, '   سلام');
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

    await tester.tap(find.text(l10n.captureKindNote));
    await tester.pumpAndSettle();
    expect(tester.state<EditableTextState>(editable), same(editor));
    expect(editor.widget.focusNode.hasFocus, isTrue);
    expect(editor.widget.textDirection, TextDirection.rtl);
    expect(editor.widget.controller.text, '   سلام');

    await tester.tap(find.text(l10n.code));
    await tester.pumpAndSettle();
    expect(tester.state<EditableTextState>(editable), same(editor));
    expect(editor.widget.focusNode.hasFocus, isTrue);
    expect(editor.widget.textDirection, TextDirection.ltr);
  });

  testWidgets('the language button changes what is saved', (tester) async {
    await openComposer(tester);
    await tester.enterText(_field, 'println("hi")');
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

  testWidgets(
    'language hints and multiline indentation preserve the selection and draft',
    (tester) async {
      await openComposer(tester);
      const source = 'def draw():\n  return 1\n';
      await tester.enterText(_field, source);
      await tester.pumpAndSettle();
      final input = tester.widget<TextField>(_field).controller!;
      input.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: source.length,
      );
      await tester.tap(find.byKey(const ValueKey('code-language-suggestion')));
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(tester.element(_field));
      await tester.tap(find.byTooltip(l10n.codeIndent));
      await tester.pumpAndSettle();
      expect(input.text, '  def draw():\n    return 1\n');
      await tester.tap(find.byTooltip(l10n.codeOutdent));
      await tester.pumpAndSettle();
      expect(input.text, source);
      expect(input.selection.extentOffset, source.length);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final note = (await services.timeline(limit: 1)).single;
      expect(note.snippetPreview?.language, NexCodeLanguage.python);
      expect(note.copyText, source);
      final glyph = tester.widget<NexCodeLanguageGlyph>(
        find.byType(NexCodeLanguageGlyph).first,
      );
      expect(glyph.language, NexCodeLanguage.python);
    },
  );

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
      await tester.enterText(_field, 'a + b');
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
    await tester.enterText(_field, code);
    await tester.tap(find.byKey(const ValueKey('capture-code-language')));
    await tester.pumpAndSettle();
    expect(find.text('HTML'), findsOneWidget);
    expect(find.text('CSS'), findsOneWidget);
    await tester.tap(find.text('PHP'));
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
    expect(tester.widget<TextField>(editor).controller!.text, _code);

    const edited = '\tprint("سلام");   \n\n';
    await tester.enterText(editor, edited);
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
      expect(first.highlight, isFalse);
      await tester.pumpAndSettle();
      expect(tester.widget<NexCodeText>(source).highlight, isTrue);
    },
  );

  testWidgets(
    'editing HTML on the Android editor path shows syntax and preserves composing text',
    (tester) async {
      final native = NexTextField.native;
      NexTextField.native = true;
      addTearDown(() => NexTextField.native = native);
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
    },
  );

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
    'long source pages reassemble exactly and wrap independently of copying',
    (tester) async {
      tester.view.physicalSize = const Size(600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final code =
          '${'a' * 3999}😀\r\n${List.generate(55, (i) => '  line $i').join('\n')}';
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
      final source = find.byType(NexCodeText);
      final context = tester.element(source);
      await tester.tap(find.byTooltip(AppLocalizations.of(context).codeWrap));
      await tester.pumpAndSettle();
      expect(tester.widget<NexCodeText>(source).softWrap, isTrue);
      final nextLabel = MaterialLocalizations.of(tester.element(source))
          .nextPageTooltip;
      final next = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == nextLabel,
      );
      final pages = <String>[];
      while (true) {
        pages.add(tester.widget<NexCodeText>(source).code);
        if (tester.widget<IconButton>(next).onPressed == null) break;
        await tester.tap(next);
        await tester.pumpAndSettle();
      }
      expect(pages, hasLength(3));
      expect(pages.join(), code);
      expect(pages.first.length, 3999);
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
      final horizontal = find.ancestor(
        of: find.byType(NexCodeText),
        matching: find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
      );
      final scrollable = find
          .descendant(of: horizontal, matching: find.byType(Scrollable))
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(0));
      expect(position.axisDirection, AxisDirection.right);
      expect(position.pixels, 0);
      expect(tester.takeException(), isNull);
    }
  });
}
