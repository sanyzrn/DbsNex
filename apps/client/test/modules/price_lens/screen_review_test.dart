import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/price_lens/price_lens_screen.dart';

import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness harness;
  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_price_lens_capture_');
  });
  tearDown(() => harness.dispose());
  for (final persian in [true, false]) {
    for (final dark in [false, true]) {
      for (final compact in [false, true]) {
        testWidgets(
          'main, products, history and shopping fa:$persian dark:$dark compact:$compact',
          (tester) async {
            tester.view.physicalSize = compact
                ? const Size(320, 480)
                : const Size(390, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final store = NexModuleStore(harness.services, 'price_lens');
            final now = DateTime.now();
            Map<String, Object?> offer(
              String label,
              int price,
              int q,
              String unit,
            ) => {
              'label': label,
              'price': price,
              'currency': 'IRR',
              'quantity': q,
              'unit': unit,
              'packageCount': 1,
              'discount': 'none',
            };
            await store.put('comparison', 'demo', {
              'date': now.toIso8601String(),
              'options': [
                offer(
                  persian ? 'برنج ۷۵۰ گرمی' : 'Rice 750g',
                  9000000,
                  750,
                  'g',
                ),
                offer(
                  persian ? 'برنج یک کیلویی' : 'Rice 1kg',
                  11500000,
                  1,
                  'kg',
                ),
              ],
              'commonUnit': 'kg',
            });
            final product = persian ? 'برنج طارم' : 'Tarom rice';
            for (final (id, date, qty) in [
              ('old', '2026-10-01', 1000),
              ('new', '2026-10-15', 750),
            ]) {
              await store.put('memory', id, {
                'schema': 3,
                'label': product,
                'productName': product,
                'priceRial': 90000,
                'currency': 'IRR',
                'quantity': qty,
                'unit': 'g',
                'date': date,
                'person': {
                  'name': persian ? 'فروشگاه محله' : 'Neighbourhood shop',
                },
              });
            }
            final boundary = GlobalKey();
            await tester.runAsync(() async {
              final inter = FontLoader('Inter')
                ..addFont(rootBundle.load('assets/fonts/Inter-subset.ttf'));
              final vazir = FontLoader(
                'Vazirmatn',
              )..addFont(rootBundle.load('assets/fonts/VazirmatnVariable.ttf'));
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

                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  theme: dark
                      ? nexDarkTheme(fontFamily: 'Vazirmatn')
                      : nexLightTheme(fontFamily: 'Inter'),
                  home: PriceLensScreen(store: store),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.tap(
              find.byTooltip(persian ? 'گزینه‌های بیشتر' : 'More actions'),
            );
            await tester.pumpAndSettle();
            await tester.tap(
              find.text(persian ? 'مقایسه‌های ذخیره‌شده' : 'Saved comparisons'),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text(persian ? 'باز کردن' : 'Open'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            const output = String.fromEnvironment('NEX_CAPTURE');
            Future<void> capture(String name) async {
              if (output.isEmpty || compact || dark != persian) return;
              await tester.runAsync(() async {
                final frame =
                    await (boundary.currentContext!.findRenderObject()!
                            as RenderRepaintBoundary)
                        .toImage();
                final bytes = await frame.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final dir = Directory(output)..createSync(recursive: true);
                await File(
                  '${dir.path}/price_lens_${persian ? 'fa_dark' : 'en_light'}_$name.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                frame.dispose();
              });
            }

            await capture('compare');
            if (!compact) {
              await tester.ensureVisible(
                find.byKey(const ValueKey('lens-hero')),
              );
              await tester.pumpAndSettle();
              await capture('result');
            }
            await tester.tap(find.text(persian ? 'کالاهای من' : 'My products'));
            await tester.pumpAndSettle();
            await capture('products');
            expect(tester.takeException(), isNull);
            await tester.scrollUntilVisible(
              find.text(product),
              200,
              scrollable: find
                  .descendant(
                    of: find.byKey(const ValueKey('lens-product-list')),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text(product));
            await tester.pumpAndSettle();
            await capture('history');
            expect(tester.takeException(), isNull);
            await tester
                .state<NavigatorState>(find.byType(Navigator).first)
                .maybePop();
            await tester.pumpAndSettle();
            await tester.tap(
              find.text(persian ? 'فهرست خرید' : 'Shopping list'),
            );
            await tester.pumpAndSettle();
            await capture('shopping');
            expect(tester.takeException(), isNull);
            await tester.tap(find.text(persian ? 'مقایسه' : 'Compare'));
            await tester.pumpAndSettle();
            if (compact) {
              await tester.tap(find.byKey(const ValueKey('lens-add')));
              await tester.pumpAndSettle();
              await tester.enterText(
                find.byKey(const ValueKey('lens-label')),
                persian ? '۱۲٫۵' : '12.5',
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
