import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/warranty/warranty_logic.dart';
import 'package:nex_client/modules/warranty/warranty_models.dart';
import 'package:nex_client/modules/warranty/warranty_screen.dart';
import 'package:nex_client/modules/warranty/warranty_shared.dart';

import 'warranty_widget_test.dart' show pumpWarranty;

/// How a search behaves for a Persian reader and at a service desk: the
/// query is folded the way the rest of the app folds it, it reaches the
/// serial on the box and the model on the card, and it finds a purchase
/// that has been archived.
void main() {
  group('the query is folded, not matched letter by letter', () {
    test('Arabic yeh and kaf typed on a keyboard find the Persian word', () {
      final body = <String, Object?>{'product': 'کتری برقی'};
      expect(WarrantyLogic.matchesQuery(body, 'كتري'), isTrue);
      expect(WarrantyLogic.matchesQuery(body, 'کتری'), isTrue);
    });

    test('a half-space in the record does not hide it from a plain query', () {
      final body = <String, Object?>{'product': 'یخچال ال‌جی'};
      expect(WarrantyLogic.matchesQuery(body, 'الجی'), isTrue);
      expect(WarrantyLogic.matchesQuery(body, 'ال‌جی'), isTrue);
    });

    test('harakat and tatweel are not part of the match', () {
      final body = <String, Object?>{'company': 'همراه طلایی'};
      expect(WarrantyLogic.matchesQuery(body, 'هَمراه'), isTrue);
      expect(WarrantyLogic.matchesQuery(body, 'همــراه'), isTrue);
    });

    test('Persian digits in the query find an ASCII serial', () {
      final body = <String, Object?>{'serial': '352099001761481'};
      expect(WarrantyLogic.matchesQuery(body, '۳۵۲۰۹۹'), isTrue);
    });

    test('what the person wrote is not changed by the folding', () {
      // Folding is for matching only; the record keeps its own letters.
      expect(
        WarrantyModels.readString(<String, Object?>{
          'product': 'كتري',
        }, 'product'),
        'كتري',
      );
    });
  });

  group('the search reaches what a service desk reads out', () {
    final body = <String, Object?>{
      'product': 'Galaxy A55',
      'brand': 'Samsung',
      'model': 'SM-A556E',
      'serial': '352099001761481',
      'receiptRef': 'INV-1403-8821',
      'merchant': 'Rezaei store',
      'company': 'Hamrah Talaei',
    };

    test('the model, the serial and the invoice are searchable', () {
      expect(WarrantyLogic.matchesQuery(body, 'a556e'), isTrue);
      expect(WarrantyLogic.matchesQuery(body, '352099'), isTrue);
      expect(WarrantyLogic.matchesQuery(body, 'INV-1403'), isTrue);
    });

    test('the shop and the company still are', () {
      expect(WarrantyLogic.matchesQuery(body, 'rezaei'), isTrue);
      expect(WarrantyLogic.matchesQuery(body, 'talaei'), isTrue);
    });

    test('a word that is in none of them matches nothing', () {
      expect(WarrantyLogic.matchesQuery(body, 'kettle'), isFalse);
    });
  });

  group('a search finds an archived purchase', () {
    Future<void> seed(NexModuleStore store) async {
      await store.put('warranty', 'w-live', {
        'v': 2,
        'product': 'Kettle',
        'purchasedAt': '2026-01-10',
        'coverageEnd': '2090-01-10',
      });
      await store.put('warranty', 'w-old', {
        'v': 2,
        'product': 'Old fridge',
        'brand': 'Emersun',
        'archived': true,
        'purchasedAt': '2020-01-10',
        'coverageEnd': '2024-01-10',
      });
    }

    Future<void> pump(
      WidgetTester tester,
      NexModuleStore store, {
      Locale locale = const Locale('en'),
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: WarrantyScreen(store: store),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a query that matches an archived purchase shows it, with '
        'its way back', (tester) async {
      final h = await pumpWarranty(tester);
      final store = NexModuleStore(h.services, 'warranty');
      await seed(store);
      await pump(tester, store);
      // Not searching: the archive stays behind its own toggle.
      expect(find.text('Old fridge'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('warranty-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('warranty-field-search')),
        'fridge',
      );
      await tester.pump();
      expect(find.text('Old fridge'), findsOneWidget);
      expect(find.text('Nothing matches.'), findsNothing);
      expect(
        find.byKey(const ValueKey('warranty-unarchive-w-old')),
        findsOneWidget,
      );
    });

    testWidgets('unarchiving from a search returns it to the list', (
      tester,
    ) async {
      final h = await pumpWarranty(tester);
      final store = NexModuleStore(h.services, 'warranty');
      await seed(store);
      await pump(tester, store);
      await tester.tap(find.byKey(const ValueKey('warranty-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('warranty-field-search')),
        'Emersun',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('warranty-unarchive-w-old')));
      await tester.pumpAndSettle();
      final stored = await store.get('warranty', 'w-old');
      expect(stored?['archived'], isFalse);
      // The search was by the brand; the purchase is now on the list.
      expect(find.text('Old fridge'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a match in the archive alone is not "nothing matches"', (
      tester,
    ) async {
      final h = await pumpWarranty(tester);
      final store = NexModuleStore(h.services, 'warranty');
      await seed(store);
      await pump(tester, store);
      await tester.tap(find.byKey(const ValueKey('warranty-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('warranty-field-search')),
        'zzz',
      );
      await tester.pump();
      expect(find.text('Nothing matches.'), findsOneWidget);
    });

    testWidgets('searching by a serial finds the purchase', (tester) async {
      final h = await pumpWarranty(tester);
      final store = NexModuleStore(h.services, 'warranty');
      await store.put('warranty', 'w-phone', {
        'v': 2,
        'product': 'Phone',
        'serial': '352099001761481',
        'purchasedAt': '2026-01-10',
        'coverageEnd': '2090-01-10',
      });
      await pump(tester, store);
      await tester.tap(find.byKey(const ValueKey('warranty-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('warranty-field-search')),
        '352099',
      );
      await tester.pump();
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('Kettle'), findsNothing);
    });
  });

  group('the shared calendar line', () {
    ModuleRecord record(String id, Map<String, Object?> body) => ModuleRecord(
      module: 'warranty',
      kind: 'warranty',
      id: id,
      body: body,
      updatedAt: DateTime.now(),
    );

    test('a purchase without a product is called by its brand', () {
      final dues = WarrantyShared([
        record('w1', {'brand': 'Samsung', 'coverageEnd': '2026-12-01'}),
      ]).duesBetween(DateTime(2026, 11, 1), DateTime(2026, 12, 31));
      expect(dues, hasLength(1));
      expect(dues.single.title, 'Samsung');
    });

    test('a purchase with no name at all stays off the calendar', () {
      final dues = WarrantyShared([
        record('w1', {'coverageEnd': '2026-12-01'}),
        record('w2', {'product': 'Kettle', 'coverageEnd': '2026-12-02'}),
      ]).duesBetween(DateTime(2026, 11, 1), DateTime(2026, 12, 31));
      expect(dues, hasLength(1));
      expect(dues.single.title, 'Kettle');
    });
  });
}
