import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/widgets/nex_banner.dart';
import 'package:nex_core/nex_core.dart';

import 'support/nex_harness.dart';

/// A model with nothing new to say about a note's tags.
class _NoTags implements AIAdapter {
  int asked = 0;
  @override
  Future<OCRText>? ocr(ImageRef image) => null;
  @override
  Future<Transcript>? transcribe(AudioRef audio) => null;
  @override
  Future<Vector>? embed(String text) => null;
  @override
  Future<Summary>? summarize(Note note) => null;
  @override
  Future<List<TagSuggestion>>? suggestTags(Note note) async {
    asked++;
    return const [];
  }
}

void main() {
  testWidgets('Suggest tags says so when there is nothing to suggest', (
    tester,
  ) async {
    final adapter = _NoTags();
    final h = await NexTestHarness.create(adapter: adapter);
    addTearDown(h.dispose);
    await h.preferences.setAiEnabled(true);
    await h.preferences.setAiProvider(
      const AiProviderConfig(provider: AiProvider.openai, apiKey: 'test-key'),
    );
    final note = (await h.db.captureText('A note about the garden.'))!;
    await tester.pumpWidget(
      MaterialApp(
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
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NoteDetailSheet)),
    );
    await tester.ensureVisible(find.byTooltip(l10n.aiTagsAction));
    await tester.tap(find.byTooltip(l10n.aiTagsAction));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(adapter.asked, 1);
    // Not a silent tap: the reason is said where the person is looking.
    expect(find.text(l10n.aiNoTagSuggestions), findsOneWidget);
    nexHideBanner();
    await tester.pumpAndSettle();
  });
}
