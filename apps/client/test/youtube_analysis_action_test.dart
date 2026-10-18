import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    // flutter_test answers every request with a 400: the failure is said.
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text(l10n.aiVideoFailed), findsOneWidget);
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
