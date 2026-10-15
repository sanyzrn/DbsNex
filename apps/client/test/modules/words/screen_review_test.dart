import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/words/words_screen.dart';
import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness harness;
  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_words_capture_');
  });
  tearDown(() => harness.dispose());
  for (final persian in [true, false]) {
    for (final compact in [false, true]) {
      testWidgets(
        'actual main screen in ${persian ? 'Persian dark' : 'English light'}, compact:$compact',
        (tester) async {
          tester.view.physicalSize = compact
              ? const Size(320, 480)
              : const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final store = NexModuleStore(harness.services, 'words');
          final now = DateTime.now();
          String day(int offset) {
            final d = DateTime(now.year, now.month, now.day + offset);
            return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          }

          await store.put('card', 'w1', {
            'schema': 2,
            'headword': 'resilient',
            'language': 'English',
            'meaning': persian
                ? 'تاب‌آور؛ کسی که پس از دشواری دوباره توان پیدا می‌کند'
                : 'Able to recover after difficulties.',
            'example': 'Small steps build a resilient routine.',
            'tag': persian ? 'کتاب' : 'Reading',
            'createdAt': now.toUtc().toIso8601String(),
            'reps': 2,
            'step': 1,
            'due': day(0),
            'lastReview': DateTime(
              now.year,
              now.month,
              now.day - 3,
            ).toUtc().toIso8601String(),
            'introducedOn': day(-10),
          });
          await store.put('card', 'w2', {
            'schema': 2,
            'headword': 'flâner',
            'language': 'French',
            'meaning': persian
                ? 'قدم‌زدن بی‌شتاب'
                : 'To stroll without hurrying.',
            'tag': persian ? 'سفر' : 'Travel',
            'createdAt': now.toUtc().toIso8601String(),
          });
          await store.put('card', 'w3', {
            'schema': 2,
            'headword': persian ? 'آرامش' : 'Stillness',
            'language': persian ? 'فارسی' : 'English',
            'meaning': persian ? 'آسودگی و سکون' : 'A moment of calm.',
            'paused': true,
            'createdAt': now.toUtc().toIso8601String(),
          });
          final boundary = GlobalKey();
          await tester.runAsync(() async {
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
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: Locale(persian ? 'fa' : 'en'),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(compact ? 2 : 1),
                    disableAnimations: compact,
                  ),
                  child: child!,
                ),

                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: persian
                    ? nexDarkTheme(fontFamily: 'Vazirmatn')
                    : nexLightTheme(fontFamily: 'Inter'),
                home: WordsScreen(store: store),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          const output = String.fromEnvironment('NEX_CAPTURE');
          if (output.isNotEmpty && !compact) {
            await tester.runAsync(() async {
              final image =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final dir = Directory(output)..createSync(recursive: true);
              await File(
                '${dir.path}/words_${persian ? 'fa_dark' : 'en_light'}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
