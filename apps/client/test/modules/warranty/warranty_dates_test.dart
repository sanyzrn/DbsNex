import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/warranty/warranty_screen.dart';

import '../../support/nex_harness.dart';
import 'warranty_widget_test.dart' show addWarranty, pumpWarranty;

/// Every date a person reads is shown on their saved calendar through the
/// shared label — Jalali in Persian digits for a Persian reader, civil
/// `yyyy/MM/dd` for an English one — with no "Gregorian" wording left in
/// either language. A purchase whose end cannot be read is «date
/// unavailable», never expired.
void main() {
  group('dates on the reader’s calendar', () {
    testWidgets('the English list and detail read civil days', (tester) async {
      await pumpWarranty(tester);
      await addWarranty(
        tester,
        product: 'Kettle',
        purchaseDate: '2026/10/13',
        endDate: '2030/10/13',
      );
      // The list row, on the shared label.
      expect(find.text('2030/10/13'), findsOneWidget);
      await tester.tap(find.text('Kettle'));
      await tester.pumpAndSettle();
      // And the detail sheet's purchased and coverage rows — the row behind
      // the sheet still counts its own copy of the end.
      expect(find.text('2026/10/13'), findsOneWidget);
      expect(find.text('2030/10/13'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Persian reads Jalali days, in Persian digits', (tester) async {
      final h = await NexTestHarness.create(name: 'warranty_fa_dates_');
      addTearDown(h.dispose);
      final store = NexModuleStore(h.services, 'warranty');
      await store.put('warranty', 'w1', {
        'v': 1,
        'product': 'کتری برقی',
        'purchasedAt': '2026-10-13',
        'coverageEnd': '2030-10-13',
      });
      await store.put('claim', 'c1', {
        'v': 1,
        'warrantyId': 'w1',
        'kind': 'claim',
        'note': 'تماس با فروشگاه',
        'at': '2026-10-13T15:30:00.000Z',
      });
      await _pump(
        tester,
        WarrantyScreen(store: store),
        locale: const Locale('fa'),
      );
      // The row's coverage end: the Jalali day in Persian digits, never a
      // Gregorian year a Persian reader has to work out.
      expect(find.text('۱۴۰۹/۰۷/۲۱'), findsOneWidget);
      await tester.tap(find.text('کتری برقی'));
      await tester.pumpAndSettle();
      // The detail's coverage row, over the row behind the sheet.
      expect(find.text('۱۴۰۹/۰۷/۲۱'), findsNWidgets(2));
      // The claim note's own day, as the local day it happened.
      expect(find.textContaining('ادعا — ۱۴۰۵/۰۷/۲۱'), findsOneWidget);
      expect(find.textContaining(RegExp('20[0-9][0-9]/')), findsNothing);
      expect(find.textContaining('میلادی'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the computed end in the editor reads on the shared label', (
      tester,
    ) async {
      await pumpWarranty(tester);
      await tester.tap(find.byKey(const ValueKey('warranty-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('warranty-field-product')),
        'Kettle',
      );
      await tester.enterText(
        find.byKey(const ValueKey('warranty-field-purchase')),
        '2026/10/13',
      );
      await tester.enterText(
        find.byKey(const ValueKey('warranty-field-duration')),
        '12',
      );
      await tester.pumpAndSettle();
      expect(find.text('Ends 2027/10/13'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no date field calls itself Gregorian any more', (
      tester,
    ) async {
      await pumpWarranty(tester);
      await tester.tap(find.byKey(const ValueKey('warranty-fab')));
      await tester.pumpAndSettle();
      expect(find.text('Purchase date'), findsOneWidget);
      expect(find.text('or end date'), findsOneWidget);
      expect(find.textContaining('Gregorian'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('a purchase whose end cannot be read', () {
    testWidgets('sits under its own words, never under expired', (
      tester,
    ) async {
      final h = await NexTestHarness.create(name: 'warranty_unknown_');
      addTearDown(h.dispose);
      final store = NexModuleStore(h.services, 'warranty');
      await store.put('warranty', 'w1', {
        'v': 1,
        'product': 'Broken date',
        'coverageEnd': 'not a date',
      });
      await _pump(tester, WarrantyScreen(store: store));

      expect(find.text('Date unavailable'), findsWidgets);
      // The unknown glyph, not the expired one.
      expect(find.byIcon(Icons.help_outline), findsWidgets);
      expect(find.byIcon(Icons.event_busy_outlined), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('the words for a single one', () {
    testWidgets('a one-month duration reads “1 month”, never “1 months”', (
      tester,
    ) async {
      final h = await NexTestHarness.create(name: 'warranty_one_month_');
      addTearDown(h.dispose);
      final store = NexModuleStore(h.services, 'warranty');
      final today = DateTime.now();
      await store.put('warranty', 'w1', {
        'v': 1,
        'product': 'Kettle',
        'purchasedAt': DateTime(
          today.year,
          today.month,
          today.day,
        ).toIso8601String(),
        'coverageEnd': DateTime(
          today.year,
          today.month,
          today.day,
        ).add(const Duration(days: 30)).toIso8601String(),
        'durationMonths': 1,
      });
      await _pump(tester, WarrantyScreen(store: store));
      await tester.tap(find.text('Kettle'));
      await tester.pumpAndSettle();
      expect(find.text('1 month'), findsOneWidget);
      expect(find.text('1 months'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a coverage that ended yesterday says so', (tester) async {
      final h = await NexTestHarness.create(name: 'warranty_yesterday_');
      addTearDown(h.dispose);
      final store = NexModuleStore(h.services, 'warranty');
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await store.put('warranty', 'w1', {
        'v': 1,
        'product': 'Kettle',
        'purchasedAt': '2019-01-01',
        'coverageEnd': DateTime(
          yesterday.year,
          yesterday.month,
          yesterday.day,
        ).toIso8601String(),
      });
      await _pump(tester, WarrantyScreen(store: store));
      expect(find.text('Ended yesterday'), findsOneWidget);
      expect(find.textContaining('Ended 1 days ago'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

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
