import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

void main() {
  for (final locale in ['en', 'fa']) {
    for (final dark in [false, true]) {
      testWidgets(
        '$locale dark=$dark summary renders and expands in the sheet',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          String? copied;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                copied = (call.arguments as Map)['text'] as String;
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          final h = await NexTestHarness.create();
          addTearDown(h.dispose);
          final source = List.filled(
            100,
            'Original note remains unchanged.',
          ).join(' ');
          final note = (await h.services.captureText(source))!;
          final summary = List.generate(
            18,
            (i) => locale == 'fa'
                ? '- **تصمیم:** انتشار مشروط به رفع خطا و تأیید طرح است.'
                : '- **Decision:** Release requires the fix and approval.',
          ).join('\n');
          final tail = locale == 'fa'
              ? 'پایان خلاصه: بودجه سقف مجاز است، نه هزینه انجام‌شده.'
              : 'Summary tail: the budget is a ceiling, not actual spending.';
          final stored = '$summary\n\n$tail';
          await h.db.setSummaryText(note.id, stored);
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(locale),
              theme: dark ? nexDarkTheme() : nexLightTheme(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: const TextScaler.linear(1.8),
                ),
                child: child!,
              ),
              home: Scaffold(
                body: NoteDetailSheet(services: h.services, noteId: note.id),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final l10n = AppLocalizations.of(
            tester.element(find.byType(NoteDetailSheet)),
          );
          final result = find.byKey(const ValueKey('note-ai-results'));
          final expand = find.descendant(
            of: result,
            matching: find.byTooltip(l10n.aiResultExpand),
          );
          expect(expand, findsOneWidget);
          // The folded preview is plain readable text, without raw ** markers.
          for (final widget in tester.widgetList<RichText>(
            find.descendant(of: result, matching: find.byType(RichText)),
          )) {
            expect(widget.text.toPlainText(), isNot(contains('**')));
          }
          await tester.ensureVisible(expand);
          await tester.tap(expand);
          await tester.pumpAndSettle();
          final markdown = find.descendant(
            of: result,
            matching: find.byType(NexMarkdown),
          );
          expect(markdown, findsOneWidget);
          expect(tester.widget<NexMarkdown>(markdown).text, stored);
          // No vertical scroll box hides the second half of the summary.
          final nestedScrollers = find.descendant(
            of: result,
            matching: find.byType(Scrollable),
          );
          expect(nestedScrollers, findsNothing);
          final tailText = find.textContaining(tail, findRichText: true).last;
          await tester.ensureVisible(tailText);
          await tester.pumpAndSettle();
          expect(tailText.hitTestable(), findsOneWidget);
          final copy = find.descendant(
            of: result,
            matching: find.text(l10n.copy),
          );
          await tester.ensureVisible(copy);
          await tester.tap(copy);
          await tester.pumpAndSettle();
          expect(copied, stored);
          expect((await h.services.getById(note.id))!.content, source);
          expect((await h.services.getById(note.id))!.summaryText, stored);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
