import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/gold/gold_math.dart';
import 'package:nex_client/modules/gold/gold_models.dart';
import 'package:nex_client/modules/gold/gold_format.dart';
import 'package:nex_client/modules/gold/gold_screen.dart';
import 'package:nex_client/modules/gold/gold_form.dart';
import 'package:nex_client/modules/gold/gold_quotes_page.dart';
import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness harness;
  setUp(
    () async => harness = await NexTestHarness.create(name: 'gold_regression_'),
  );
  tearDown(() => harness.dispose());
  Widget host(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
  GoldQuote example() {
    const input = GoldInput(
      weightMg: 3000,
      finenessPpt: 750,
      rateCentiPerG: 1000000000,
      rateRefPpt: 750,
      makingPercentBp: 1000,
    );
    final result = GoldMath.calculate(input);
    return GoldQuote(
      id: 'old',
      title: 'Original',
      shop: 'Shop',
      savedAtIso: '2026-10-12T12:00:00',
      quoteDateIso: '2026-10-12',
      notes: 'Note',
      input: input,
      metalValueRial: result.metalValueRial,
      makingChargeRial: result.makingChargeRial,
      sellerProfitRial: result.sellerProfitRial,
      commissionRial: result.commissionRial,
      vatBaseRial: result.vatBaseRial,
      vatRial: result.vatRial,
      extrasRial: result.extrasRial,
      estimatedTotalRial: result.estimatedTotalRial,
    );
  }

  Future<void> reveal(
    WidgetTester tester,
    String key, {
    bool up = false,
  }) async {
    await tester.scrollUntilVisible(
      find.byKey(ValueKey(key)),
      up ? -400 : 400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  test('a fractional negative and malformed sign cannot turn positive', () {
    expect(parseScaled('-0.5', 2), -50);
    expect(parseScaled('−۰٫۵', 2), -50);
    expect(parseScaled('١٢٫٥', 2), 1250);
    expect(parseScaled('1.-5', 2), isNull);
    expect(parseScaled('99999999999999999999999999999999', 2), isNull);
  });
  test('all editable scaled values round-trip without symbols', () {
    for (final scale in [1, 2, 3]) {
      for (final value in [1, 7, 725, 3000, 1000000000]) {
        expect(parseScaled(inputScaled(value, scale), scale), value);
      }
    }
  });
  test('large percentage intermediates use exact arithmetic', () {
    final result = GoldMath.calculate(
      const GoldInput(
        weightMg: 1000,
        finenessPpt: 750,
        rateCentiPerG: 10000,
        rateRefPpt: 750,
        makingMode: GoldMakingMode.fixed,
        makingFixedRial: 100000000000000,
        profitBp: 99999,
        vatBp: 0,
      ),
    );
    expect(result.sellerProfitRial, 999990000010000);
    expect(result.estimatedTotalRial, 1099990000011000);
  });
  test('combined values beyond exact storage are rejected before display', () {
    const input = GoldInput(
      weightMg: 10000000,
      finenessPpt: 999,
      rateCentiPerG: 10000000000,
      rateRefPpt: 999,
      makingPercentBp: 99999,
      profitBp: 99999,
      vatBp: 99999,
      commissionRial: 1000000000000000,
      extras: [('stones', 1000000000000000)],
    );
    expect(
      input.problems().map((p) => p.field),
      contains(GoldProblemField.total),
    );
    expect(() => GoldMath.calculate(input), throwsStateError);
  });
  test('a rounded-zero estimate does not divide by zero for a quote', () {
    final result = GoldMath.calculate(
      const GoldInput(
        weightMg: 1,
        finenessPpt: 750,
        rateCentiPerG: 1,
        rateRefPpt: 750,
        profitBp: 0,
        vatBp: 0,
        shopQuoteRial: 100,
      ),
    );
    expect(result.estimatedTotalRial, 0);
    expect(result.quoteDiffRial, 100);
    expect(result.quoteDiffHundredthsPct, isNull);
  });
  test('alternative bases are explicit and stored', () {
    const input = GoldInput(
      weightMg: 1000,
      finenessPpt: 750,
      rateCentiPerG: 1000000,
      rateRefPpt: 750,
      makingMode: GoldMakingMode.fixed,
      makingFixedRial: 10000,
      commissionRial: 5000,
      profitBp: 700,
      vatBp: 1000,
      profitBase: GoldProfitBase.services,
      commissionTaxable: false,
    );
    final result = GoldMath.calculate(input);
    expect(result.sellerProfitRial, 1050);
    expect(result.vatBaseRial, 11050);
    expect(result.vatRial, 1105);
    final original = example();
    final restored = GoldQuote.fromRecord(
      'old',
      original.withRecalculated(input, result).toRecord(),
    );
    expect(restored.input.profitBase, GoldProfitBase.services);
    expect(restored.input.commissionTaxable, isFalse);
  });
  test('corrupt nonfinite metadata never throws', () {
    for (final invalid in [
      double.nan,
      double.infinity,
      -double.infinity,
      3.5,
    ]) {
      final quote = GoldQuote.fromRecord('x', {
        'weightMg': invalid,
        'profitBp': invalid,
        'snapTotalRial': invalid,
      });
      expect(quote.input.weightMg, 0);
      expect(quote.input.profitBp, 700);
      expect(quote.estimatedTotalRial, 0);
    }
  });
  testWidgets('editing keeps every entered percentage and original rate', (
    tester,
  ) async {
    final store = NexModuleStore(harness.services, 'gold');
    final original = example();
    await store.put('quote', 'old', {
      ...original.toRecord(),
      'futureField': {'kept': true},
    });
    await tester.pumpWidget(host(GoldScreen(store: store, editing: original)));
    await tester.pumpAndSettle();
    final form = tester.state<GoldFormState>(find.byType(GoldForm));
    expect(form.buildInput()!.profitBp, 700);
    expect(form.buildInput()!.vatBp, 1000);
    expect(form.buildInput()!.makingPercentBp, 1000);
    expect(form.buildInput()!.rateCentiPerG, 1000000000);
    await tester.tap(find.byKey(const ValueKey('gold-save-fab')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('gold-save-confirm')));
    await tester.tap(find.byKey(const ValueKey('gold-save-confirm')));
    await tester.pumpAndSettle();
    final body = await store.get('quote', 'old');
    expect(body!['snapTotalRial'], 358410000);
    expect(body['futureField'], {'kept': true});
    expect(await store.list('quote'), hasLength(1));
  });
  testWidgets('invalid optional money and percentages disable saving', (
    tester,
  ) async {
    final store = NexModuleStore(harness.services, 'gold');
    await tester.pumpWidget(host(GoldScreen(store: store, editing: example())));
    await tester.pumpAndSettle();
    final form = tester.state<GoldFormState>(find.byType(GoldForm));
    await reveal(tester, 'gold-profit');
    for (final bad in ['-0.5', 'nonsense', '1.234', '99999999999999999999']) {
      await tester.enterText(find.byKey(const ValueKey('gold-profit')), bad);
      await tester.pump();
      expect(form.buildInput(), isNull);
      expect(
        tester
            .widget<FloatingActionButton>(
              find.byKey(const ValueKey('gold-save-fab')),
            )
            .onPressed,
        isNull,
      );
    }
  });
  testWidgets('picker changes recalculate without another keystroke', (
    tester,
  ) async {
    final store = NexModuleStore(harness.services, 'gold');
    await tester.pumpWidget(host(GoldScreen(store: store, editing: example())));
    await tester.pumpAndSettle();
    final form = tester.state<GoldFormState>(find.byType(GoldForm));
    await reveal(tester, 'gold-making-mode');
    await tester.tap(find.byKey(const ValueKey('gold-making-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fixed for this piece').last);
    await tester.pumpAndSettle();
    expect(form.buildInput()!.makingMode, GoldMakingMode.fixed);
    expect(form.buildInput()!.makingFixedRial, 0);
    final rate = GoldMath.calculate(form.buildInput()!);
    expect(rate.estimatedTotalRial, 323100000);
    expect(
      tester
          .widget<FloatingActionButton>(
            find.byKey(const ValueKey('gold-save-fab')),
          )
          .onPressed,
      isNotNull,
    );
  });
  testWidgets('a draft survives route back and reopening', (tester) async {
    final store = NexModuleStore(harness.services, 'gold');
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                NexPageRoute<void>(builder: (_) => GoldScreen(store: store)),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('gold-weight')), '2.125');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('gold-weight')))
          .controller!
          .text,
      '2.125',
    );
    expect(await store.list('quote'), isEmpty);
  });
  testWidgets('Undo restores raw fields and a related edit draft', (
    tester,
  ) async {
    final store = NexModuleStore(harness.services, 'gold');
    final body = {
      ...example().toRecord(),
      'extraUnknown': {'v': 3},
    };
    final draft = {
      'v': 1,
      'base': 'historical',
      'fields': {'title': 'Unsaved'},
    };
    await store.put('quote', 'old', body);
    await store.put('draft', 'quote:old', draft);
    await tester.pumpWidget(
      host(GoldQuotesPage(store: store, showRials: false)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Original'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('gold-quote-delete')));
    await tester.tap(find.byKey(const ValueKey('gold-quote-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gold-delete-confirm')));
    await tester.pumpAndSettle();
    expect(await store.get('quote', 'old'), isNull);
    expect(await store.get('draft', 'quote:old'), isNull);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(await store.get('quote', 'old'), body);
    expect(await store.get('draft', 'quote:old'), draft);
  });
}
