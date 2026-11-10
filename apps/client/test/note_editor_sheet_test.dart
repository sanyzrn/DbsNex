import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/platform/editor_drafts.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/widgets/note_editor_sheet.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The editor is where somebody's own words are, and a model is now allowed
/// to change them. Two things follow from that and are what this file holds:
/// nothing is saved until Save, and everything the model does can be undone.
void main() {
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await NexPreferences.load();
  });

  /// A provider that answers every request with the same text.
  http.Client replying(String content) => MockClient(
    (_) async => http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'choices': [
            {
              'message': {'content': content},
            },
          ],
        }),
      ),
      200,
      headers: const {'content-type': 'application/json'},
    ),
  );

  Future<void> enableAi() async {
    await preferences.setAiEnabled(true);
    await preferences.setAiProvider(
      const AiProviderConfig(provider: AiProvider.openai, apiKey: 'k'),
    );
  }

  /// Opens the editor the way the detail sheet does, and hands back a getter
  /// for what it resolves to.
  Future<String? Function()> open(
    WidgetTester tester, {
    required String initial,
    http.Client? client,
    String? draftKey,
    int? initialSelection,
  }) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    String? result;
    var done = false;
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
                  result = await NoteEditorSheet.show(
                    context,
                    initial: initial,
                    preferences: preferences,
                    draftKey: draftKey,
                    initialSelection: initialSelection,
                    client: client == null
                        ? null
                        : () => CloudAIAdapter(
                            config: preferences.aiProvider,
                            client: client,
                          ),
                  );
                  done = true;
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
    return () => done ? result : null;
  }

  testWidgets('AI undo stays reachable after the editor height shrinks', (
    tester,
  ) async {
    await enableAi();
    await open(tester, initial: 'teh draft', client: replying('the draft'));
    await tester.tap(find.byTooltip('Edit with AI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fix writing'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(900, 320);
    await tester.pumpAndSettle();
    final undo = find.byTooltip('Undo').hitTestable();
    expect(undo, findsOneWidget);
    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'teh draft',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('it opens as a sheet on the text it was given', (tester) async {
    await open(tester, initial: 'the boiler is making a noise');

    expect(find.text('Edit note'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'the boiler is making a noise',
    );
  });

  testWidgets('the shared note and caption editor opens the caret at the end', (
    tester,
  ) async {
    await open(tester, initial: 'the boiler is making a noise');
    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.baseOffset, controller.text.length);
  });

  testWidgets('a caller can place the caret where its flow needs it', (
    tester,
  ) async {
    await open(tester, initial: 'call the landlord', initialSelection: 5);
    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    expect(controller.selection.baseOffset, 5);
  });

  testWidgets('a recovered draft opens with the caret at its end', (
    tester,
  ) async {
    // testWidgets uses a fake-async clock: awaiting an actual filesystem
    // future here can hang until the ten-minute test timeout.
    final dir = Directory.systemTemp.createTempSync('nex_editor_draft_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final drafts = EditorDrafts(dir.path);
    preferences.editorDrafts = drafts;
    drafts.write('note-7', {'text': 'half-finished thou'});
    // This test verifies draft restoration itself, without adding an
    // unrelated modal-route settle to the synchronous recovery assertion.
    await tester.pumpWidget(
      MaterialApp(
        theme: nexLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NoteEditorSheet(
            initial: 'original words',
            preferences: preferences,
            draftKey: 'note-7',
          ),
        ),
      ),
    );
    await tester.pump();
    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    expect(controller.text, 'half-finished thou');
    // Composition half-finished: the caret waits after the last word typed.
    expect(controller.selection.baseOffset, 'half-finished thou'.length);
  });

  testWidgets('the AI row is absent when there is no model to ask', (
    tester,
  ) async {
    // Not disabled: an app with AI switched off has no business showing six
    // buttons that cannot work.
    await open(tester, initial: 'a note');
    expect(find.text('Edit with AI'), findsNothing);
    expect(find.text('Auto style'), findsNothing);
  });

  testWidgets('turning AI on puts the edits on the sheet', (tester) async {
    await enableAi();
    await open(tester, initial: 'a note');

    expect(find.text('Edit with AI'), findsOneWidget);
    expect(find.text('Auto style'), findsOneWidget);
    expect(find.text('Fix writing'), findsOneWidget);
  });

  testWidgets('an edit replaces the text, and Undo puts it back', (
    tester,
  ) async {
    await enableAi();
    const before = 'boiler noise. call landlord';
    await open(
      tester,
      initial: before,
      client: replying('## Boiler\n\n**Call the landlord.**'),
    );

    await tester.tap(find.text('Auto style'));
    await tester.pumpAndSettle();

    String text() =>
        tester.widget<TextField>(find.byType(TextField)).controller!.text;
    expect(text(), '## Boiler\n\n**Call the landlord.**');

    // The way back. Nothing is saved yet, so an edit that made the note worse
    // costs one tap rather than re-typing what was there.
    expect(find.text('Edited by AI'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(text(), before);
    expect(find.text('Edited by AI'), findsNothing);
  });

  testWidgets('oversized AI edits keep the draft and explain the limit', (
    tester,
  ) async {
    await enableAi();
    final before = 'A long note. ' * 1000;
    var calls = 0;
    await open(
      tester,
      initial: before,
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    // Longer notes open expanded, with AI actions behind their own toggle.
    await tester.tap(find.byTooltip('Edit with AI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auto style'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      before,
    );
    expect(find.textContaining('too long to edit'), findsOneWidget);
    expect(find.text('Edited by AI'), findsNothing);
  });

  testWidgets('a rewrite that comes back empty leaves the note alone', (
    tester,
  ) async {
    await enableAi();
    await open(
      tester,
      initial: 'a note worth keeping',
      client: MockClient((_) async => http.Response('nope', 500)),
    );

    await tester.ensureVisible(find.text('Shorter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shorter'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'a note worth keeping',
    );
    expect(find.text('Edited by AI'), findsNothing);
  });

  testWidgets('nothing is saved until Save, and Cancel saves nothing', (
    tester,
  ) async {
    final result = await open(tester, initial: 'first');
    await tester.enterText(find.byType(TextField), 'second');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    final confirmation = tester.element(find.text('Discard unsaved changes?'));
    expect(ModalRoute.of(confirmation)!.barrierColor, Colors.black54);
    final frame =
        Theme.of(confirmation).dialogTheme.shape! as RoundedRectangleBorder;
    expect(frame.side.style, BorderStyle.solid);
    expect(
      nexContrastRatio(
        frame.side.color,
        Theme.of(confirmation).dialogTheme.backgroundColor!,
      ),
      greaterThanOrEqualTo(3),
    );
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'second',
    );
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorSheet), findsNothing);
    expect(result(), isNull);
  });

  testWidgets('Save hands back what is in the field', (tester) async {
    final result = await open(tester, initial: 'first');
    await tester.enterText(find.byType(TextField), 'second');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    expect(result(), 'second');
  });

  testWidgets('an empty note cannot be saved over itself', (tester) async {
    // Emptying the field is not an edit — it is a note being deleted through
    // a route that does not delete notes.
    await open(tester, initial: 'something');
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<IconButton>(
            find
                .ancestor(
                  of: find.byTooltip('Save'),
                  matching: find.byType(IconButton),
                )
                .first,
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('full screen is the same editor with more room', (tester) async {
    await enableAi();
    await open(tester, initial: 'a long note');

    final small = tester.getSize(find.byType(TextField)).height;
    await tester.tap(find.byTooltip('Full screen'));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(TextField)).height,
      greaterThan(small),
      reason: 'the point of the button',
    );
    // Still one editor, and still holding the same text: expanding is a size,
    // not a second screen with a second copy of the note in it.
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'a long note',
    );
    expect(find.byTooltip('Smaller'), findsOneWidget);
  });

  testWidgets('with the keyboard up, full screen gives the note the room', (
    tester,
  ) async {
    // The bug this replaces: full screen was the sheet stretched, with its
    // title, chips and buttons still in it, and with the keyboard up the
    // text got the same strip in both sizes.
    await enableAi();
    await open(tester, initial: 'a long note');
    tester.view.viewInsets = const FakeViewPadding(bottom: 800);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    final small = tester.getSize(find.byType(TextField)).height;
    await tester.tap(find.byTooltip('Full screen'));
    await tester.pumpAndSettle();
    final full = tester.getSize(find.byType(TextField)).height;

    expect(full, greaterThan(small * 2));
    // The chrome is icons, not a second copy of the sheet's.
    expect(find.text('Edit note'), findsNothing);
    expect(find.text('Fix writing'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('full screen keeps every action: AI edits, undo and Save', (
    tester,
  ) async {
    await enableAi();
    final result = await open(
      tester,
      initial: 'teh draft',
      client: replying('the draft'),
    );
    await tester.tap(find.byTooltip('Full screen'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit with AI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fix writing'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'the draft',
    );

    // The undo is the same bar in either size now, not a header icon that
    // only the full screen had.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'teh draft',
    );

    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(result(), 'teh draft');
  });

  testWidgets('a long note opens owning the screen outright', (tester) async {
    // A tall note used to open in the 220px box: already scrolling, most of
    // itself out of view, Save below the fold. More than about eight lines
    // and the editor starts full screen — and can still be shrunk.
    final long = List.generate(
      12,
      (i) => 'line $i of a note that grew',
    ).join('\n');
    await open(tester, initial: long);

    expect(find.byTooltip('Smaller'), findsOneWidget);
    final field = tester.getSize(find.byType(TextField)).height;

    await tester.tap(find.byTooltip('Smaller'));
    await tester.pumpAndSettle();
    final small = tester.getSize(find.byType(TextField)).height;
    expect(field, greaterThan(small * 2));
  });

  testWidgets('the controls are the same shape in both sizes', (tester) async {
    // ✕ and ✓ with tooltips in either size, rather than words that became
    // icons the moment the sheet grew.
    await open(tester, initial: 'a note');
    expect(find.byTooltip('Cancel'), findsOneWidget);
    expect(find.byTooltip('Save'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Save'), findsNothing);

    await tester.tap(find.byTooltip('Full screen'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Cancel'), findsOneWidget);
    expect(find.byTooltip('Save'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Save'), findsNothing);
  });
}
