import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/theme_presets.dart';
import 'package:nex_client/widgets/note_grid_card.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

/// A grid tile keeps one height in its row at any text size: the words give
/// way rather than overflow (2.6.27).
void main() {
  testWidgets('text tiles omit the visible type label at every density', (
    tester,
  ) async {
    const preview = 'Note preview';
    final note = Note(
      id: 'n',
      type: NoteType.text,
      content: preview,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      deviceId: 'd',
      rev: 1,
      syncState: SyncState.pending,
    );

    for (final density in NexCardDensity.values) {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: NexCardDensityScope(
            density: density,
            child: Center(
              child: SizedBox(
                width: 220,
                child: NexNoteGridCard(
                  note: note,
                  strings: NexCardStrings.fallback,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Text'), findsNothing, reason: density.name);
      expect(find.text(preview), findsOneWidget, reason: density.name);
    }
  });

  Note fileNote(String filename, {String? mimeType, String? path}) => Note(
    id: 'file',
    type: NoteType.file,
    content: filename,
    mimeType: mimeType,
    mediaUri: path,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    deviceId: 'd',
    rev: 1,
    syncState: SyncState.pending,
  );

  testWidgets(
    'file marks use the original suffix, MIME and stored path in order',
    (tester) async {
      for (final (name, mime, path, icon) in [
        (
          'گزارش.PDF',
          'application/octet-stream',
          '/stored',
          Icons.picture_as_pdf_outlined,
        ),
        ('video.MP4', null, null, Icons.smart_display_outlined),
        ('backup.zip', null, null, Icons.folder_zip_outlined),
        ('backup.RAR', null, null, Icons.folder_zip_outlined),
        ('backup.tar.gz', null, null, Icons.folder_zip_outlined),
        ('contract.docx', 'application/zip', null, Icons.description_outlined),
        ('ledger.xlsx', null, null, Icons.table_chart_outlined),
        ('data.csv', 'text/plain', null, Icons.table_chart_outlined),
        ('slides.pptx', null, null, Icons.slideshow_outlined),
        ('image.webp', null, null, Icons.image_outlined),
        ('sample.flac', null, null, Icons.audio_file_outlined),
        ('main.dart', 'text/plain', null, Icons.code_outlined),
        ('notes.txt', null, null, Icons.article_outlined),
        ('book.epub', null, null, Icons.menu_book_outlined),
        (
          'video',
          'Video/WebM; codecs=vp9',
          '/stored.pdf',
          Icons.smart_display_outlined,
        ),
        ('document', null, '/stored.PDF', Icons.picture_as_pdf_outlined),
        (
          'unknown.xyz',
          'application/octet-stream',
          null,
          Icons.insert_drive_file_outlined,
        ),
      ]) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: NexNoteCardGlyph(fileNote(name, mimeType: mime, path: path)),
          ),
        );
        expect(find.byIcon(icon), findsOneWidget, reason: name);
        expect(find.text('MD'), findsNothing, reason: name);
      }
    },
  );

  for (final grid in [false, true]) {
    testWidgets(
      'the ${grid ? 'grid' : 'list'} file card only swaps its glyph',
      (tester) async {
        const generic = Icons.insert_drive_file_outlined;
        const pdf = Icons.picture_as_pdf_outlined;
        Widget host(String filename) {
          final note = fileNote(filename);
          return MaterialApp(
            theme: nexSoftDarkTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 220,
                  child: grid
                      ? NexNoteGridCard(
                          note: note,
                          strings: NexCardStrings.fallback,
                          onTap: () {},
                        )
                      : NoteCard(note: note),
                ),
              ),
            ),
          );
        }

        await tester.pumpWidget(host('report.xyz'));
        final genericFinder = find.byIcon(generic);
        final glyph = find.byType(NexNoteCardGlyph);
        final bounds = tester.getRect(glyph);
        final color = tester.widget<Icon>(genericFinder).color;
        await tester.pumpWidget(host('report.pdf'));
        await tester.pumpAndSettle();
        final pdfFinder = find.byIcon(pdf);
        expect(pdfFinder, findsOneWidget);
        expect(genericFinder, findsNothing);
        expect(tester.getRect(glyph), bounds);
        expect(tester.widget<Icon>(pdfFinder).color, color);

        await tester.pumpWidget(host('report.MD'));
        await tester.pumpAndSettle();
        expect(find.text('MD'), findsOneWidget);
        expect(tester.getRect(glyph), bounds);
        expect(tester.widget<Icon>(genericFinder).color, color);
        expect(pdfFinder, findsNothing);
      },
    );
  }

  for (final scale in [1.0, 1.3, 1.6, 2.0, 2.6, 3.2]) {
    testWidgets('a grid tile fits at text scale $scale', (tester) async {
      final note = Note(
        id: 'n',
        type: NoteType.text,
        content: 'A long title that goes on and on for a while\nAnd a body that also goes on for quite a few words to fill two lines',
        isUrgent: true,
        dueAt: DateTime(2030),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        deviceId: 'd',
        rev: 1,
        syncState: SyncState.pending,
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(360, 800),
              textScaler: TextScaler.linear(scale),
            ),
            child: Builder(
              builder: (context) => Center(
                child: SizedBox(
                  width: 164,
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
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }

  // The wash is the kind's colour over the card; every word on a tile has to
  // read on its strongest corner, in every appearance and palette.
  test('a tile\'s words read on its wash in every theme', () {
    final bad = <String>[];
    for (final preset in nexThemePresets) {
      for (final base in [
        nexSoftLightTheme(),
        nexSoftDarkTheme(),
        nexOledNightTheme(),
      ]) {
        final scheme = nexApplyThemePreset(base, preset.id, null).colorScheme;
        for (final type in NoteType.values) {
          final tint = nexNoteTypeTint(type.wireName, scheme);
          final dark = scheme.brightness == Brightness.dark;
          for (final alpha in [dark ? 0.09 : 0.07, 0.24]) {
            final wash = Color.alphaBlend(
              tint.withValues(alpha: alpha),
              scheme.surfaceContainerLowest,
            );
            for (final (name, ink) in [
              ('title', scheme.onSurface),
              ('words', nexReadableOn(scheme.onSurfaceVariant, wash)),
              (
                'reminder',
                nexReadableOn(
                  scheme.primary,
                  Color.alphaBlend(
                    scheme.primary.withValues(alpha: 0.12),
                    wash,
                  ),
                ),
              ),
              ('kind', nexReadableOn(tint, wash)),
            ]) {
              final ratio = nexContrastRatio(ink, wash);
              if (ratio < 4.5) {
                bad.add(
                  '${preset.id} ${scheme.brightness.name} '
                  '${type.name} $name $alpha: ${ratio.toStringAsFixed(2)}',
                );
              }
            }
          }
        }
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });
}
