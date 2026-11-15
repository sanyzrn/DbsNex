import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/smoke_free/quit_home_screen.dart';
import 'package:nex_client/modules/smoke_free/quit_model.dart';
import 'package:nex_client/modules/smoke_free/smoke_free_screen.dart';
import 'package:nex_client/modules/smoke_free/sos_sheet.dart';

import '../../support/nex_harness.dart';
import 'quit_details.dart';

void main() {
  late NexTestHarness harness;
  setUp(
    () async => harness = await NexTestHarness.create(name: 'quit_review_'),
  );
  tearDown(() => harness.dispose());
  for (final persian in [true, false]) {
    for (final dark in [true, false]) {
      for (final compact in [false, true]) {
        for (final scene in ['home', 'detail', 'help']) {
          testWidgets('$scene fa:$persian dark:$dark compact:$compact', (
            t,
          ) async {
            t.view.physicalSize = compact
                ? const Size(320, 640)
                : const Size(390, 844);
            t.view.devicePixelRatio = 1;
            addTearDown(t.view.resetPhysicalSize);
            addTearDown(t.view.resetDevicePixelRatio);
            final store = NexModuleStore(harness.services, 'smoke_free');
            final now = DateTime.now();
            final body = <String, Object?>{
              'v': 3,
              'startedAt': DateTime(
                now.year,
                now.month,
                now.day - 14,
              ).toIso8601String(),
              'cigarettesPerDay': 10,
              'pricePerPackMinor': 200000,
              'currency': 'IRR',
              'perPack': 20,
              'why': persian
                  ? 'برای نفس راحت‌تر و وقت بیشتر'
                  : 'More time for myself',
              'nextStep': persian
                  ? 'اگر بعد از چای هوس کردم، دو دقیقه قدم می‌زنم.'
                  : 'After tea, I will walk for two minutes.',
            };
            await store.put('quit', 'q', body);
            if (scene == 'home') {
              await store.put('quit', 'future', {
                'habit': 'sugar',
                'startedAt': DateTime(
                  now.year,
                  now.month,
                  now.day + 3,
                ).toIso8601String(),
              });
            }
            await store.put('craving', 'c1', {
              'at': now.toIso8601String(),
              'intensity': 3,
              'afterIntensity': 1,
              'triggers': ['coffee'],
              'coping': 'walk',
              'note': '',
            });
            await store.put('craving', 'c2', {
              'at': DateTime(
                now.year,
                now.month,
                now.day - 1,
              ).toIso8601String(),
              'intensity': 2,
              'triggers': ['coffee'],
              'coping': 'water',
              'note': '',
            });
            await t.runAsync(() async {
              for (final pair in [
                ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
                ('Inter', 'assets/fonts/Inter-subset.ttf'),
                ('Vazirmatn', 'assets/fonts/VazirmatnVariable.ttf'),
              ]) {
                await (FontLoader(
                  pair.$1,
                )..addFont(rootBundle.load(pair.$2))).load();
              }
            });
            final boundary = GlobalKey();
            await t.pumpWidget(
              RepaintBoundary(
                key: boundary,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  locale: Locale(persian ? 'fa' : 'en'),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  theme: dark
                      ? nexSoftDarkTheme(
                          fontFamily: persian ? 'Vazirmatn' : 'Inter',
                        )
                      : nexSoftLightTheme(
                          fontFamily: persian ? 'Vazirmatn' : 'Inter',
                        ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(compact ? 2 : 1),
                      disableAnimations: compact,
                    ),
                    child: child!,
                  ),
                  home: scene == 'home'
                      ? QuitHomeScreen(store: store)
                      : scene == 'detail'
                      ? SmokeFreeScreen(store: store)
                      : Scaffold(
                          body: Builder(
                            builder: (context) => TextButton(
                              onPressed: () => showSosSheet(
                                context,
                                store,
                                QuitAttempt.fromBody('q', body),
                              ),
                              child: const Text('Open test scene'),
                            ),
                          ),
                        ),
                ),
              ),
            );
            await t.pumpAndSettle();
            if (scene == 'help') {
              await t.tap(find.text('Open test scene'));
              await t.pumpAndSettle();
            }
            expect(t.takeException(), isNull);
            const output = String.fromEnvironment('NEX_CAPTURE');
            Future<void> capture(String suffix) async {
              if (output.isEmpty || compact || persian != dark) return;
              await t.runAsync(() async {
                final image =
                    await (boundary.currentContext!.findRenderObject()!
                            as RenderRepaintBoundary)
                        .toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final dir = Directory(output)..createSync(recursive: true);
                await File(
                  '${dir.path}/quit_${scene}_${persian ? 'fa_dark' : 'en_light'}$suffix.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }

            await capture('');
            if (scene == 'detail') {
              await revealQuit(
                t,
                find.text(persian ? '۳۰ روز اخیر شما' : 'Your last 30 days'),
              );
              expect(t.takeException(), isNull);
              await capture('_insights');
              await revealQuit(
                t,
                find.text(persian ? 'پنج هفتهٔ اخیر' : 'The last five weeks'),
              );
              expect(t.takeException(), isNull);
              await capture('_calendar');
            } else if (scene == 'help') {
              await revealQuit(t, find.text(persian ? 'مکث' : 'Wait'));
              await t.tap(find.text(persian ? 'مکث' : 'Wait'));
              await t.pumpAndSettle();
              await revealQuit(t, find.byKey(const ValueKey('sos-wait-start')));
              expect(t.takeException(), isNull);
              await capture('_pause');
            }
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
          });
        }
      }
    }
  }
}
