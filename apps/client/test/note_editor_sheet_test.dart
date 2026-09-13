import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/ai_provider.dart';
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

  testWidgets('it opens as a sheet on the text it was given', (tester) async {
    await open(tester, initial: 'the boiler is making a noise');

    expect(find.text('Edit note'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'the boiler is making a noise',
    );
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

  testWidgets('a rewrite that comes back empty leaves the note alone', (
    tester,
  ) async {
    await enableAi();
    await open(
      tester,
      initial: 'a note worth keeping',
      client: MockClient((_) async => http.Response('nope', 500)),
    );

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

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result(), isNull);
  });

  testWidgets('Save hands back what is in the field', (tester) async {
    final result = await open(tester, initial: 'first');
    await tester.enterText(find.byType(TextField), 'second');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
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
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
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
    // And the actions are all laid out rather than in a scroller, which is
    // what asking for a bigger editor is asking for.
    expect(find.byType(Wrap), findsWidgets);
    expect(find.byTooltip('Smaller'), findsOneWidget);
  });
}
