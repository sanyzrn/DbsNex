import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/capture_sheet.dart';
import 'package:nex_client/widgets/nex_dialog.dart';
import 'package:nex_client/widgets/note_editor_sheet.dart';
import 'package:nex_client/widgets/text_format_menu.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

void main() {
  late NexTestHarness harness;
  var windowDismissals = 0;
  String? saved;
  const host = MethodChannel('nex/os_capture');

  setUp(() async {
    harness = await NexTestHarness.create();
    windowDismissals = 0;
    saved = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(host, (call) async {
          if (call.method == 'hideKeyboard') windowDismissals++;
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(host, null);
    await harness.dispose();
  });

  Future<void> open(WidgetTester tester, {required bool capture}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: nexLightTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                if (capture) {
                  await nexShowSheet<void>(
                    context: context,
                    dismissible: false,
                    swipeToClose: true,
                    builder: (_) => CaptureSheet(
                      services: harness.services,
                      preferences: harness.preferences,
                      onCamera: () {},
                      onGallery: () {},
                      onFile: () {},
                    ),
                  );
                } else {
                  saved = await NoteEditorSheet.show(
                    context,
                    initial: 'one two three',
                    preferences: harness.preferences,
                  );
                }
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    if (capture) {
      await tester.enterText(find.byType(TextField), 'one two three');
      await tester.pumpAndSettle();
    }
  }

  Future<void> format(WidgetTester tester, String label) async {
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    state.userUpdateTextEditingValue(
      state.textEditingValue.copyWith(
        selection: const TextSelection(baseOffset: 4, extentOffset: 7),
      ),
      SelectionChangedCause.tap,
    );
    await tester.pump();
    final context = tester.element(find.byType(TextField));
    final menu =
        nexFormatContextMenuBuilder(context)(context, state)
            as AdaptiveTextSelectionToolbar;
    menu.buttonItems!.firstWhere((item) => item.label == label).onPressed!();
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester, {required bool capture}) async {
    if (capture) {
      await tester.tap(find.byKey(const ValueKey('capture-send')));
    } else {
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    }
    await tester.pumpAndSettle();
    expect(find.byType(CaptureSheet), findsNothing);
    expect(find.byType(NoteEditorSheet), findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(
      windowDismissals,
      greaterThan(0),
      reason: 'dismiss the activity IME even after a dialog owned the keyboard',
    );
    expect(tester.takeException(), isNull);
  }

  for (final capture in [false, true]) {
    final kind = capture ? 'capture' : 'edit';
    for (final label in [
      'Bold',
      'Italic',
      'Mono',
      'Strikethrough',
      'Quote',
      'Regular',
      'Link',
    ]) {
      testWidgets(
        '$kind: $label keeps editing, Save ends the keyboard session',
        (tester) async {
          await open(tester, capture: capture);
          await format(tester, label);
          if (label == 'Link') {
            final dialog = find.byType(AlertDialog);
            expect(dialog, findsOneWidget);
            await tester.enterText(
              find.descendant(of: dialog, matching: find.byType(TextField)),
              'https://example.com',
            );
            await tester.tap(
              find.descendant(of: dialog, matching: find.text('Save')),
            );
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
            final state = tester.state<EditableTextState>(
              find.byType(EditableText),
            );
            expect(state.widget.focusNode.hasFocus, isTrue);
            expect(
              state.textEditingValue.text,
              'one [two](https://example.com) three',
            );
          }
          expect(tester.testTextInput.isVisible, isTrue);
          await finish(tester, capture: capture);
          if (capture) {
            final note = (await harness.services.timeline(limit: 5)).single;
            expect(note.content, contains('two'));
          } else {
            expect(saved, contains('two'));
          }
        },
      );
    }

    testWidgets(
      '$kind: cancelling Link returns to the same text and still closes cleanly',
      (tester) async {
        await open(tester, capture: capture);
        await format(tester, 'Link');
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Cancel'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'one two three',
        );
        expect(tester.testTextInput.isVisible, isTrue);
        await finish(tester, capture: capture);
      },
    );
  }
  testWidgets('discard after inserting a link ends the editor and keyboard', (
    tester,
  ) async {
    await open(tester, capture: false);
    await format(tester, 'Link');
    final dialog = find.byType(AlertDialog);
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)),
      'https://example.com',
    );
    await tester.tap(find.descendant(of: dialog, matching: find.text('Save')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorSheet), findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(windowDismissals, greaterThan(0));
    expect(saved, isNull);
  });
}
