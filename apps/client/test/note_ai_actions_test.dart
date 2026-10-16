import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/widgets/folded_note.dart';
import 'package:nex_client/widgets/translate_sheet.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

class _MediaAi implements AIAdapter {
  int images = 0;
  int summaries = 0;
  int tags = 0;
  static const summary = 'A short useful summary.';
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
  Future<List<TagSuggestion>>? suggestTags(Note note) async {
    tags++;
    return const [TagSuggestion(name: 'Ideas')];
  }

  @override
  Future<Summary>? summarize(Note note) async {
    summaries++;
    return const Summary(text: summary);
  }
}

void main() {
  for (final locale in ['en', 'fa']) {
    for (final glass in [false, true]) {
      testWidgets(
        '$locale glass=$glass text AI stays below content and never offers a caption',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          tester.platformDispatcher.textScaleFactorTestValue = 1.6;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final adapter = _MediaAi();
          final h = await NexTestHarness.create(adapter: adapter);
          addTearDown(h.dispose);
          await h.preferences.setAiEnabled(true);
          await h.preferences.setAiProvider(
            const AiProviderConfig(
              provider: AiProvider.openai,
              apiKey: 'test-key',
            ),
          );
          const original =
              'A detailed original note about plans, ideas, and things to remember. The source must stay unchanged when a summary is generated.';
          final note = (await h.services.captureText(original))!;
          final theme = glass
              ? nexDarkTheme(liquidGlass: true)
              : nexLightTheme();
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
          final l10n = AppLocalizations.of(
            tester.element(find.byType(NoteDetailSheet)),
          );
          final workspace = find.byKey(const ValueKey('note-ai-workspace'));
          expect(
            tester.getTopLeft(workspace).dy,
            greaterThan(tester.getBottomLeft(find.byType(FoldedNote)).dy),
          );
          final tools = find.byKey(const ValueKey('note-ai-tools'));
          for (final label in [
            l10n.summarize,
            l10n.translate,
            l10n.askAboutNote,
            l10n.aiTagsAction,
          ]) {
            expect(
              find.descendant(of: tools, matching: find.byTooltip(label)),
              findsOneWidget,
            );
            expect(
              find.descendant(of: tools, matching: find.text(label)),
              findsNothing,
            );
          }
          await tester.ensureVisible(find.byTooltip(l10n.summarize));
          await tester.longPress(find.byTooltip(l10n.summarize));
          await tester.pumpAndSettle();
          expect(find.text(l10n.summarize), findsOneWidget);
          expect(adapter.summaries, 0);
          Tooltip.dismissAllToolTips();
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip(l10n.summarize));
          await tester.pumpAndSettle();
          expect(adapter.summaries, 1);
          expect(find.text(_MediaAi.summary), findsOneWidget);
          expect(find.text(l10n.aiAddToCaption), findsNothing);
          expect((await h.services.getById(note.id))!.caption, isNull);
          final status = find.byKey(const ValueKey('note-ai-status'));
          expect(tester.widget<Text>(status).textAlign, TextAlign.end);
          final panelRect = tester.getRect(workspace);
          final statusRect = tester.getRect(status);
          expect(
            locale == 'fa' ? statusRect.left : statusRect.right,
            closeTo(
              locale == 'fa'
                  ? panelRect.left + NexSpacing.md
                  : panelRect.right - NexSpacing.md,
              0.1,
            ),
          );

          await tester.ensureVisible(find.byTooltip(l10n.aiTagsAction));
          await tester.tap(find.byTooltip(l10n.aiTagsAction));
          await tester.pumpAndSettle();
          expect(adapter.tags, 1);
          expect(find.text('Ideas'), findsOneWidget);
          expect((await h.services.getById(note.id))!.tags, isEmpty);
          await tester.ensureVisible(find.byTooltip(l10n.hide));
          await tester.tap(find.byTooltip(l10n.hide));
          await tester.pumpAndSettle();
          expect(find.text(_MediaAi.summary), findsNothing);
          expect(find.text('Ideas'), findsNothing);
          await tester.ensureVisible(find.text(l10n.aiShowResults));
          await tester.tap(find.text(l10n.aiShowResults));
          await tester.pumpAndSettle();
          expect(find.text(_MediaAi.summary), findsOneWidget);
          expect(find.text('Ideas'), findsOneWidget);
          expect(adapter.summaries, 1);
          expect(adapter.tags, 1);

          await tester.ensureVisible(find.byTooltip(l10n.translate));
          await tester.tap(find.byTooltip(l10n.translate));
          await tester.pumpAndSettle();
          final translator = tester.widget<TranslateSheet>(
            find.byType(TranslateSheet),
          );
          expect(translator.onAddToCaption, isNull);
          expect(translator.text, original);
          final translationState = tester.state(find.byType(TranslateSheet));
          await tester.ensureVisible(find.byTooltip(l10n.hide));
          await tester.tap(find.byTooltip(l10n.hide));
          await tester.pumpAndSettle();
          expect(find.byType(TranslateSheet), findsNothing);
          await tester.ensureVisible(find.text(l10n.aiShowResults));
          await tester.tap(find.text(l10n.aiShowResults));
          await tester.pumpAndSettle();
          expect(
            tester.state(find.byType(TranslateSheet)),
            same(translationState),
          );
          await tester.ensureVisible(
            find.byKey(const ValueKey('note-ai-result-picker')),
          );
          await tester.tap(find.byKey(const ValueKey('note-ai-result-picker')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(l10n.summary));
          await tester.pumpAndSettle();
          expect(find.text(_MediaAi.summary), findsOneWidget);
          expect(find.text(l10n.aiAddToCaption), findsNothing);
          expect((await h.services.getById(note.id))!.content, original);
          expect((await h.services.getById(note.id))!.caption, isNull);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        },
      );
    }
  }

  for (final locale in ['en', 'fa']) {
    for (final (caption, glass) in [
      ('', false),
      ('', true),
      ('Keep my caption', false),
      ('Keep my caption', true),
    ]) {
      testWidgets(
        '$locale glass=$glass image action is explicit; caption=$caption is preserved',
        (tester) async {
          final adapter = _MediaAi();
          final theme = caption.isEmpty
              ? nexLightTheme(liquidGlass: glass)
              : nexDarkTheme(liquidGlass: glass);
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
            final tooltip = find.byTooltip(label);
            expect(tester.widget<Tooltip>(tooltip).preferBelow, isFalse);
            expect(
              find.descendant(of: tooltip, matching: find.byType(Text)),
              findsNothing,
            );
            final button = find.descendant(
              of: tooltip,
              matching: find.byType(IconButton),
            );
            expect(button, findsOneWidget);
            final widget = tester.widget<IconButton>(button);
            expect(
              widget.style!.foregroundColor!.resolve({}),
              theme.colorScheme.primary,
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
          expect(find.byTooltip(l10n.translate), findsNothing);
          expect(find.byTooltip(l10n.summarize), findsNothing);
          await tester.ensureVisible(find.byTooltip(l10n.aiDescribeImage));
          expectActionColors(l10n.aiDescribeImage);
          await tester.tap(find.byTooltip(l10n.aiDescribeImage));
          await tester.pumpAndSettle();
          expect(adapter.images, 1);
          expect((await h.services.getById(note.id))!.ocrText, _MediaAi.result);
          expect(
            (await h.services.getById(note.id))!.caption,
            caption.isEmpty ? null : caption,
          );
          await tester.ensureVisible(
            find.byKey(const ValueKey('note-ai-hide-results')),
          );
          await tester.tap(find.byKey(const ValueKey('note-ai-hide-results')));
          await tester.pumpAndSettle();
          expect(find.text(_MediaAi.result), findsNothing);
          expect(find.text(l10n.aiAddToCaption), findsNothing);
          expect(find.byTooltip(l10n.aiDescribeImage), findsOneWidget);
          await tester.ensureVisible(find.text(l10n.aiShowResults));
          await tester.tap(find.text(l10n.aiShowResults));
          await tester.pumpAndSettle();
          expect(
            adapter.images,
            1,
            reason: 'revealing output must reuse the saved result',
          );
          await tester.ensureVisible(find.text(l10n.aiAddToCaption));
          await tester.tap(find.text(l10n.aiAddToCaption));
          await tester.pumpAndSettle();
          if (caption.isNotEmpty) {
            expect(find.text(l10n.aiAppendCaptionTitle), findsOneWidget);
            expect(find.text(l10n.aiAppendCaption), findsOneWidget);
            expect(find.text(l10n.aiReplaceCaption), findsOneWidget);
            expect(find.text(l10n.cancel), findsOneWidget);
            if (!narrow) {
              expect(
                tester
                    .getSize(
                      find.descendant(
                        of: find.byType(Dialog),
                        matching: find.byWidgetPredicate(
                          (widget) =>
                              widget is Material &&
                              widget.type == MaterialType.card,
                        ),
                      ),
                    )
                    .width,
                lessThanOrEqualTo(460),
                reason: 'The action stack must keep the shared dialog width.',
              );
            }
            final choices =
                [l10n.aiAppendCaption, l10n.aiReplaceCaption, l10n.cancel]
                    .map(
                      (label) => tester.getRect(
                        find.ancestor(
                          of: find.text(label),
                          matching: find.bySubtype<ButtonStyleButton>(),
                        ),
                      ),
                    )
                    .toList();
            for (var i = 1; i < choices.length; i++) {
              expect(choices[i].left, closeTo(choices.first.left, 0.1));
              expect(choices[i].width, closeTo(choices.first.width, 0.1));
              expect(choices[i].top, greaterThan(choices[i - 1].bottom));
            }
            expect(tester.takeException(), isNull);
            await tester.tap(find.text(l10n.cancel));
            await tester.pumpAndSettle();
            expect((await h.services.getById(note.id))!.caption, caption);
            await tester.ensureVisible(find.text(l10n.aiAddToCaption));
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
          await tester.ensureVisible(find.text(l10n.aiAddToCaption));
          await tester.tap(find.text(l10n.aiAddToCaption));
          await tester.pumpAndSettle();
          await tester.tap(find.text(l10n.aiReplaceCaption));
          await tester.pumpAndSettle();
          expect((await h.services.getById(note.id))!.caption, _MediaAi.result);
          await tester.ensureVisible(find.text(l10n.aiAddToCaption));
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
          await tester.ensureVisible(find.byTooltip(l10n.summarize));
          expectActionColors(l10n.summarize);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
