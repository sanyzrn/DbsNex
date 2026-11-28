import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/widgets/nex_paragraph_editor.dart';
import 'package:nex_client/widgets/note_editor_sheet.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:nex_ui/widgets/nex_selection_highlight.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor/super_editor_test.dart' show SuperEditorInspector;

import 'support/text_input.dart';

void main() {
  group('nexLevelSelectionRects', () {
    test('merges horizontally overlapping runs while preserving bidi gaps', () {
      final levelled = nexLevelSelectionRects(const [
        Rect.fromLTRB(10, 2, 60, 22),
        Rect.fromLTRB(55, 0, 110, 24),
        Rect.fromLTRB(140, 3, 200, 21),
      ]);

      expect(levelled, hasLength(2));
      expect(levelled[0], const Rect.fromLTRB(10, 0, 110, 24));
      expect(levelled[1], const Rect.fromLTRB(140, 0, 200, 24));
    });

    test('clamps vertical overlap between consecutive visual rows', () {
      final levelled = nexLevelSelectionRects(const [
        Rect.fromLTRB(0, 0, 120, 26),
        Rect.fromLTRB(0, 22, 120, 48),
      ]);

      expect(levelled, hasLength(2));
      expect(levelled[0].bottom, lessThanOrEqualTo(levelled[1].top));
      expect(levelled[0].bottom, closeTo(24.0, 0.001));
      expect(levelled[1].top, closeTo(24.0, 0.001));
    });
  });

  group('nexDirectionOf UAX #9 neutrals', () {
    test(
      'treats Arabic-Indic per mille/ten thousand and sajdah as neutral',
      () {
        expect(nexDirectionOf('\u0609 100'), isNull);
        expect(nexDirectionOf('\u060A 100'), isNull);
        expect(nexDirectionOf('\u06E9'), isNull);
        expect(nexDirectionOf('\u0609 Hello'), TextDirection.ltr);
      },
    );
  });

  group('NexParagraphEditor audit refinements', () {
    Future<TextEditingController> pumpEditor(
      WidgetTester tester, {
      required String text,
      TextSelection? selection,
      bool formatting = true,
      ThemeData? theme,
    }) async {
      final controller = TextEditingController(text: text);
      if (selection != null) controller.selection = selection;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme ?? nexDarkTheme(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 400,
              child: NexParagraphEditor(
                controller: controller,
                autofocus: true,
                formatting: formatting,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    testWidgets('uses themed caret, transparent SuperText selection, and '
        'minimal single-rule stylesheet', (tester) async {
      final theme = nexDarkTheme();
      await pumpEditor(tester, text: 'Hello\nWorld', theme: theme);

      final superEditor = tester.widget<SuperEditor>(find.byType(SuperEditor));
      expect(superEditor.selectionStyles.selectionColor, Colors.transparent);
      expect(superEditor.selectionStyles.highlightEmptyTextBlocks, isFalse);
      final context = tester.element(find.byType(SuperEditor));
      expect(
        SuperEditorAndroidControlsScope.rootOf(context).controlsColor,
        theme.colorScheme.primary,
      );
      expect(
        SuperEditorIosControlsScope.rootOf(context).handleColor,
        theme.colorScheme.primary,
      );
      expect(superEditor.stylesheet.rules, hasLength(1));

      final caretOverlay = superEditor.documentOverlayBuilders
          .whereType<DefaultCaretOverlayBuilder>()
          .single;
      expect(caretOverlay.caretStyle.color, theme.colorScheme.primary);
      expect(caretOverlay.displayCaretWithExpandedSelection, isFalse);
    });

    testWidgets('contextual selection menu integrates formatting and supports '
        'undo/redo', (tester) async {
      final controller = await pumpEditor(tester, text: 'one two three');
      await selectNexWord(tester, 5);
      final toolbar = find.byKey(DocumentKeys.mobileToolbar);
      expect(toolbar, findsOneWidget);
      for (final label in ['Cut', 'Copy', 'Paste', 'Select all']) {
        expect(
          find.descendant(of: toolbar, matching: find.text(label)),
          findsOneWidget,
        );
      }
      await tester.tap(find.byTooltip('Formatting'));
      await tester.pumpAndSettle();
      for (final label in [
        'Bold',
        'Italic',
        'Mono',
        'Strikethrough',
        'Quote',
        'Link',
        'Regular',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Bold'));
      await tester.pumpAndSettle();
      expect(controller.text, 'one **two** three');

      final engine = tester
          .widget<SuperEditor>(find.byType(SuperEditor))
          .editor;
      engine.undo();
      await tester.pumpAndSettle();
      expect(controller.text, 'one two three');
      expect(controller.selection.textInside(controller.text), 'two');
      expect(tester.testTextInput.isVisible, isTrue);

      engine.redo();
      await tester.pumpAndSettle();
      expect(controller.text, 'one **two** three');
    });

    testWidgets('cut across paragraphs makes one undoable edit', (
      tester,
    ) async {
      final controller = await pumpEditor(
        tester,
        text: 'سلام دنیا\nHello world',
        selection: const TextSelection(baseOffset: 5, extentOffset: 15),
      );
      String? copied;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(copied, 'دنیا\nHello');
      expect(controller.text, 'سلام  world');
      expect(controller.selection, const TextSelection.collapsed(offset: 5));
      tester.widget<SuperEditor>(find.byType(SuperEditor)).editor.undo();
      await tester.pumpAndSettle();
      expect(controller.text, 'سلام دنیا\nHello world');
    });

    testWidgets('paste replaces a mixed selection and undo restores it', (
      tester,
    ) async {
      const initial = 'سلام دنیا\nHello world';
      final controller = await pumpEditor(
        tester,
        text: initial,
        selection: const TextSelection(baseOffset: 15, extentOffset: 5),
      );
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          return {'text': 'Nex\nآزمایش'};
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(controller.text, 'سلام Nex\nآزمایش world');
      final editor = tester
          .widget<SuperEditor>(find.byType(SuperEditor))
          .editor;
      editor.undo();
      await tester.pumpAndSettle();
      expect(controller.text, initial);
      expect(editor.composer.selection, isNotNull);
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('cut leaves text intact when the selection moves mid-copy', (
      tester,
    ) async {
      final controller = await pumpEditor(tester, text: 'one two three');
      final copying = Completer<void>();
      String? copied;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String;
          await copying.future;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await selectNexWord(tester, 5);
      await tester.tap(find.text('Cut'));
      await tester.pump();
      controller.selection = const TextSelection(
        baseOffset: 8,
        extentOffset: 13,
      );
      copying.complete();
      await tester.pumpAndSettle();
      expect(copied, 'two');
      expect(controller.text, 'one two three');
    });

    testWidgets(
      'Android selection handles extend a Persian word into Latin text',
      (tester) async {
        final controller = await pumpEditor(
          tester,
          text: 'سلام دنیا\nHello world',
        );
        await selectNexWord(tester, 2);
        expect(controller.selection.textInside(controller.text), 'سلام');
        final editor = find.byType(SuperEditor);
        final layout = SuperEditorInspector.findDocumentLayout(editor);
        final document = tester.widget<SuperEditor>(editor).editor.document;
        final initial = layout.getRectForPosition(
          DocumentPosition(
            nodeId: document.first.id,
            nodePosition: const TextNodePosition(offset: 4),
          ),
        )!;
        final endpoint = layout.getRectForPosition(
          DocumentPosition(
            nodeId: document.last.id,
            nodePosition: const TextNodePosition(offset: 5),
          ),
        )!;
        final handle = SuperEditorInspector.findMobileExtentDragHandle(editor);
        final gesture = await tester.startGesture(tester.getCenter(handle));
        await gesture.moveBy(endpoint.center - initial.center);
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(controller.selection.start, 0);
        expect(controller.selection.end, greaterThan('سلام دنیا\n'.length));
        expect(controller.text, 'سلام دنیا\nHello world');
        expect(tester.testTextInput.isVisible, isTrue);
      },
    );

    testWidgets('Ctrl+B and Ctrl+I toggle markdown formatting when enabled', (
      tester,
    ) async {
      final controller = await pumpEditor(
        tester,
        text: 'hello world',
        selection: const TextSelection(baseOffset: 0, extentOffset: 5),
        formatting: true,
      );

      await simulateKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await simulateKeyDownEvent(LogicalKeyboardKey.keyB);
      await simulateKeyUpEvent(LogicalKeyboardKey.keyB);
      await simulateKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(controller.text, '**hello** world');

      await simulateKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await simulateKeyDownEvent(LogicalKeyboardKey.keyI);
      await simulateKeyUpEvent(LogicalKeyboardKey.keyI);
      await simulateKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(controller.text, '**_hello_** world');
    });
  });

  group('NoteEditorSheet UI/UX refinements', () {
    testWidgets('removes header A format icon, enables contextual formatting, '
        'and renders a distinct editor surface', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await NexPreferences.load();
      addTearDown(preferences.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: nexLightTheme(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: NoteEditorSheet(
              initial: 'Sample note text',
              preferences: preferences,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.text_format), findsNothing);

      final editor = tester.widget<NexParagraphEditor>(
        find.byType(NexParagraphEditor),
      );
      expect(editor.formatting, isTrue);

      final surface = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('note-editor-surface')),
      );
      final decoration = surface.decoration! as BoxDecoration;
      expect(decoration.color, isNotNull);
      expect(decoration.border, isNotNull);
    });
  });
}
