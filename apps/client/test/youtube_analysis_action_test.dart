import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// 2.1.7: a saved YouTube video gets "Analyze video" in its AI tools when
/// the provider can watch one from its address, in place of a summary of the
/// page's few words.
void main() {
  Future<NexTestHarness> open(
    WidgetTester tester,
    AiProvider provider, {
    String url = 'https://youtu.be/dQw4w9WgXcQ',
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    await h.preferences.setAiEnabled(true);
    await h.preferences.setAiProvider(
      AiProviderConfig(provider: provider, apiKey: 'test-key'),
    );
    final note = (await h.services.captureLink(url))!;
    await tester.pumpWidget(
      MaterialApp(
        theme: nexLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NoteDetailSheet(
            services: h.services,
            preferences: h.preferences,
            noteId: note.id,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return h;
  }

  testWidgets('Gemini offers it on a YouTube link and says when it fails', (
    tester,
  ) async {
    await open(tester, AiProvider.gemini);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NoteDetailSheet)),
    );
    final action = find.byTooltip(l10n.aiAnalyzeVideo);
    expect(action, findsOneWidget);
    expect(find.byTooltip(l10n.summarize), findsNothing);
    // flutter_test answers every request with a 400 and no words: the
    // refusal is said with its code (2.1.9), not as a lost connection.
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.aiVideoFailedRefused('400', l10n.aiVideoRefusedReason)),
      findsOneWidget,
    );
  });

  group('2.1.9', () {
    tearDown(() => nexVideoClientForTest = null);

    http.Response gemini(String text) => http.Response(
      jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': text},
              ],
            },
            'finishReason': 'STOP',
          },
        ],
      }),
      200,
    );

    testWidgets('a plan\'s limit is said as one, not as a private video', (
      tester,
    ) async {
      nexVideoClientForTest = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'message': 'Resource has been exhausted.'},
          }),
          429,
        ),
      );
      await open(tester, AiProvider.gemini);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(NoteDetailSheet)),
      );
      final action = find.byTooltip(l10n.aiAnalyzeVideo);
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text(l10n.aiVideoFailedLimit), findsOneWidget);
    });

    test('the excerpt arriving while the video is watched does not cost '
        'the analysis', () async {
      final h = await NexTestHarness.create();
      addTearDown(h.dispose);
      await h.preferences.setAiEnabled(true);
      await h.preferences.setAiProvider(
        const AiProviderConfig(provider: AiProvider.gemini, apiKey: 'k'),
      );
      final note = (await h.services.captureLink(
        'https://youtu.be/dQw4w9WgXcQ',
      ))!;
      final before = (await h.db.getById(note.id))!.aiSourceText;
      nexVideoClientForTest = MockClient((_) async {
        // The link preview lands mid-analysis and changes the note's
        // words — which used to make a finished analysis unkeepable.
        await h.db.setLinkMetadata(note.id, excerpt: 'Official video');
        return gemini('A song.\n- 0:43 the chorus');
      });
      final result = await h.services.analyzeVideo(note.id);
      expect(
        (await h.db.getById(note.id))!.aiSourceText,
        isNot(before),
        reason: 'the words did change',
      );
      expect(result.failure, isNull);
      expect(result.text, contains('the chorus'));
      expect(
        (await h.db.getById(note.id))!.summaryText,
        contains('the chorus'),
      );
    });

    test('a link changed while the video is watched keeps nothing', () async {
      final h = await NexTestHarness.create();
      addTearDown(h.dispose);
      await h.preferences.setAiEnabled(true);
      await h.preferences.setAiProvider(
        const AiProviderConfig(provider: AiProvider.gemini, apiKey: 'k'),
      );
      final note = (await h.services.captureLink(
        'https://youtu.be/dQw4w9WgXcQ',
      ))!;
      nexVideoClientForTest = MockClient((_) async {
        await h.db.deleteNote(note.id);
        return gemini('A song.');
      });
      final result = await h.services.analyzeVideo(note.id);
      expect(result.failure, NexVideoFailure.changed);
    });
  });

  testWidgets('not on a provider that cannot watch, nor on another link', (
    tester,
  ) async {
    await open(tester, AiProvider.openai);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NoteDetailSheet)),
    );
    expect(find.byTooltip(l10n.aiAnalyzeVideo), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await open(tester, AiProvider.gemini, url: 'https://example.com/article');
    expect(find.byTooltip(l10n.aiAnalyzeVideo), findsNothing);
  });
}
