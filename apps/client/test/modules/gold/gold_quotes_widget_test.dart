import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/gold/gold_screen.dart';
import 'package:nex_client/platform/nex_services.dart';

import '../../support/nex_harness.dart';

/// Gold Check's saved estimates on screen: the honest empty state, delete
/// with Undo restoring the whole record, and comparing two quotes — on a
/// shared basis and across bases. (The calculator itself is covered in
/// `gold_widget_test.dart`.)
void main() {
  late NexTestHarness harness;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'gold_q_');
  });

  tearDown(() => harness.dispose());

  Widget host(Widget home) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  /// The English words the tests assert against, spelled out here so a
  /// wording change in the strings file fails loudly rather than silently
  /// un-testing the screen.
  const Map<String, String> enWords = {
    'savedQuotesEmpty':
        'Nothing saved yet. Work out an estimate and keep it, together with '
        'the rates that went into it.',
    'compareWarn':
        'These two are not on the same weight and fineness basis — the '
        'comparison may mean nothing.',
  };

  testWidgets('the quotes page starts with an honest empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(GoldScreen(store: NexModuleStore(harness.services, 'gold'))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gold-open-quotes')));
    await tester.pumpAndSettle();
    expect(find.byType(NexEmptyState), findsOneWidget);
    expect(find.text(enWords['savedQuotesEmpty']!), findsOneWidget);
  });

  testWidgets('delete asks, and Undo puts the estimate back whole', (
    tester,
  ) async {
    final store = NexModuleStore(harness.services, 'gold');
    final id = store.newId();
    await store.put('quote', id, {
      'schema': 1,
      'title': 'Bracelet',
      'savedAt': '2026-10-11T09:00:00',
      'quoteDate': '2026-10-11',
      'weightMg': 5000,
      'finenessPpt': 750,
      'rateCentiPerG': 500000000,
      'rateRefPpt': 750,
      'makingMode': 'percent',
      'makingPercentBp': 1000,
      'profitBp': 700,
      'vatBp': 1000,
      'snapMetalRial': 250000000,
      'snapMakingRial': 25000000,
      'snapProfitRial': 19250000,
      'snapVatBaseRial': 44250000,
      'snapVatRial': 4425000,
      'snapTotalRial': 298675000,
    });

    await tester.pumpWidget(host(GoldScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gold-open-quotes')));
    await tester.pumpAndSettle();
    expect(find.text('Bracelet'), findsOneWidget);

    await tester.tap(find.text('Bracelet'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gold-quote-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Delete this estimate?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('gold-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Estimate deleted'), findsOneWidget);
    expect(await harness.services.moduleRecords('gold', 'quote'), isEmpty);

    // Undo brings the whole record back, same id, same numbers.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    final restored = await harness.services.moduleRecords('gold', 'quote');
    expect(restored, hasLength(1));
    expect(restored.single.id, id);
    expect(restored.single.body['title'], 'Bracelet');
    expect(restored.single.body['snapTotalRial'], 298675000);
    expect(find.text('Estimate restored'), findsOneWidget);
  });

  Map<String, Object> quoteRecord(String title, int weightMg, int fineness) => {
    'schema': 1,
    'title': title,
    'savedAt': '2026-10-11T09:00:00',
    'quoteDate': '2026-10-11',
    'weightMg': weightMg,
    'finenessPpt': fineness,
    'rateCentiPerG': 1000000000,
    'rateRefPpt': 750,
    'makingMode': 'percent',
    'makingPercentBp': 1000,
    'profitBp': 700,
    'vatBp': 1000,
    'snapMetalRial': 300000000,
    'snapMakingRial': 30000000,
    'snapProfitRial': 23100000,
    'snapVatBaseRial': 53100000,
    'snapVatRial': 5310000,
    'snapTotalRial': 358410000,
  };

  testWidgets('two estimates on the same basis compare line by line', (
    tester,
  ) async {
    final store = NexModuleStore(harness.services, 'gold');
    await store.put('quote', store.newId(), quoteRecord('Shop A', 3000, 750));
    await store.put('quote', store.newId(), quoteRecord('Shop B', 3000, 750));

    await tester.pumpWidget(host(GoldScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gold-open-quotes')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('gold-compare-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shop A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shop B'));
    await tester.pumpAndSettle();

    expect(find.text('Same weight and fineness basis.'), findsOneWidget);
    expect(find.text('Difference'), findsOneWidget);
  });

  testWidgets('a comparison across bases says so instead of meaning it', (
    tester,
  ) async {
    final store = NexModuleStore(harness.services, 'gold');
    await store.put('quote', store.newId(), quoteRecord('Shop A', 3000, 750));
    await store.put('quote', store.newId(), quoteRecord('Shop B', 4000, 875));

    await tester.pumpWidget(host(GoldScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gold-open-quotes')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gold-compare-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shop A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shop B'));
    await tester.pumpAndSettle();

    expect(find.text(enWords['compareWarn']!), findsOneWidget);
  });
}
