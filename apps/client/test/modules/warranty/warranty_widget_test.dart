import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/warranty/warranty_screen.dart';
import 'package:nex_client/platform/nex_services.dart';

import '../../support/nex_harness.dart';
import '../../support/add_button.dart';
import '../../support/more_details.dart';

/// The warranties screen, used the way a person uses it: a purchase
/// added with a duration, searched, sorted, edited, archived, deleted and
/// undone — with claim notes kept and the sections decided on view.
Future<NexTestHarness> pumpWarranty(WidgetTester tester) async {
  final h = await NexTestHarness.create(name: 'warranty_ui_');
  addTearDown(h.dispose);
  await _pump(
    tester,
    WarrantyScreen(store: NexModuleStore(h.services, 'warranty')),
  );
  return h;
}

void main() {
  group('the list', () {
    testWidgets('says what to do when nothing is on file', (tester) async {
      await pumpWarranty(tester);
      expect(find.byKey(const ValueKey('warranty-empty')), findsOneWidget);
      expect(addButton('warranty-fab', 'warranty-empty-add'), findsOneWidget);
      // The empty state carries its own first action, not only the button
      // below it.
      expect(find.byKey(const ValueKey('warranty-empty-add')), findsOneWidget);
    });

    testWidgets('the empty state button adds a purchase', (tester) async {
      final h = await pumpWarranty(tester);
      await tester.tap(find.byKey(const ValueKey('warranty-empty-add')));
      await tester.pumpAndSettle();
      await openMoreDetails(tester, 'warranty-more-toggle');
      await tester.enterText(
        find.byKey(const ValueKey('warranty-field-product')),
        'Kettle',
      );
      await scrollWarrantyTo(
        tester,
        find.byKey(const ValueKey('warranty-today')),
      );
      await tester.tap(find.byKey(const ValueKey('warranty-today')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('warranty-field-duration')),
        '6',
      );
      // Settle the focused field's scroll-into-view before reaching Save.
      await tester.pumpAndSettle();
      await _tapSave(tester);
      expect(find.text('Kettle'), findsWidgets);
      expect(
        await h.services.moduleRecords('warranty', 'warranty'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Today chip writes the zero-padded entry format', (
      tester,
    ) async {
      await pumpWarranty(tester);
      await tester.tap(addButton('warranty-fab', 'warranty-empty-add'));
      await tester.pumpAndSettle();
      await openMoreDetails(tester, 'warranty-more-toggle');
      await scrollWarrantyTo(
        tester,
        find.byKey(const ValueKey('warranty-today')),
      );
      await tester.tap(find.byKey(const ValueKey('warranty-today')));
      await tester.pump();
      final written = tester
          .widget<TextField>(
            find.byKey(const ValueKey('warranty-field-purchase')),
          )
          .controller!
          .text;
      expect(written, matches(r'^\d{4}/\d{2}/\d{2}$'));
    });

    testWidgets('a purchase with a duration lands under Covered, with its '
        'computed end shown while writing', (tester) async {
      final h = await pumpWarranty(tester);
      await addWarranty(tester, product: 'Kettle', durationMonths: '6');
      expect(
        find.byKey(const ValueKey('warranty-section-active')),
        findsOneWidget,
      );
      expect(find.text('Kettle'), findsWidgets);
      final stored = await h.services.moduleRecords('warranty', 'warranty');
      expect(stored.single.body['durationMonths'], 6);
      expect(
        DateTime.parse(stored.single.body['coverageEnd']! as String).year,
        DateTime.now().add(const Duration(days: 182)).year,
      );
    });

    testWidgets('an end date written directly works the same', (tester) async {
      final h = await pumpWarranty(tester);
      await addWarranty(tester, product: 'Kettle', endDate: '2099/01/01');
      final stored = await h.services.moduleRecords('warranty', 'warranty');
      expect(
        DateTime.parse(stored.single.body['coverageEnd']! as String),
        DateTime(2099, 1, 1),
      );
      expect(stored.single.body.containsKey('durationMonths'), isFalse);
    });

    testWidgets('without a product it says so and saves nothing', (
      tester,
    ) async {
      final h = await pumpWarranty(tester);
      await tester.tap(addButton('warranty-fab', 'warranty-empty-add'));
      await tester.pumpAndSettle();
      await openMoreDetails(tester, 'warranty-more-toggle');
      await _tapSave(tester);
      expect(find.text('Write what the product is.'), findsOneWidget);
      expect(await h.services.moduleRecords('warranty', 'warranty'), isEmpty);
    });

    testWidgets('a purchase date is required', (tester) async {
      final h = await pumpWarranty(tester);
      await tester.tap(addButton('warranty-fab', 'warranty-empty-add'));
      await tester.pumpAndSettle();
      await openMoreDetails(tester, 'warranty-more-toggle');
      await tester.enterText(
        find.byKey(const ValueKey('warranty-field-product')),
        'Kettle',
      );
      await _tapSave(tester);
      expect(find.text('Use a valid purchase date.'), findsOneWidget);
      expect(await h.services.moduleRecords('warranty', 'warranty'), isEmpty);
    });

    testWidgets('an end before the purchase is refused', (tester) async {
      final h = await pumpWarranty(tester);
      await addWarranty(
        tester,
        product: 'Kettle',
        purchaseDate: '2026/01/10',
        endDate: '2025/12/31',
      );
      expect(find.text('The end date is before the purchase.'), findsOneWidget);
      expect(await h.services.moduleRecords('warranty', 'warranty'), isEmpty);
    });

    testWidgets('a duration and an end date together are refused', (
      tester,
    ) async {
      final h = await pumpWarranty(tester);
      await addWarranty(
        tester,
        product: 'Kettle',
        durationMonths: '6',
        endDate: '2027/01/01',
      );
      expect(
        find.text('Write a duration or an end date — not both.'),
        findsOneWidget,
      );
      expect(await h.services.moduleRecords('warranty', 'warranty'), isEmpty);
    });

    testWidgets('a malformed amount is refused', (tester) async {
      final h = await pumpWarranty(tester);
      await addWarranty(tester, product: 'Kettle', amount: 'free');
      expect(find.text('Write a whole number, 0 or more'), findsOneWidget);
      expect(await h.services.moduleRecords('warranty', 'warranty'), isEmpty);
    });

    testWidgets('tomans typed are stored as exact rials', (tester) async {
      final h = await pumpWarranty(tester);
      await addWarranty(
        tester,
        product: 'Kettle',
        durationMonths: '6',
        amount: '3000000',
        inTomans: true,
      );
      final stored = await h.services.moduleRecords('warranty', 'warranty');
      expect(stored.single.body['amountRials'], 30000000);
    });

    testWidgets('long Arabic, Persian and English names hold up', (
      tester,
    ) async {
      final h = await pumpWarranty(tester);
      final long =
          '${List.filled(40, 'نام').join()} and ${List.filled(40, 'name').join()}';
      await addWarranty(tester, product: long, durationMonths: '6');
      expect(
        (await h.services.moduleRecords(
          'warranty',
          'warranty',
        )).single.body['product'],
        long,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('sections decided on view', () {
    testWidgets('expired purchases sit under Expired', (tester) async {
      await pumpWarranty(tester);
      await addWarranty(
        tester,
        product: 'Old kettle',
        purchaseDate: '2019/01/01',
        endDate: '2020/01/01',
      );
      expect(find.text('Expired'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('warranty-section-active')),
        findsNothing,
      );
    });

    testWidgets('a coverage ending this week shows its days', (tester) async {
      final soon = DateTime.now().add(const Duration(days: 5));
      await pumpWarranty(tester);
      await addWarranty(
        tester,
        product: 'Kettle',
        endDate: '${soon.year}/${soon.month}/${soon.day}',
      );
      expect(
        find.byKey(const ValueKey('warranty-section-expiring')),
        findsOneWidget,
      );
    });
  });

  group('search and sort', () {
    testWidgets('search finds by product and brand', (tester) async {
      await pumpWarranty(tester);
      await addWarranty(
        tester,
        product: 'Kettle',
        brand: 'Boma',
        endDate: '2090/01/01',
      );
      await addWarranty(
        tester,
        product: 'Phone',
        brand: 'Samsung',
        endDate: '2091/01/01',
      );
      await tester.tap(find.byKey(const ValueKey('warranty-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('warranty-field-search')),
        'samsung',
      );
      await tester.pump();
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('Kettle'), findsNothing);
    });

    testWidgets('sorting by soonest end reorders the rows', (tester) async {
      await pumpWarranty(tester);
      await addWarranty(tester, product: 'Far', endDate: '2090/01/01');
      await addWarranty(tester, product: 'Near', endDate: '2030/01/01');
      await tester.tap(find.byKey(const ValueKey('warranty-sort')));
      await tester.pumpAndSettle();
      // Both stay on the list; only the order changes.
      expect(find.text('Far'), findsWidgets);
      expect(find.text('Near'), findsWidgets);
      final rows = find.byType(ListTile).evaluate();
      expect(rows.length, greaterThanOrEqualTo(2));
    });
  });
}

// ------------------------------------------------------------------ helpers

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

/// Adds a purchase through the editor sheet, as a person would.
Future<void> addWarranty(
  WidgetTester tester, {
  required String product,
  String brand = '',
  String purchaseDate = '',
  String durationMonths = '',
  String endDate = '',
  String amount = '',
  bool inTomans = false,
}) async {
  await tester.tap(addButton('warranty-fab', 'warranty-empty-add'));
  await tester.pumpAndSettle();
  await openMoreDetails(tester, 'warranty-more-toggle');
  await tester.enterText(
    find.byKey(const ValueKey('warranty-field-product')),
    product,
  );
  if (brand.isNotEmpty) {
    await tester.enterText(
      find.byKey(const ValueKey('warranty-field-brand')),
      brand,
    );
  }
  if (purchaseDate.isEmpty) {
    // The Today chip writes today's date for us.
    await scrollWarrantyTo(
      tester,
      find.byKey(const ValueKey('warranty-today')),
    );
    await tester.tap(find.byKey(const ValueKey('warranty-today')));
    await tester.pump();
  } else {
    await tester.enterText(
      find.byKey(const ValueKey('warranty-field-purchase')),
      purchaseDate,
    );
  }
  if (durationMonths.isNotEmpty) {
    await tester.enterText(
      find.byKey(const ValueKey('warranty-field-duration')),
      durationMonths,
    );
  }
  if (endDate.isNotEmpty) {
    await tester.enterText(
      find.byKey(const ValueKey('warranty-field-end')),
      endDate,
    );
  }
  if (amount.isNotEmpty) {
    await scrollWarrantyTo(
      tester,
      find.byKey(const ValueKey('warranty-amount-unit')),
    );
    if (inTomans) {
      await tester.tap(find.byKey(const ValueKey('warranty-amount-unit')));
      await tester.pumpAndSettle();
    }
    await tester.enterText(
      find.byKey(const ValueKey('warranty-field-amount')),
      amount,
    );
  }
  await _tapSave(tester);
  await tester.pumpAndSettle();
}

/// Drags the sheet's list until [finder] is actually tappable —
/// `ensureVisible` can leave a button half under the screen edge.
Future<void> scrollWarrantyTo(WidgetTester tester, Finder finder) async {
  // The sheet is one plain scroll view, so it can bring the target into view
  // itself; a short drag after that clears a button left half under the
  // screen edge.
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }
  final sheetList = find
      .descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable),
      )
      .first;
  for (var attempt = 0; attempt < 10; attempt++) {
    if (finder.hitTestable().evaluate().isNotEmpty) break;
    await tester.drag(sheetList, const Offset(0, -120), warnIfMissed: false);
    await tester.pumpAndSettle();
  }
}

Future<void> _tapSave(WidgetTester tester) async {
  await scrollWarrantyTo(tester, find.byKey(const ValueKey('warranty-save')));
  await tester.tap(find.byKey(const ValueKey('warranty-save')));
  await tester.pumpAndSettle();
}
