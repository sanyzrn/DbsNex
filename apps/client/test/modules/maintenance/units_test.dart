import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/maintenance/units.dart';

/// The measurement and calendar arithmetic: exact km⇄mi rationals,
/// the end-of-month month addition, leap days, and day boundaries.
void main() {
  group('kilometres and miles', () {
    test('convert exactly through the rational, rounded half up', () {
      // 1 mi = 25146/15625 km exactly: these are lossless.
      expect(kmToMi(25146), 15625);
      expect(miToKm(15625), 25146);
      expect(kmToMi(50292), 31250);
      expect(miToKm(31250), 50292);
      // Integer round trips are not lossless: 1000 km is 621.37 mi,
      // stored as 621, which is 999.4 km back — a unit of drift, by
      // design, because readings are integers.
      expect(kmToMi(1000), 621);
      expect(miToKm(621), 999);
    });

    test('known values round correctly', () {
      // 1 mile is 1.609344 km, so 1609 km is just under 1000 miles.
      expect(kmToMi(1609), 1000); // 999.79 → 1000 by half-up
      expect(kmToMi(1610), 1000); // 1000.41 → 1000
      expect(kmToMi(8047), 5000); // exactly ~5000 miles
      expect(kmToMi(100), 62); // 62.137 miles
      expect(kmToMi(200), 124); // 124.27 miles
      expect(miToKm(62), 100); // 99.779 → 100 by half-up
      expect(miToKm(100), 161); // 160.934
      expect(miToKm(0), 0);
      expect(kmToMi(0), 0);
    });

    test('same unit is identity; convertDistance dispatches', () {
      expect(convertDistance(500, DistanceUnit.km, DistanceUnit.km), 500);
      expect(convertDistance(500, DistanceUnit.mi, DistanceUnit.mi), 500);
      expect(
        convertDistance(100, DistanceUnit.km, DistanceUnit.mi),
        kmToMi(100),
      );
      expect(
        convertDistance(100, DistanceUnit.mi, DistanceUnit.km),
        miToKm(100),
      );
    });

    test('meter bounds', () {
      // The parse path enforces the cap: 1e9 whole units fit, anything
      // beyond it — or negative — is refused.
      expect(parseMeterInput('1000000000'), isNotNull);
      expect(parseMeterInput('1000000000.001'), isNull);
      expect(parseMeterInput('-1'), isNull);
    });
  });

  group('month addition', () {
    test('keeps the day when the month has it', () {
      expect(addMonths(DateTime(2026, 3, 15), 1), DateTime(2026, 4, 15));
      expect(addMonths(DateTime(2026, 1, 10), 11), DateTime(2026, 12, 10));
      expect(addMonths(DateTime(2026, 12, 10), 1), DateTime(2027, 1, 10));
      expect(addMonths(DateTime(2026, 12, 10), -1), DateTime(2026, 11, 10));
    });

    test('clamps to the month end — the documented convention', () {
      // 31 January + 1 month is 28/29 February, never 3 March.
      expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonths(DateTime(2024, 1, 31), 1), DateTime(2024, 2, 29));
      // 29 February + 12 months in a non-leap year.
      expect(addMonths(DateTime(2024, 2, 29), 12), DateTime(2025, 2, 28));
      expect(addMonths(DateTime(2024, 2, 29), 48), DateTime(2028, 2, 29));
      // 31 March + 1 month is 30 April.
      expect(addMonths(DateTime(2026, 3, 31), 1), DateTime(2026, 4, 30));
      // Going back across a short month clamps too.
      expect(addMonths(DateTime(2026, 3, 31), -1), DateTime(2026, 2, 28));
    });

    test('crosses years in both directions', () {
      expect(addMonths(DateTime(2026, 11, 5), 2), DateTime(2027, 1, 5));
      expect(addMonths(DateTime(2026, 1, 5), -2), DateTime(2025, 11, 5));
      expect(addMonths(DateTime(2026, 6, 15), 7), DateTime(2027, 1, 15));
    });
  });

  group('days and day boundaries', () {
    test('daysInMonth honours leap years', () {
      expect(daysInMonth(2024, 2), 29);
      expect(daysInMonth(2026, 2), 28);
      expect(daysInMonth(2026, 4), 30);
      expect(daysInMonth(2026, 12), 31);
      expect(daysInMonth(2000, 2), 29); // divisible by 400: leap
      expect(daysInMonth(1900, 2), 28); // divisible by 100 not 400: not
    });

    test('dayOf drops the time of day', () {
      expect(dayOf(DateTime(2026, 10, 13, 23, 59)), DateTime(2026, 10, 13));
      expect(dayOf(DateTime(2026, 10, 14, 0, 1)), DateTime(2026, 10, 14));
    });

    test('daysBetween counts whole days, time-insensitive', () {
      expect(
        daysBetween(DateTime(2026, 10, 1, 7), DateTime(2026, 10, 13, 23)),
        12,
      );
      expect(
        daysBetween(DateTime(2026, 10, 13, 23), DateTime(2026, 10, 1, 7)),
        -12,
      );
      expect(
        daysBetween(DateTime(2026, 10, 13, 0), DateTime(2026, 10, 13, 23)),
        0,
      );
    });

    test('addDays is calendar arithmetic', () {
      expect(addDays(DateTime(2026, 2, 27), 3), DateTime(2026, 3, 2));
      expect(addDays(DateTime(2024, 2, 27), 3), DateTime(2024, 3, 1));
    });
  });

  group('digit helpers', () {
    test('grouping and Persian digits', () {
      expect(groupDigits('1250000', persian: false), '1,250,000');
      expect(groupDigits('1250000', persian: true), '۱٬۲۵۰٬۰۰۰');
      expect(persianDigits('a1b2'), 'a۱b۲');
      expect(groupDigits('42', persian: false), '42');
    });
  });
}
