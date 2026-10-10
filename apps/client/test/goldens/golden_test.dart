/// Linux only (REL-16). The pictures were drawn by CI's Linux runner, and
/// that is the one renderer they are checked against: on Windows the same
/// commit differed by ~2% at glyph edges in 36 pictures — anti-aliasing,
/// not the app. The rest of the suite runs everywhere.
@TestOn('linux')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/hold_menu.dart';
import 'package:nex_client/platform/theme_presets.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/widgets/nex_banner.dart';
import 'package:nex_client/widgets/note_context_menu.dart';
import 'package:nex_data/nex_data.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;

import '../support/nex_harness.dart';

/// W6.2: what the surfaces most of the last twenty releases' bugs were found
/// on look like, in both directions, both brightnesses and every palette.
///
/// Update after an intended visual change with
///
///     flutter test --update-goldens test/goldens/
///
/// and look at every changed picture before committing it.
void main() {
  setUpAll(() async {
    await _loadFonts();
    final local = goldenFileComparator as LocalFileComparator;
    goldenFileComparator = _TolerantComparator(
      Uri.parse('${local.basedir}golden_test.dart'),
    );
  });

  // Fixed, so a date on a card or in the sheet never makes a picture stale.
  final written = DateTime.utc(2026, 3, 14, 9, 26);

  Note note(String id, NoteType type, String content) => Note(
    id: id,
    type: type,
    content: content,
    createdAt: written,
    updatedAt: written,
    deviceId: 'golden',
    rev: 1,
    syncState: SyncState.synced,
  );

  const english =
      'Call the landlord about the heating before Friday.\n'
      'Ask whether the boiler service is included.';
  const persian =
      'قبل از جمعه با صاحبخانه دربارهٔ شوفاژ تماس بگیرم.\n'
      'بپرسم سرویس پکیج هم شامل قرارداد هست یا نه.';

  for (final rtl in [false, true]) {
    for (final dark in [false, true]) {
      final variant = '${rtl ? 'rtl' : 'ltr'}_${dark ? 'dark' : 'light'}';
      final locale = Locale(rtl ? 'fa' : 'en');

      testWidgets('timeline cards $variant', (tester) async {
        await _frame(tester, const Size(420, 330));
        await tester.pumpWidget(
          _app(
            locale: locale,
            dark: dark,
            child: Column(
              children: [
                NoteCard(
                  note: note('a', NoteType.text, rtl ? persian : english),
                  onTap: () {},
                ),
                NoteCard(
                  note: note(
                    'b',
                    NoteType.checklist,
                    rtl
                        ? '- [x] نان\n- [ ] شیر\n- [ ] تخم‌مرغ'
                        : '- [x] Bread\n- [ ] Milk\n- [ ] Eggs',
                  ),
                  onTap: () {},
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('timeline_cards_$variant.png'),
        );
      });

      testWidgets('hold menu $variant', (tester) async {
        await _frame(tester, const Size(420, 480));
        await tester.pumpWidget(
          _app(
            locale: locale,
            dark: dark,
            child: NoteContextMenu(
              entries: [
                for (final action in [
                  NexHoldAction.pin,
                  NexHoldAction.copy,
                  NexHoldAction.edit,
                  NexHoldAction.remind,
                  NexHoldAction.delete,
                ])
                  NoteMenuEntry(action, () {}),
              ],
              child: NoteCard(
                note: note('a', NoteType.text, rtl ? persian : english),
                onTap: () {},
              ),
            ),
          ),
        );
        await tester.longPress(find.byType(NoteCard));
        await tester.pumpAndSettle();
        // The whole app: the menu is drawn in the overlay, above the page.
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('hold_menu_$variant.png'),
        );
      });

      testWidgets('capsule notice $variant', (tester) async {
        await _frame(tester, const Size(420, 200));
        await tester.pumpWidget(
          _app(
            locale: locale,
            dark: dark,
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => nexShowBanner(
                  context,
                  message: rtl ? 'یادداشت حذف شد' : 'Note deleted',
                  actionLabel: rtl ? 'بازگردانی' : 'Undo',
                  onAction: () {},
                  haptics: false,
                ),
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        );
        await tester.tap(find.byType(TextButton));
        // Past the drip-in, well before an Undo notice leaves by itself.
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('capsule_notice_$variant.png'),
        );
        nexHideBanner();
        await tester.pumpAndSettle(const Duration(seconds: 1));
      });

      testWidgets('note detail sheet $variant', (tester) async {
        await _frame(tester, const Size(420, 760));
        final harness = await NexTestHarness.create(name: 'nex_golden_');
        addTearDown(harness.dispose);
        final captured = await harness.services.captureText(
          rtl ? persian : english,
        );
        // Pinned in the database itself: the sheet reads the note back.
        final db = NexDatabase.open(harness.dbPath);
        db.db.execute('UPDATE notes SET created_at = ?, updated_at = ?', [
          written.toIso8601String(),
          written.toIso8601String(),
        ]);
        db.close();
        await tester.pumpWidget(
          _app(
            locale: locale,
            dark: dark,
            child: NoteDetailSheet(
              services: harness.services,
              noteId: captured!.id,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('note_detail_$variant.png'),
        );
      });
    }
  }

  // Every palette, on the card that carries the most of it.
  for (final preset in nexThemePresets) {
    for (final dark in [false, true]) {
      testWidgets('palette ${preset.id} ${dark ? 'dark' : 'light'}', (
        tester,
      ) async {
        await _frame(tester, const Size(420, 330));
        await tester.pumpWidget(
          _app(
            locale: const Locale('en'),
            dark: dark,
            preset: preset.id,
            child: Column(
              children: [
                NoteCard(note: note('a', NoteType.text, english), onTap: () {}),
                NoteCard(
                  note: note(
                    'b',
                    NoteType.checklist,
                    '- [x] Bread\n- [ ] Milk\n- [ ] Eggs',
                  ),
                  onTap: () {},
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            'palette_${preset.id}_${dark ? 'dark' : 'light'}.png',
          ),
        );
      });
    }
  }
}

Future<void> _frame(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _app({
  required Locale locale,
  required bool dark,
  required Widget child,
  String preset = 'classic',
}) {
  final font = nexFontFor(locale);
  final theme = nexApplyThemePreset(
    dark ? nexDarkTheme(fontFamily: font) : nexLightTheme(fontFamily: font),
    preset,
    null,
  );
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: locale,
    theme: theme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SafeArea(child: child)),
  );
}

/// The app's own faces, and Material's icons, instead of the test font's
/// boxes — a picture of boxes cannot show a Persian line laid out wrong.
Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      loader.addFont(
        Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
      );
    }
    await loader.load();
  }

  await load(nexLatinFont, ['assets/fonts/Inter-subset.ttf']);
  await load(nexPersianFont, ['assets/fonts/VazirmatnVariable.ttf']);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
  await load('MaterialIcons', [
    p.join(
      flutterRoot,
      'bin',
      'cache',
      'artifacts',
      'material_fonts',
      'MaterialIcons-Regular.otf',
    ),
  ]);
}

/// Passes a picture that differs by a sliver of anti-aliasing, and nothing
/// more: 0.3% of the pixels, which a moved icon or a flipped line exceeds
/// many times over.
class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.testFile);

  static const _tolerance = 0.003;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= _tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
