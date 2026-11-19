import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/app.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/widgets/capture_sheet.dart';
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

  testWidgets('a snippet reads LTR in a Persian detail sheet, in both themes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final note = (await services.captureText(
      NexCodeSnippet(
        code: '# کامنت فارسی\nprint("سلام");',
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
      expect(tester.takeException(), isNull);
    }
  });
}
