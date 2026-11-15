import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/note_grid_card.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

/// A grid tile shows whole lines only, and picking it moves nothing but its
/// edge (2.7.2) — both reported from a phone, with a Persian note whose
/// last line was drawn half under the tile and whose lines jumped when the
/// tile was picked.
///
/// The app's own faces are loaded: under the test font every line is exactly
/// `fontSize × height` tall, which is the estimate that was wrong for
/// Vazirmatn and a Latin word inside a Persian line.
void main() {
  setUpAll(() async {
    Future<void> load(String family, String path) async {
      final loader = FontLoader(family)
        ..addFont(
          Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
        );
      await loader.load();
    }

    await load(nexLatinFont, 'assets/fonts/Inter-subset.ttf');
    await load(nexPersianFont, 'assets/fonts/VazirmatnVariable.ttf');
  });

  final note = Note(
    id: 'n',
    type: NoteType.text,
    content:
        'در ریپوی "sanyzrn/DbsNex"، یک بررسی عمیق و خط‌به‌خط روی ارتباط و '
        'یکپارچگی زیرسیستم‌های اپ انجام بده.\n\nنقطهٔ شروع:\n\n'
        '- apps/client/lib/platform/nex_services.dart و همهٔ فایل‌هایی که '
        'از آن خوانده می‌شوند، تا آخرین خط.',
    pinnedAt: DateTime(2026),
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    deviceId: 'd',
    rev: 1,
    syncState: SyncState.pending,
  );

  Future<void> pump(
    WidgetTester tester, {
    bool? selected,
    double width = 190,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        theme: nexLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: Builder(
              builder: (context) => Center(
                child: SizedBox(
                  width: width,
                  height: NexNoteGridCard.heightFor(context),
                  child: NexNoteGridCard(
                    note: note,
                    strings: NexCardStrings.fallback,
                    onTap: () {},
                    onLeadingTap: () {},
                    selected: selected,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The paragraph of the note's words: the one that starts with them.
  RenderParagraph body(WidgetTester tester) => tester
      .renderObjectList<RenderParagraph>(find.byType(RichText))
      .firstWhere((p) => p.text.toPlainText().startsWith('در ریپوی'));

  for (final width in [110.0, 190.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('every line drawn is a whole line ($width, ×$scale)', (
        tester,
      ) async {
        await pump(tester, width: width, scale: scale);
        final paragraph = body(tester);
        final clip = tester.renderObject<RenderBox>(
          find
              .ancestor(
                of: find.byWidgetPredicate(
                  (w) =>
                      w is RichText &&
                      w.text.toPlainText().startsWith('در ریپوی'),
                ),
                matching: find.byType(ClipRect),
              )
              .first,
        );
        final top = clip.localToGlobal(Offset.zero).dy;
        final bottom = top + clip.size.height;
        final paragraphBottom =
            paragraph.localToGlobal(Offset.zero).dy + paragraph.size.height;
        expect(
          paragraphBottom,
          lessThanOrEqualTo(bottom + 0.5),
          reason: 'the last line must not run under the clip',
        );
      });
    }
  }

  testWidgets('picking the tile moves none of its words', (tester) async {
    await pump(tester);
    final before = body(tester);
    final where = before.localToGlobal(Offset.zero);
    final height = before.size.height;
    await pump(tester, selected: true);
    final after = body(tester);
    expect(after.localToGlobal(Offset.zero), where);
    expect(after.size.height, height);
  });

  Future<void> pumpNote(WidgetTester tester, Note note) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        theme: nexLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Center(
            child: SizedBox(
              width: 190,
              height: NexNoteGridCard.heightFor(context),
              child: NexNoteGridCard(
                note: note,
                strings: NexCardStrings.fallback,
                onTap: () {},
                onLeadingTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Note textNote(String content, {String? caption}) => Note(
    id: 't',
    type: NoteType.text,
    content: content,
    caption: caption,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    deviceId: 'd',
    rev: 1,
    syncState: SyncState.pending,
  );

  bool bold(WidgetTester tester, String text) => tester
      .widgetList<Text>(find.text(text))
      .any((t) => t.style?.fontWeight == FontWeight.w700);

  testWidgets('a first line is a heading only when written as one (2.7.2)', (
    tester,
  ) async {
    await pumpNote(
      tester,
      textNote('ورزشکار بتونه درخواست مربی بده\nفعلا اشتراک‌ها کنسل'),
    );
    expect(
      find.textContaining('ورزشکار بتونه'),
      findsOneWidget,
      reason: 'the whole note is one text',
    );
    expect(
      tester
          .widgetList<Text>(find.textContaining('ورزشکار بتونه'))
          .any((t) => t.style?.fontWeight == FontWeight.w700),
      isFalse,
    );

    await pumpNote(tester, textNote('# خرید هفته\nنان و شیر'));
    expect(bold(tester, 'خرید هفته'), isTrue);
  });

  testWidgets('a text note\'s caption shows on its tile (2.7.2)', (
    tester,
  ) async {
    await pumpNote(
      tester,
      textNote('متن یادداشت', caption: 'توضیح زیر یادداشت'),
    );
    expect(find.byKey(const ValueKey('grid-caption')), findsOneWidget);
    expect(find.text('توضیح زیر یادداشت'), findsOneWidget);
  });
}
