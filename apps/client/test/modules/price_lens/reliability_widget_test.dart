import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/price_lens/option_editor.dart';
import 'package:nex_client/modules/price_lens/options.dart';
import 'package:nex_client/modules/price_lens/rational.dart';
import 'package:nex_client/modules/price_lens/price_lens_screen.dart';
import 'lens_test_store.dart';
import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness h;
  late LensFaultStore store;
  setUp(() async {
    h = await NexTestHarness.create(name: 'lens_widgets_');
    store = LensFaultStore(h.services);
  });
  tearDown(() => h.dispose());
  PriceOption offer({int count = 1, int? paid, int? fixed, int? shipping}) =>
      PriceOption(
        id: 'o',
        label: 'Rice',
        priceMinor: 1500,
        currency: 'IRR',
        quantity: const Fraction(1),
        unitKey: 'kg',
        packageCount: count,
        paidCount: paid,
        discount: fixed == null ? DiscountKind.none : DiscountKind.fixed,
        discountMinor: fixed,
        shippingMinor: shipping,
        date: DateTime(2026, 10, 1),
      );
  Future<void> host(
    WidgetTester tester,
    Widget home, {
    bool compact = false,
    bool fa = false,
    bool dark = false,
  }) async {
    tester.view.physicalSize = compact
        ? const Size(320, 480)
        : const Size(700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(fa ? 'fa' : 'en'),
        theme: dark ? nexDarkTheme() : nexLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(compact ? 2 : 1),
            disableAnimations: compact,
          ),
          child: child!,
        ),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> editor(
    WidgetTester tester,
    PriceOption option,
    ValueChanged<PriceOption> save, {
    bool compact = false,
    bool fa = false,
    bool dark = false,
  }) async {
    await host(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                showOptionEditor(context, existing: option, onSave: save),
            child: const Text('Open'),
          ),
        ),
      ),
      compact: compact,
      fa: fa,
      dark: dark,
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Finder priceField() => find.descendant(
    of: find.byKey(const ValueKey('lens-price')),
    matching: find.byType(TextField),
  );
  testWidgets(
    'Rial/Toman switch reexpresses price, fixed discount and shipping',
    (tester) async {
      PriceOption? saved;
      await editor(tester, offer(fixed: 500, shipping: 200), (o) => saved = o);
      await tester.ensureVisible(find.text('Tomans'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tomans'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(priceField()).controller!.text, '1.5');
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('lens-discount-value')),
            )
            .controller!
            .text,
        '0.5',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('lens-shipping')))
            .controller!
            .text,
        '0.2',
      );
      await tester.tap(find.byKey(const ValueKey('lens-save')));
      await tester.pumpAndSettle();
      expect(saved!.priceMinor, 1500);
      expect(saved!.discountMinor, 500);
      expect(saved!.shippingMinor, 200);
      expect(await store.list('comparison'), isEmpty);
      expect(await store.list('memory'), isEmpty);
    },
  );
  testWidgets('fixed discount over total cannot save and keeps typed text', (
    tester,
  ) async {
    PriceOption? saved;
    await editor(tester, offer(fixed: 500), (o) => saved = o);
    await tester.enterText(
      find.byKey(const ValueKey('lens-discount-value')),
      '16',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('lens-save')));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('lens-discount-value')))
          .controller!
          .text,
      '16',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('received count cannot silently hide too many paid packages', (
    tester,
  ) async {
    PriceOption? saved;
    await editor(tester, offer(count: 3, paid: 2), (o) => saved = o);
    await tester.enterText(find.byKey(const ValueKey('lens-count')), '1');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lens-paid-count')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lens-save')));
    await tester.pumpAndSettle();
    expect(saved, isNull);
  });
  for (final fa in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets('offer editor 320x480 with 2x text, fa:$fa dark:$dark', (
        tester,
      ) async {
        await editor(
          tester,
          offer(count: 3, paid: 2, fixed: 500, shipping: 200),
          (_) {},
          compact: true,
          fa: fa,
          dark: dark,
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const ValueKey('lens-date')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets('failed memory save keeps offers and retry uses one record', (
    tester,
  ) async {
    await store.put(
      'comparison',
      'c',
      SavedComparison(
        id: 'c',
        date: DateTime(2026, 10, 1),
        options: [offer(), offer()],
      ).toBody(),
    );
    await host(tester, PriceLensScreen(store: store));
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved comparisons'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    store.failAfterKind = 'memory';
    await tester.tap(find.byTooltip('Remember this price').first);
    await tester.pumpAndSettle();
    for (
      var i = 0;
      i < 20 &&
          find
              .text('Could not save. Your offers are still here.')
              .evaluate()
              .isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }
    expect(
      find.text('Could not save. Your offers are still here.'),
      findsOneWidget,
    );
    expect(await store.list('memory'), isEmpty);
    await tester.tap(find.byTooltip('Remember this price').first);
    await tester.pumpAndSettle();
    for (var i = 0; i < 20 && (await store.list('memory')).isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }
    expect(await store.list('memory'), hasLength(1));
    expect(find.text('Rice'), findsAtLeast(2));
    expect(tester.takeException(), isNull);
  });
}
