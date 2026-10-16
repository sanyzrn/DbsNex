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
            final text = find.text(label);
            final button = find.ancestor(
              of: text,
              matching: find.bySubtype<OutlinedButton>(),
            );
            expect(button, findsOneWidget);
            final widget = tester.widget<OutlinedButton>(button);
            expect(
              widget.style!.foregroundColor!.resolve({}),
              theme.colorScheme.onSurface,
            );
            final glyph = find
                .descendant(
                  of: button,
                  matching: find.byWidgetPredicate(
                    (w) => w is Icon || w is NexSummariseIcon,
                  ),
                )
                .first;
            expect(
              IconTheme.of(tester.element(glyph)).color,
              theme.colorScheme.primary,
            );
          }

          expect(
            adapter.images,
            0,
            reason: 'opening a photo must not upload it',
          );
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
            expect(find.text(l10n.aiAppendCaption), findsOneWidget);
            expect(find.text(l10n.aiReplaceCaption), findsOneWidget);
            expect(find.text(l10n.cancel), findsOneWidget);
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
          // A full replacement changes only the caption. A later edit made
          // while the confirmation is open must win over a stale replacement.
          await tester.tap(find.text(l10n.aiAddToCaption));
          await tester.pumpAndSettle();
          await tester.tap(find.text(l10n.aiReplaceCaption));
          await tester.pumpAndSettle();
          expect((await h.services.getById(note.id))!.caption, _MediaAi.result);
          await tester.tap(find.text(l10n.aiAddToCaption));
          await tester.pumpAndSettle();
          await h.services.setCaption(note.id, 'A newer manual edit');
          await tester.tap(find.text(l10n.aiReplaceCaption));
          await tester.pumpAndSettle();
          final preserved = (await h.services.getById(note.id))!;
          expect(preserved.caption, 'A newer manual edit');
          expect(preserved.mediaUri, note.mediaUri);
          expect(preserved.ocrText, _MediaAi.result);
          expect(await h.services.relatedNotes(note.id), isEmpty);
          expect(h.db.relatedQueries, 0);
          expect(h.preferences.aiCapabilities.relatedNotes, isTrue);
          expect(h.preferences.effectiveAiCapabilities.relatedNotes, isFalse);
          expect(h.preferences.effectiveAiCapabilities.semanticSearch, isTrue);
          await tester.ensureVisible(find.text(l10n.summarize));
          expectActionColors(l10n.summarize);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
