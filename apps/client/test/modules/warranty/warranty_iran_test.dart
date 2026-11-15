import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/warranty/warranty_logic.dart';
import 'package:nex_client/modules/warranty/warranty_models.dart';
import 'package:nex_client/modules/warranty/warranty_service_file.dart';

/// The parts an Iranian buyer deals with: a warranty company separate from
/// the shop, its support line and card number, the registry, the three
/// kinds of cover, and the 30-day list those all exist for.
void main() {
  group('reading a record written by another version', () {
    test('a v1 purchase has no company, phone, card or registry — and no '
        'crash', () {
      final body = <String, Object?>{
        'v': 1,
        'product': 'کتری',
        'purchasedAt': '2026-10-13',
        'coverageEnd': '2028-10-13',
      };
      expect(WarrantyModels.readCoverKind(body), '');
      expect(WarrantyModels.readRegistry(body), '');
      expect(WarrantyModels.readString(body, 'company'), '');
      expect(WarrantyModels.readString(body, 'supportPhone'), '');
      expect(WarrantyModels.readString(body, 'cardNumber'), '');
      expect(WarrantyModels.readDate(body, 'purchasedAt'), isNotNull);
    });

    test('a kind or registry value nobody knows reads as empty', () {
      for (final value in <Object?>[
        null,
        3,
        '',
        'gold',
        'MINE',
        [1],
      ]) {
        expect(
          WarrantyModels.readCoverKind({'coverKind': value}),
          '',
          reason: '$value',
        );
        expect(
          WarrantyModels.readRegistry({'registryOwner': value}),
          '',
          reason: '$value',
        );
      }
      expect(
        WarrantyModels.readCoverKind({'coverKind': 'afterSales'}),
        'afterSales',
      );
      expect(WarrantyModels.readRegistry({'registryOwner': 'other'}), 'other');
    });
  });

  group('writing a v2 purchase', () {
    final purchase = DateTime(2026, 3, 20);
    final end = DateTime(2027, 9, 20);

    test('the Iran fields are written only when they were typed', () {
      final bare = WarrantyModels.warrantyBody(
        product: 'Kettle',
        category: '',
        brand: '',
        model: '',
        serial: '',
        merchant: '',
        receiptRef: '',
        coverageType: '',
        note: '',
        purchasedAt: purchase,
        coverageEnd: end,
      );
      expect(bare['v'], 2);
      for (final key in const [
        'company',
        'supportPhone',
        'cardNumber',
        'coverKind',
        'registryOwner',
      ]) {
        expect(bare.containsKey(key), isFalse, reason: key);
      }

      final full = WarrantyModels.warrantyBody(
        product: 'Phone',
        category: 'Electronics',
        brand: 'Samsung',
        model: 'A55',
        serial: '352099001761481',
        merchant: 'Shop',
        receiptRef: 'INV-1',
        coverageType: 'Official',
        note: '',
        purchasedAt: purchase,
        coverageEnd: end,
        coverKind: WarrantyModels.coverCompany,
        company: '  Hamrah Talaei  ',
        supportPhone: ' 021-1234 ',
        cardNumber: ' C-99 ',
        registryOwner: WarrantyModels.registryMine,
      );
      expect(full['company'], 'Hamrah Talaei');
      expect(full['supportPhone'], '021-1234');
      expect(full['cardNumber'], 'C-99');
      expect(full['coverKind'], 'company');
      expect(full['registryOwner'], 'mine');
    });
  });

  group('the 30-day list', () {
    ModuleRecord record(String id, String? end, {String? product}) =>
        ModuleRecord(
          module: 'warranty',
          kind: 'warranty',
          id: id,
          body: {'product': product ?? id, 'coverageEnd': ?end},
          updatedAt: DateTime.now(),
        );
    final now = DateTime(2026, 10, 12, 15, 30);

    test(
      'ending-soon comes first, soonest first, whatever the input order',
      () {
        final split = WarrantyLogic.splitByStatus([
          record('far', '2028-01-01'),
          record('soon-20', '2026-11-01'),
          record('gone', '2026-01-01'),
          record('soon-3', '2026-10-15'),
          record('broken', 'not a date'),
        ], now);
        expect(split.expiring.map((r) => r.id), ['soon-3', 'soon-20']);
        expect(split.covered.map((r) => r.id), ['far']);
        expect(split.expired.map((r) => r.id), ['gone']);
        expect(split.unknown.map((r) => r.id), ['broken']);
      },
    );

    test('the day it ends is still covered, the next day is not', () {
      final split = WarrantyLogic.splitByStatus([
        record('today', '2026-10-12'),
        record('yesterday', '2026-10-11'),
      ], now);
      expect(split.expiring.map((r) => r.id), ['today']);
      expect(split.expired.map((r) => r.id), ['yesterday']);
    });

    test('a very old end stays expired and keeps the latest first', () {
      final split = WarrantyLogic.splitByStatus(
        [record('ancient', '1900-01-01'), record('last-year', '2025-12-31')],
        now,
        sorted: true,
      );
      expect(split.expired.map((r) => r.id), ['last-year', 'ancient']);
    });

    test('empty input is four empty lists, not a crash', () {
      final split = WarrantyLogic.splitByStatus(const [], now);
      expect(split.expiring, isEmpty);
      expect(split.covered, isEmpty);
      expect(split.expired, isEmpty);
      expect(split.unknown, isEmpty);
    });
  });

  group('reminder maths', () {
    test('30, 7 and 1 days before the end, at nine in the morning', () {
      final end = DateTime(2027, 9, 20);
      expect(WarrantyLogic.reminderAt(end, 30), DateTime(2027, 8, 21, 9));
      expect(WarrantyLogic.reminderAt(end, 7), DateTime(2027, 9, 13, 9));
      expect(WarrantyLogic.reminderAt(end, 1), DateTime(2027, 9, 19, 9));
      // Across a month boundary, February included.
      expect(
        WarrantyLogic.reminderAt(DateTime(2027, 3, 1), 1),
        DateTime(2027, 2, 28, 9),
      );
    });

    test('only the lead times still in the future are offered', () {
      final end = DateTime(2026, 12, 1);
      expect(WarrantyLogic.reminderChoices(end, DateTime(2026, 11, 1)), [
        30,
        7,
        1,
      ]);
      expect(WarrantyLogic.reminderChoices(end, DateTime(2026, 11, 20)), [
        7,
        1,
      ]);
      expect(WarrantyLogic.reminderChoices(end, DateTime(2026, 11, 30)), [1]);
      // The day it ends, and after, nothing can be set.
      expect(
        WarrantyLogic.reminderChoices(end, DateTime(2026, 12, 1)),
        isEmpty,
      );
      expect(WarrantyLogic.reminderChoices(end, DateTime(2027, 1, 1)), isEmpty);
    });

    test('an end already past has nothing to remind about', () {
      expect(
        WarrantyLogic.reminderChoices(DateTime(2020, 1, 1), DateTime(2026)),
        isEmpty,
      );
    });
  });

  group('search reaches the company and the shop', () {
    test('by company, shop, product or brand', () {
      final body = <String, Object?>{
        'product': 'گوشی',
        'brand': 'Samsung',
        'merchant': 'فروشگاه رضایی',
        'company': 'همراه طلایی',
      };
      expect(WarrantyLogic.matchesQuery(body, 'همراه'), isTrue);
      expect(WarrantyLogic.matchesQuery(body, 'رضایی'), isTrue);
      expect(WarrantyLogic.matchesQuery(body, 'Samsung'), isTrue);
      expect(WarrantyLogic.matchesQuery(body, 'apple'), isFalse);
      expect(WarrantyLogic.matchesQuery(body, ''), isTrue);
    });
  });

  testWidgets(
    'the service file carries the company, phone, card and registry',
    (tester) async {
      late String text;
      late String persian;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              final body = <String, Object?>{
                'v': 2,
                'product': 'Galaxy A55',
                'brand': 'Samsung',
                'serial': '352099001761481',
                'company': 'Hamrah Talaei',
                'supportPhone': '021-91001234',
                'cardNumber': 'C-7788',
                'coverKind': 'company',
                'registryOwner': 'mine',
                'merchant': 'Rezaei store',
                'receiptRef': 'INV-1403-8821',
                'purchasedAt': DateTime(2026, 3, 20).toIso8601String(),
                'coverageEnd': DateTime(2027, 9, 20).toIso8601String(),
              };
              text = warrantyServiceFile(context, body, const []);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(text, contains('Serial / IMEI: 352099001761481'));
      expect(text, contains('Warranty company: Hamrah Talaei'));
      expect(text, contains('Support: 021-91001234'));
      expect(text, contains('Card number: C-7788'));
      expect(text, contains('Cover: Company warranty'));
      expect(text, contains('Registry: In my name'));
      expect(text, contains('Coverage ends: 2027/09/20 — '));
      expect(text, contains('Nex does not confirm a warranty'));

      // The same record in Persian, on the Jalali calendar.
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fa'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              persian = warrantyServiceFile(context, {
                'v': 2,
                'product': 'گوشی',
                'company': 'همراه طلایی',
                'supportPhone': '۰۲۱-۹۱۰۰۱۲۳۴',
                'coverageEnd': DateTime(2027, 9, 20).toIso8601String(),
              }, const []);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(persian, contains('شرکت گارانتی: همراه طلایی'));
      expect(persian, contains('پشتیبانی: ۰۲۱-۹۱۰۰۱۲۳۴'));
      expect(persian, contains('۱۴۰۶/۰۶/۲۹'));
    },
  );
}
