import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/words/words_review_page.dart';
import 'package:nex_client/modules/words/words_screen.dart';

import '../../support/nex_harness.dart';

/// The captures kept in `lib/modules/words/review/`, taken from the real
/// screens: the home page with the goal and a deck, and a typed answer
/// turned over. Persian dark and English light, as the review asks.
///
/// `flutter test test/modules/words/words_upgrade_capture_test.dart
///   --dart-define=NEX_CAPTURE=lib/modules/words/review`
void main() {
  late NexTestHarness harness;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_words_upgrade_shot_');
  });

  tearDown(() => harness.dispose());

  String day(int offset) {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day + offset);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  String meaningOf(bool persian) => persian
      ? 'تاب‌آور؛ کسی که پس از دشواری دوباره توان پیدا می‌کند'
      : 'Able to recover after difficulties.';

  Future<NexModuleStore> seed({required bool persian}) async {
    final store = NexModuleStore(harness.services, 'words');
    await store.put('deck', 'd1', {
      'schema': 1,
      'name': persian ? 'کتاب کوچک' : 'The Little Prince',
      'createdAt': '2026-11-01T09:00:00',
    });
    await store.put('card', 'w1', {
      'schema': 2,
      'headword': 'resilient',
      'language': 'English',
      'meaning': meaningOf(persian),
      'example': 'Small steps build a resilient routine.',
      'tag': persian ? 'کتاب' : 'Reading',
      'createdAt': '2026-11-02T09:00:00',
      'reps': 3,
      'step': 1,
      'due': day(0),
      'lastReview': '${day(-2)}T09:00:00',
      'introducedOn': day(-10),
      'deckId': 'd1',
      'log': [
        {'at': '${day(-10)}T09:00:00', 'g': 'good'},
        {'at': '${day(-4)}T09:00:00', 'g': 'good'},
        {'at': '${day(0)}T09:30:00', 'g': 'again'},
      ],
    });
    await store.put('card', 'w2', {
      'schema': 2,
      'headword': 'flâner',
      'language': 'French',
      'meaning': persian ? 'قدم‌زدن بی‌شتاب' : 'To stroll without hurrying.',
      'tag': persian ? 'سفر' : 'Travel',
      'createdAt': '2026-11-03T09:00:00',
      'deckId': 'd1',
    });
    await store.put('card', 'w3', {
      'schema': 2,
      'headword': persian ? 'آرامش' : 'Stillness',
      'language': persian ? 'فارسی' : 'English',
      'meaning': persian ? 'آسودگی و سکون' : 'A moment of calm.',
      'createdAt': '2026-11-04T09:00:00',
    });
    return store;
  }

  Future<void> loadFonts(WidgetTester tester) => tester.runAsync(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-subset.ttf'));
    final vazir = FontLoader('Vazirmatn')
      ..addFont(rootBundle.load('assets/fonts/VazirmatnVariable.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    await inter.load();
    await vazir.load();
  });

  Widget host({required bool persian, required Widget home}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: Locale(persian ? 'fa' : 'en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: persian
        ? nexDarkTheme(fontFamily: 'Vazirmatn')
        : nexLightTheme(fontFamily: 'Inter'),
    home: home,
  );

  Future<void> capture(
    WidgetTester tester,
    GlobalKey boundary,
    String name,
  ) async {
    const output = String.fromEnvironment('NEX_CAPTURE');
    if (output.isEmpty) return;
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory(output)..createSync(recursive: true);
      await File('${dir.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final persian in [false, true]) {
    final suffix = persian ? 'fa_dark' : 'en_light';

    testWidgets('home page, $suffix', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await loadFonts(tester);
      final store = await seed(persian: persian);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: host(
            persian: persian,
            home: WordsScreen(store: store),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, boundary, 'words_home_$suffix');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a typed answer turned over, $suffix', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await loadFonts(tester);
      final store = await seed(persian: persian);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: host(
            persian: persian,
            home: WordsReviewPage(store: store),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('words-exercise')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('words-exercise-type')));
      await tester.pumpAndSettle();
      // The first card is the due one; its own meaning is the right
      // answer, typed loosely (spacing and case are forgiven).
      await tester.enterText(
        find.byKey(const ValueKey('words-typed-answer')),
        meaningOf(persian),
      );
      await tester.tap(find.byKey(const ValueKey('words-typed-check')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, boundary, 'words_practice_$suffix');
      await tester.pumpWidget(const SizedBox());
    });
  }
}
