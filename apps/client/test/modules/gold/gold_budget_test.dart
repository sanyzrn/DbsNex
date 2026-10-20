import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/gold/gold_math.dart';
import 'package:nex_client/modules/gold/gold_screen.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/nex_harness.dart';

/// «From a budget» runs the estimate backwards. The answer must be the
/// heaviest piece that still fits — one milligram more must not.
void main() {
  const base = GoldInput(
    weightMg: 3000,
    finenessPpt: 750,
    rateCentiPerG: 1000000000,
    rateRefPpt: 750,
    makingPercentBp: 1000,
  );

  int total(GoldInput input, int mg) =>
      GoldMath.calculate(input.withWeightMg(mg)).estimatedTotalRial;

  group('the heaviest weight that fits a budget', () {
    test('the reference example: 358,410,000 rials buys exactly 3 g', () {
      expect(GoldMath.maxWeightMgWithin(base, 358410000), 3000);
    });

    test('one rial short buys a little less, never more', () {
      final weight = GoldMath.maxWeightMgWithin(base, 358409999);
      expect(weight, lessThan(3000));
      expect(total(base, weight), lessThanOrEqualTo(358409999));
      expect(total(base, weight + 1), greaterThan(358409999));
    });

    test('is exact at many budgets, with a fixed making charge', () {
      final fixed = GoldInput(
        weightMg: 1000,
        finenessPpt: 750,
        rateCentiPerG: 1234567,
        rateRefPpt: 750,
        makingMode: GoldMakingMode.fixed,
        makingFixedRial: 7000000,
        commissionRial: 123456,
        extras: const [('box', 55000)],
      );
      for (final budget in [8000000, 9999999, 20000000, 123456789, 987654321]) {
        final weight = GoldMath.maxWeightMgWithin(fixed, budget);
        if (weight == 0) {
          expect(total(fixed, 1), greaterThan(budget));
          continue;
        }
        expect(total(fixed, weight), lessThanOrEqualTo(budget));
        if (weight < GoldInput.maxWeightMg) {
          expect(total(fixed, weight + 1), greaterThan(budget));
        }
      }
    });

    test('a budget under the fixed costs buys nothing', () {
      final fixed = GoldInput(
        weightMg: 1000,
        finenessPpt: 750,
        rateCentiPerG: 1000000000,
        rateRefPpt: 750,
        makingMode: GoldMakingMode.fixed,
        makingFixedRial: 50000000,
      );
      expect(GoldMath.maxWeightMgWithin(fixed, 40000000), 0);
      expect(GoldMath.maxWeightMgWithin(fixed, 0), 0);
    });

    test('a budget past the calculator\'s limit is capped, not overflowed', () {
      expect(
        GoldMath.maxWeightMgWithin(base, GoldInput.maxAmountRial),
        lessThanOrEqualTo(GoldInput.maxWeightMg),
      );
    });

    test('the gross weight and the seller\'s quote do not take part', () {
      const quoted = GoldInput(
        weightMg: 3000,
        grossWeightMg: 4000,
        finenessPpt: 750,
        rateCentiPerG: 1000000000,
        rateRefPpt: 750,
        makingPercentBp: 1000,
        shopQuoteRial: 1,
      );
      expect(GoldMath.maxWeightMgWithin(quoted, 358410000), 3000);
    });
  });

  group('the making charge as a share of the metal', () {
    test('a percentage charge reads back as itself', () {
      expect(GoldMath.makingShareBp(GoldMath.calculate(base)), 1000);
    });

    test('a fixed charge is worked out against the metal value', () {
      final result = GoldMath.calculate(
        GoldInput(
          weightMg: 3000,
          finenessPpt: 750,
          rateCentiPerG: 1000000000,
          rateRefPpt: 750,
          makingMode: GoldMakingMode.fixed,
          makingFixedRial: 60000000,
        ),
      );
      // 60,000,000 / 300,000,000 = 20%.
      expect(GoldMath.makingShareBp(result), 2000);
    });
  });

  group('on screen', () {
    late NexTestHarness harness;
    setUp(() async => harness = await NexTestHarness.create(name: 'goldb_'));
    tearDown(() => harness.dispose());

    Widget screen() => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GoldScreen(store: NexModuleStore(harness.services, 'gold')),
    );

    testWidgets('asks for the rate first when there is none', (tester) async {
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('gold-open-budget')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('gold-budget-field')), findsNothing);
    });

    testWidgets('turns a budget into a weight and puts it in the form', (
      tester,
    ) async {
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('gold-rate')),
        '10000000',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('gold-open-budget')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('gold-budget-field')),
        '35841000',
      );
      await tester.pump();
      // 7% profit and 10% VAT are the form's own starting points; making
      // is 0 here, so the weight is a little over 3 g.
      expect(find.byKey(const ValueKey('gold-budget-result')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('gold-budget-use')));
      await tester.pumpAndSettle();
      final weight = tester.widget<TextFormField>(
        find.byKey(const ValueKey('gold-weight')),
      );
      expect(weight.controller!.text, isNotEmpty);
      expect(double.parse(weight.controller!.text), greaterThan(3));
    });
  });
}
