import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

class _MediaAi implements AIAdapter {
  int images = 0;
  static const result =
      'A red flower with green leaves in a small pot. '
      'The background is plain and there is no visible writing. '
      'Only the visible flower and its leaves are described.';
  @override
  Future<OCRText>? ocr(ImageRef image) async {
    images++;
    return const OCRText(text: result);
  }

  @override
  Future<Transcript>? transcribe(AudioRef audio) => null;
  @override
  Future<Vector>? embed(String text) => null;
  @override
  Future<List<TagSuggestion>>? suggestTags(Note note) => null;
  @override
  Future<Summary>? summarize(Note note) => null;
}

void main() {
  for (final locale in ['en', 'fa']) {
    for (final caption in ['', 'Keep my caption']) {
      testWidgets(
        '$locale image action is explicit; caption=$caption is preserved',
        (tester) async {
          final adapter = _MediaAi();
          final theme = caption.isEmpty
              ? nexLightTheme(liquidGlass: true)
              : nexDarkTheme(liquidGlass: true);
          final h = await NexTestHarness.create(adapter: adapter);
          addTearDown(h.dispose);
          final narrow = locale == 'fa' && caption.isNotEmpty;
          tester.view.physicalSize = narrow
              ? const Size(390, 844)
              : const Size(900, 1800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          if (narrow) {
            tester.platformDispatcher.textScaleFactorTestValue = 1.6;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
          }
          await h.preferences.setAiEnabled(true);
          await h.preferences.setAiProvider(
            const AiProviderConfig(
              provider: AiProvider.gemini,
              apiKey: 'test-key',
            ),
          );
          final note = await h.services.capturePhoto(
            mediaUri: '${h.root.path}/photo.jpg',
            mediaHash: 'image',
          );
          if (caption.isNotEmpty) await h.services.setCaption(note.id, caption);
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(locale),
              theme: theme,
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
          final context = tester.element(find.byType(NoteDetailSheet));
          final l10n = AppLocalizations.of(context);
          void expectActionColors(String label) {
            final row = find.ancestor(
              of: find.text(label),
              matching: find.byType(ListTile),
            );
            final tile = tester.widget<ListTile>(row);
            expect(
              tester.widget<Text>(find.text(label)).style?.color,
              theme.colorScheme.onSurface,
            );
            expect(
              IconTheme.of(tester.element(find.byWidget(tile.leading!))).color,
              theme.colorScheme.primary,
            );
          }

          expect(
            adapter.images,
            0,
            reason: 'opening a photo must not upload it',
          );
          await tester.tap(find.byIcon(Icons.more_horiz));
          await tester.pumpAndSettle();
          expect(find.text(l10n.translate), findsNothing);
          expect(find.text(l10n.summarize), findsNothing);
          await tester.ensureVisible(find.text(l10n.aiDescribeImage));
          expectActionColors(l10n.aiDescribeImage);
          await tester.tap(find.text(l10n.aiDescribeImage));
          await tester.pumpAndSettle();
          expect(adapter.images, 1);
          expect((await h.services.getById(note.id))!.ocrText, _MediaAi.result);
          expect(
            (await h.services.getById(note.id))!.caption,
            caption.isEmpty ? null : caption,
          );
          await tester.ensureVisible(find.text(l10n.aiAddToCaption));
          await tester.tap(find.text(l10n.aiAddToCaption));
          await tester.pumpAndSettle();
          if (caption.isNotEmpty) {
            expect(find.text(l10n.aiAppendCaptionTitle), findsOneWidget);
            await tester.tap(find.text(l10n.cancel));
            await tester.pumpAndSettle();
            expect((await h.services.getById(note.id))!.caption, caption);
            await tester.tap(find.text(l10n.aiAddToCaption));
            await tester.pumpAndSettle();
            await tester.tap(find.text(l10n.aiAppendCaption));
            await tester.pumpAndSettle();
          }
          final saved = (await h.services.getById(note.id))!;
          expect(
            saved.caption,
            caption.isEmpty
                ? _MediaAi.result
                : '$caption\n\n${_MediaAi.result}',
          );
          expect(saved.ocrText, _MediaAi.result);
          expect(saved.mediaHash, note.mediaHash);
          await tester.tap(find.byIcon(Icons.more_horiz));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text(l10n.aiSummarizeImageText));
          expectActionColors(l10n.aiSummarizeImageText);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
