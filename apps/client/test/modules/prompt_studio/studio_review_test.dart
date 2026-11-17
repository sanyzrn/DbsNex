import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/prompt_studio/prompt_model.dart';
import 'package:nex_client/modules/prompt_studio/studio_editor.dart';
import 'package:nex_client/modules/prompt_studio/studio_home.dart';
import 'package:nex_client/modules/prompt_studio/studio_repository.dart';
import 'package:nex_client/modules/prompt_studio/studio_workbench.dart';

import '../../support/nex_harness.dart';
import 'studio_widget_test.dart' show settleStudio, revealStudio;

void main() {
  for (final fa in [true, false]) {
    for (final dark in [true, false]) {
      for (final compact in [true, false]) {
        for (final scene in ['home', 'editor', 'fill']) {
          testWidgets('$scene fa:$fa dark:$dark compact:$compact', (t) async {
            final h = await NexTestHarness.create(name: 'prompt_render_');
            addTearDown(h.dispose);
            t.view.physicalSize = compact
                ? const Size(320, 640)
                : const Size(390, 844);
            t.view.devicePixelRatio = 1;
            addTearDown(t.view.reset);
            final store = NexModuleStore(h.services, 'prompt_studio');
            final body = <String, Object?>{
              'v': 1,
              'title': fa
                  ? 'از ایده تا شرح طراحی'
                  : 'From idea to design brief',
              'body': fa
                  ? 'برای {{مخاطب}} یک شرح طراحی دربارهٔ {{موضوع}} بنویس.\nخروجی: هدف، پیام اصلی و سه مسیر بصری.'
                  : 'Write a design brief about {{topic}} for {{audience}}.\nInclude a goal, a core message and three visual directions.',
              'category': fa ? 'طراحی' : 'Design',
              'favorite': true,
            };
            await store.put('entry', 'p', body);
            await store.put('entry', 'p2', {
              'v': 1,
              'title': fa ? 'بازبینی آرام و دقیق کد' : 'A careful code review',
              'body': '{{code}}',
              'category': fa ? 'برنامه‌نویسی' : 'Development',
            });
            await store.put('entry', 'b', {
              'v': 1,
              'title': fa ? 'قانون پاسخ روشن' : 'Clear answers',
              'body': fa
                  ? 'فرض‌ها را جدا از واقعیت‌ها بنویس.'
                  : 'Separate assumptions from facts.',
              'block': true,
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
            final repo = StudioRepository(store);
            final entry = PromptEntry('p', body);
            final boundary = GlobalKey();
            await t.pumpWidget(
              RepaintBoundary(
                key: boundary,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  locale: Locale(fa ? 'fa' : 'en'),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  theme: dark
                      ? nexSoftDarkTheme(fontFamily: fa ? 'Vazirmatn' : 'Inter')
                      : nexSoftLightTheme(
                          fontFamily: fa ? 'Vazirmatn' : 'Inter',
                        ),
                  builder: (c, child) => MediaQuery(
                    data: MediaQuery.of(c).copyWith(
                      textScaler: TextScaler.linear(compact ? 2 : 1),
                      disableAnimations: compact,
                    ),
                    child: child!,
                  ),
                  home: scene == 'home'
                      ? StudioHome(store: store)
                      : scene == 'editor'
                      ? StudioEditor(repo: repo, entry: entry)
                      : StudioWorkbench(repo: repo, entry: entry),
                ),
              ),
            );
            await settleStudio(t);
            if (scene == 'fill') {
              for (final key in PromptTemplate(entry.body).slots) {
                final field = find.byKey(ValueKey('fill-$key'));
                await revealStudio(t, field);
                await t.enterText(
                  field,
                  fa
                      ? (key == 'موضوع' ? 'بسته‌بندی چای' : 'دوستداران طراحی')
                      : (key == 'topic' ? 'tea packaging' : 'design lovers'),
                );
              }
              await t.pumpAndSettle();
              await revealStudio(t, find.byType(NexModuleHero));
            }
            expect(t.takeException(), isNull);
            const output = String.fromEnvironment('NEX_CAPTURE');
            if (output.isNotEmpty && !compact && fa == dark) {
              await t.runAsync(() async {
                final image =
                    await (boundary.currentContext!.findRenderObject()!
                            as RenderRepaintBoundary)
                        .toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                Directory(output).createSync(recursive: true);
                await File(
                  '$output/prompt_${scene}_${fa ? 'fa_dark' : 'en_light'}.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            if (scene == 'editor') {
              await revealStudio(t, find.byKey(const ValueKey('studio-save')));
              expect(t.takeException(), isNull);
            }
            if (scene == 'fill') {
              await revealStudio(
                t,
                find.byKey(const ValueKey('studio-preview')),
              );
              expect(t.takeException(), isNull);
            }
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
          });
        }
      }
    }
  }
}
