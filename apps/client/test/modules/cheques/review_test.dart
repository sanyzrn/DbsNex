import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/cheques/home.dart';
import 'package:nex_client/modules/cheques/detail.dart';
import 'package:nex_client/modules/cheques/editor.dart';
import 'package:nex_client/modules/cheques/event_editor.dart';
import 'package:nex_client/modules/cheques/repository.dart';
import 'package:nex_client/modules/cheques/values.dart';

import '../../support/nex_harness.dart';

import 'package:nex_client/modules/cheques/plan_repository.dart';
import 'package:nex_client/modules/cheques/plan_editor.dart';
import 'package:nex_client/modules/cheques/plans_page.dart';
import 'package:nex_client/modules/cheques/privacy.dart';

import 'plan_test.dart' show planRaw;
import 'fixtures.dart';
import 'widget_test.dart' show settleCheque, reachCheque;

void main() {
  for (final fa in [false, true]) {
    for (final dark in [false, true]) {
      for (final compact in [false, true]) {
        for (final scene in [
          'follow',
          'all',
          'outlook',
          'detail',
          'editor',
          'event',
          'empty',
          'plans',
          'planEditor',
          'month',
        ]) {
          testWidgets('$scene fa:$fa dark:$dark compact:$compact', (t) async {
            final h = await NexTestHarness.create(name: 'cheque_review_');
            addTearDown(h.dispose);
            t.view.physicalSize = compact
                ? const Size(320, 640)
                : const Size(390, 844);
            t.view.devicePixelRatio = 1;
            addTearDown(t.view.reset);
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
            final store = NexModuleStore(h.services, 'cheques'),
                repo = ChequeRepository(store);
            final now = DateTime.now();
            final c = await repo.save(
              'sample',
              null,
              chequeRaw(
                amount: '125000000',
                date: chequeDayKey(DateTime(now.year, now.month, now.day + 2)),
                party: fa
                    ? 'فروشگاه آفتاب — خرید تجهیزات'
                    : 'Sunrise shop — equipment',
              ),
            );
            if (scene != 'empty') {
              await repo.save(
                'incoming',
                null,
                chequeRaw(
                  direction: 'incoming',
                  amount: '80000000',
                  date: chequeDayKey(
                    DateTime(now.year, now.month, now.day + 6),
                  ),
                  party: fa ? 'مشتری نمونه' : 'Sample customer',
                ),
              );
              await repo.save(
                'guarantee',
                null,
                chequeRaw(
                  purpose: 'guarantee',
                  amount: '500000000',
                  date: chequeDayKey(
                    DateTime(now.year, now.month, now.day + 10),
                  ),
                  party: fa ? 'ضمانت قرارداد' : 'Contract guarantee',
                ),
              );
            } else {
              await repo.delete(c);
            }
            final planRepo = PlanRepository(store);
            final plan = ['plans', 'planEditor', 'month'].contains(scene)
                ? await t.runAsync(
                    () => planRepo.save('plan', null, {
                      ...planRaw(),
                      'first': chequeDayKey(DateTime.now()),
                    }),
                  )
                : null;
            final boundary = GlobalKey();
            final page = switch (scene) {
              'plans' => PlansPage(store: store),
              'planEditor' => PlanEditor(repo: planRepo, plan: plan),
              'detail' => ChequeDetail(repo: repo, id: c.id),
              'editor' => ChequeEditor(repo: repo, cheque: c),
              'event' => ChequeEventEditor(
                repo: repo,
                cheque: c,
                payment: true,
              ),
              _ => ChequeHome(store: store),
            };
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
                  home: ChequePrivacy(child: page),
                ),
              ),
            );
            await settleCheque(t);
            if (scene == 'all' || scene == 'outlook' || scene == 'month') {
              await t.tap(
                find.text(
                  fa
                      ? (scene == 'month'
                            ? 'ماه شمسی'
                            : scene == 'all'
                            ? 'همهٔ چک‌ها'
                            : 'چشم‌انداز')
                      : (scene == 'month'
                            ? 'Jalali month'
                            : scene == 'all'
                            ? 'All cheques'
                            : 'Outlook'),
                ),
              );
              await t.pumpAndSettle();
            }
            if (scene == 'editor') {
              await reachCheque(
                t,
                find.text(fa ? 'بانک / شعبه' : 'Bank / branch'),
              );
            }
            if (scene == 'event') {
              await t.enterText(
                find.byKey(const ValueKey('cheque-event-amount')),
                fa ? '۱۲۵۰۰۰۰' : '1250000',
              );
            }
            expect(t.takeException(), isNull);
            const out = String.fromEnvironment('NEX_CAPTURE');
            if (out.isNotEmpty && !compact && fa == dark) {
              await t.runAsync(() async {
                final img =
                    await (boundary.currentContext!.findRenderObject()!
                            as RenderRepaintBoundary)
                        .toImage();
                final bytes = await img.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                Directory(out).createSync(recursive: true);
                await File(
                  '$out/cheque_${scene}_${fa ? 'fa_dark' : 'en_light'}.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                img.dispose();
              });
            }
            // Scroll through long forms/details to exercise the lower controls at 2x text.
            if (scene == 'editor' || scene == 'event') {
              await reachCheque(
                t,
                find.byKey(
                  ValueKey(
                    scene == 'editor' ? 'cheque-save' : 'cheque-event-save',
                  ),
                ),
              );
            }
            if (scene == 'detail') {
              await reachCheque(
                t,
                find.text(fa ? 'ثبت تغییر وضعیت' : 'Record a status change'),
              );
            }
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
            await settleCheque(t);
          });
        }
      }
    }
  }
}
