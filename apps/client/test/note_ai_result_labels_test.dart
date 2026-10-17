import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

void main() {
  Future<AppLocalizations> open(
    WidgetTester tester,
    NexTestHarness h,
    String id,
    String locale, {
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        theme: nexLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: NoteDetailSheet(services: h.services, noteId: id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(NoteDetailSheet)));
  }

  for (final locale in ['en', 'fa']) {
    testWidgets('$locale converted Markdown source is absent from AI results', (
      tester,
    ) async {
      final h = await NexTestHarness.create();
      addTearDown(h.dispose);
      const source = '# A Markdown note\n\n- Keep the source unchanged.';
      final note = (await h.services.captureText(source))!;
      await tester.runAsync(() => h.services.convertMarkdown(note));
      final converted = (await h.services.getById(note.id))!;
      expect(converted.type, NoteType.file);
      expect(converted.mimeType, 'text/markdown');
      expect(converted.ocrText, source);
      expect(File(converted.mediaUri!).readAsStringSync(), source);
      final l10n = await open(tester, h, note.id, locale);
      expect(find.text(l10n.aiExtractedText), findsNothing);
      expect(find.byKey(const ValueKey('note-ai-results')), findsNothing);
      expect(find.text(l10n.aiImageResult), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    for (final (name, mime, image) in [
      ('report.md', 'text/markdown', false),
      ('notes.txt', 'text/plain', false),
      ('report.pdf', 'application/pdf', false),
      (
        'report.docx',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        false,
      ),
      ('table.csv', 'text/csv', false),
      ('data.json', 'application/json', false),
      ('unknown.bin', 'application/octet-stream', false),
      ('photo.jpg', 'image/jpeg', true),
      ('photo', 'image/png', true),
      ('image.png', 'application/octet-stream', true),
    ]) {
      testWidgets('$locale $name cached text uses its actual media kind', (
        tester,
      ) async {
        final h = await NexTestHarness.create();
        addTearDown(h.dispose);
        // Specific MIME works without an extension; generic MIME falls back
        // to the stored path. Missing previews keep this about cached output.
        final path = mime == 'application/octet-stream' ? name : 'missing';
        final note = await h.services.captureFile(
          mediaUri: '${h.root.path}/$path',
          mediaHash: 'file',
          originalFilename: name,
          mimeType: mime,
        );
        h.db.seedReadText(note.id, 'Previously extracted or described text.');
        final l10n = await open(tester, h, note.id, locale);
        expect(
          find.byTooltip(image ? l10n.aiImageResult : l10n.aiExtractedText),
          name.endsWith('.md') ? findsNothing : findsOneWidget,
        );
        expect(
          find.byTooltip(image ? l10n.aiExtractedText : l10n.aiImageResult),
          findsNothing,
        );
        expect(
          (await h.services.getById(note.id))!.ocrText,
          'Previously extracted or described text.',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }

    testWidgets(
      '$locale file and image attachments keep distinct result names',
      (tester) async {
        tester.view.physicalSize = const Size(360, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final h = await NexTestHarness.create();
        addTearDown(h.dispose);
        final note = (await h.services.captureText(
          'A note with several files.',
        ))!;
        for (final (name, kind, mime) in [
          ('document.md', AttachmentKind.file, 'text/markdown'),
          ('scan.pdf', AttachmentKind.file, 'application/pdf'),
          ('image', AttachmentKind.file, 'image/png'),
          ('camera', AttachmentKind.photo, null),
        ]) {
          final attachment = (await h.db.attachmentAdd(
            note.id,
            kind: kind,
            mediaUri: '${h.root.path}/$name',
            mediaHash: name,
            name: name,
            mimeType: mime,
          ))!;
          await h.db.attachmentSetOcr(attachment.id, 'Stored text from $name');
        }
        final l10n = await open(tester, h, note.id, locale, textScale: 1.6);
        await tester.ensureVisible(
          find.byKey(const ValueKey('note-ai-result-picker')),
        );
        for (var i = 1; i <= 4; i++) {
          final number = nexDigits('$i', persian: locale == 'fa');
          final correct = i <= 2 ? l10n.aiExtractedText : l10n.aiImageResult;
          final wrong = i <= 2 ? l10n.aiImageResult : l10n.aiExtractedText;
          expect(find.byTooltip('$correct · $number'), findsOneWidget);
          expect(find.byTooltip('$wrong · $number'), findsNothing);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
}
