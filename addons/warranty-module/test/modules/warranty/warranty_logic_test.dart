import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/warranty/warranty_logic.dart';

/// The coverage arithmetic and the money display, on their own: month
/// ends, leap years, day boundaries, the soonest-end sort, and the exact
/// rial/toman conversion.
void main() {
  final today = DateTime(2026, 10, 12, 15, 30);

  group('months after a purchase', () {
    test('the same day of the ending month', () {
      expect(
        WarrantyLogic.addMonths(DateTime(2026, 8, 12), 6),
        DateTime(2027, 2, 12),
      );
      expect(
        WarrantyLogic.addMonths(DateTime(2026, 1, 15), 24),
        DateTime(2028, 1, 15),
      );
    });

    test('a month with no such day takes its last day', () {
      // January 31 + 1 month is February 28 — never March 3.
      expect(
        WarrantyLogic.addMonths(DateTime(2026, 1, 31), 1),
        DateTime(2026, 2, 28),
      );
      expect(
        WarrantyLogic.addMonths(DateTime(2023, 8, 31), 1),
        DateTime(2023, 9, 30),
      );
    });

    test('a leap February takes its 29th', () {
      expect(
        WarrantyLogic.addMonths(DateTime(2024, 1, 31), 1),
        DateTime(2024, 2, 29),
      );
      // And the year after, the same purchase ends on the 28th.
      expect(
        WarrantyLogic.addMonths(DateTime(2025, 1, 31), 1),
        DateTime(2025, 2, 28),
      );
    });

    test('across a year boundary', () {
      expect(
        WarrantyLogic.addMonths(DateTime(2026, 12, 15), 2),
        DateTime(2027, 2, 15),
      );
    });

    test('zero months is the purchase itself', () {
      expect(
        WarrantyLogic.addMonths(DateTime(2026, 5, 5), 0),
        DateTime(2026, 5, 5),
      );
    });
  });

  group('where a coverage sits today', () {
    test('past its end day it is expired', () {
      expect(WarrantyLogic.statusOf(DateTime(2026, 10, 11), today), (
        expired: true,
        expiring: false,
        daysLeft: -1,
      ));
    });

    test('through its end day it is covered, with that day left', () {
      expect(WarrantyLogic.statusOf(DateTime(2026, 10, 12), today), (
        expired: false,
        expiring: true,
        daysLeft: 0,
      ));
      expect(WarrantyLogic.statusOf(DateTime(2026, 10, 13), today), (
        expired: false,
        expiring: true,
        daysLeft: 1,
      ));
    });

    test('within the window it is expiring, past it simply covered', () {
      final soon = today.add(const Duration(days: 30));
      final far = today.add(const Duration(days: 31));
      expect(
        WarrantyLogic.statusOf(
          DateTime(soon.year, soon.month, soon.day),
          today,
        ).expiring,
        isTrue,
      );
      expect(
        WarrantyLogic.statusOf(
          DateTime(far.year, far.month, far.day),
          today,
        ).expiring,
        isFalse,
      );
    });

    test('the time of day on either side changes nothing', () {
      // End stored at midnight; now is the afternoon of the same day.
      expect(
        WarrantyLogic.statusOf(DateTime(2026, 10, 20, 0, 0), today).daysLeft,
        8,
      );
      // Now before the end's calendar day.
      expect(
        WarrantyLogic.statusOf(DateTime(2026, 10, 20), DateTime(2026, 10, 12)),
        isNot((expired: true, expiring: false, daysLeft: 0)),
      );
    });
  });

  group('the end after the purchase', () {
    test('same day or later', () {
      expect(
        WarrantyLogic.endAfterPurchase(
          DateTime(2026, 1, 10),
          DateTime(2026, 1, 10),
        ),
        isTrue,
      );
      expect(
        WarrantyLogic.endAfterPurchase(
          DateTime(2026, 1, 10),
          DateTime(2026, 7, 10),
        ),
        isTrue,
      );
      expect(
        WarrantyLogic.endAfterPurchase(
          DateTime(2026, 1, 10),
          DateTime(2025, 12, 31),
        ),
        isFalse,
      );
    });
  });

  group('money', () {
    test('rials as tomans, exactly', () {
      expect(WarrantyLogic.tomans(30000000), '3000000');
      expect(WarrantyLogic.tomans(15), '1.5');
      expect(WarrantyLogic.tomans(10), '1');
      expect(WarrantyLogic.tomans(0), '0');
    });

    test('tomans a person typed, as exact rials', () {
      expect(WarrantyLogic.rialsFromTomans(3000000), 30000000);
      expect(WarrantyLogic.rialsFromTomans(0), 0);
      expect(WarrantyLogic.rialsFromTomans(-1), isNull);
    });

    test('grouped in threes for reading', () {
      expect(WarrantyLogic.grouped(30000000), '30,000,000');
      expect(WarrantyLogic.grouped(1000), '1,000');
      expect(WarrantyLogic.grouped(999), '999');
      expect(WarrantyLogic.grouped(0), '0');
    });
  });

  group('search and order', () {
    final bodies = [
      {'product': 'Kettle', 'brand': 'Boma'},
      {'product': 'کتری برقی', 'brand': 'فلر'},
      {'product': 'Phone', 'brand': 'Samsung'},
    ];

    test('by product or brand, case-blind, Persian included', () {
      expect(
        bodies.where((b) => WarrantyLogic.matchesQuery(b, 'kettle')),
        hasLength(1),
      );
      expect(
        bodies.where((b) => WarrantyLogic.matchesQuery(b, 'SAMSUNG')),
        hasLength(1),
      );
      expect(
        bodies.where((b) => WarrantyLogic.matchesQuery(b, 'کتری')),
        hasLength(1),
      );
      expect(
        bodies.where((b) => WarrantyLogic.matchesQuery(b, ' ')),
        hasLength(3),
      );
    });

    test('soonest coverage end first', () {
      final unordered = [
        {'product': 'a', 'coverageEnd': '2027-01-01T00:00:00'},
        {'product': 'b', 'coverageEnd': '2026-11-01T00:00:00'},
        {'product': 'c', 'coverageEnd': '2026-12-01T00:00:00'},
      ];
      expect(WarrantyLogic.soonestFirst(unordered).map((b) => b['product']), [
        'b',
        'c',
        'a',
      ]);
    });

    test('long names order and match like any other', () {
      final long = List.filled(50, 'نام').join();
      expect(WarrantyLogic.matchesQuery({'product': long}, long), isTrue);
    });
  });
}
