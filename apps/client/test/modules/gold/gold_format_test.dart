import 'package:flutter_test/flutter_test.dart';

import 'package:nex_client/modules/gold/gold_format.dart';

/// The module's number layer: parsing what a person typed (in either
/// script), and showing scaled integers back in the language's digits.
void main() {
  group('parseScaled', () {
    test('plain decimals at their scale', () {
      expect(parseScaled('3', 3), 3000);
      expect(parseScaled('3.125', 3), 3125);
      expect(parseScaled('10,000,000'.replaceAll(',', ''), 2), 1000000000);
      expect(parseScaled('1234.5', 2), 123450);
      expect(parseScaled('0.001', 3), 1);
    });

    test('Persian digits and the Persian decimal separator parse the same', () {
      expect(parseScaled('۳٫۱۲۵', 3), 3125);
      expect(parseScaled('۷', 2), 700);
      expect(parseScaled('۱۰,۰۰۰,۰۰۰'.replaceAll(',', ''), 2), 1000000000);
    });

    test('whitespace and a leading plus are forgiven', () {
      expect(parseScaled('  7  ', 2), 700);
      expect(parseScaled('+7.25', 2), 725);
    });

    test('empty is null', () {
      expect(parseScaled('', 2), isNull);
      expect(parseScaled('   ', 2), isNull);
    });

    test('nonsense is null, not zero', () {
      expect(parseScaled('abc', 2), isNull);
      expect(parseScaled('1.2.3', 2), isNull);
      expect(parseScaled('.', 2), isNull);
      expect(parseScaled('-.', 2), isNull);
    });

    test('a comma is rejected rather than guessed about', () {
      // Half the world means a decimal point, the other half a thousands
      // separator. Guessing misprices jewelry; refusing does not.
      expect(parseScaled('1,5', 2), isNull);
      expect(parseScaled('1,234', 0), isNull);
    });

    test('negatives parse as negative — validation rejects them later', () {
      expect(parseScaled('-5', 2), -500);
    });
  });

  group('parseScaledDetailed', () {
    test('the reasons come back for the field to put into words', () {
      expect(parseScaledDetailed('', 2).$2, GoldParseProblem.empty);
      expect(parseScaledDetailed('abc', 2).$2, GoldParseProblem.invalid);
      expect(
        parseScaledDetailed('1.234', 2).$2,
        GoldParseProblem.tooManyDecimals,
      );
      expect(parseScaledDetailed('-1', 2).$2, GoldParseProblem.negative);
      expect(
        parseScaledDetailed('۱٫۲۳۴', 2).$2,
        GoldParseProblem.tooManyDecimals,
      );
      expect(parseScaledDetailed('1.2', 2).$1, 120);
    });
  });

  group('groupDigits', () {
    test('English grouping', () {
      expect(groupDigits(0, persian: false), '0');
      expect(groupDigits(358410000, persian: false), '358,410,000');
      expect(groupDigits(-410000, persian: false), '-410,000');
    });

    test('Persian digits with the Persian thousands mark', () {
      expect(groupDigits(358410000, persian: true), '۳۵۸٬۴۱۰٬۰۰۰');
      expect(groupDigits(12, persian: true), '۱۲');
      expect(groupDigits(-410000, persian: true), '−۴۱۰٬۰۰۰');
    });
  });

  group('groupDecimal and formatPercent', () {
    test('decimals keep their fraction digits', () {
      expect(groupDecimal(1234, 5, 2, persian: false), '1,234.05');
      expect(groupDecimal(0, 5, 2, persian: false), '0.05');
      expect(groupDecimal(3, 125, 3, persian: false), '3.125');
    });

    test('Persian decimals use «٫» and Persian digits', () {
      expect(groupDecimal(1234, 5, 2, persian: true), '۱٬۲۳۴٫۰۵');
    });

    test('a whole percent has no fraction; otherwise two decimals', () {
      expect(formatPercent(700, persian: false), '7%');
      expect(formatPercent(725, persian: false), '7.25%');
      expect(formatPercent(0, persian: false), '0%');
      expect(formatPercent(-44, persian: false), '-0.44%');
    });

    test('Persian percents use «٪»', () {
      expect(formatPercent(700, persian: true), '۷٪');
      expect(formatPercent(725, persian: true), '۷٫۲۵٪');
    });
  });

  group('formatWeightMg and formatRial', () {
    test('weights show grams with soot as the third decimal', () {
      expect(formatWeightMg(3000, persian: false), '3');
      expect(formatWeightMg(3125, persian: false), '3.125');
      expect(formatWeightMg(3125, persian: true), '۳٫۱۲۵');
      expect(formatWeightMg(1, persian: false), '0.001');
    });

    test('rials shown as rials are exact', () {
      expect(formatRial(358410000, persian: false, rials: true), '358,410,000');
      expect(formatRial(358410000, persian: true, rials: true), '۳۵۸٬۴۱۰٬۰۰۰');
    });

    test('rials shown as toman convert exactly, decimals when they matter', () {
      expect(formatRial(358410000, persian: false, rials: false), '35,841,000');
      expect(formatRial(5, persian: false, rials: false), '0.5');
      expect(formatRial(15, persian: false, rials: false), '1.5');
      expect(formatRial(-5, persian: false, rials: false), '-0.5');
      expect(formatRial(-15, persian: false, rials: false), '-1.5');
    });

    test('a centi-toman rate shows as toman', () {
      expect(formatCentiRate(1000000000, persian: false), '10,000,000');
      expect(formatCentiRate(1000000050, persian: false), '10,000,000.50');
      expect(formatCentiRate(1000000050, persian: true), '۱۰٬۰۰۰٬۰۰۰٫۵۰');
    });
  });

  group('dates', () {
    test('real Gregorian days pass; made-up ones fail', () {
      expect(isIsoDate('2026-10-12'), isTrue);
      expect(isIsoDate('2024-02-29'), isTrue); // a leap day
      expect(isIsoDate('2023-02-29'), isFalse);
      expect(isIsoDate('2026-02-30'), isFalse);
      expect(isIsoDate('2026-13-01'), isFalse);
      expect(isIsoDate('2026-4-1'), isFalse);
      expect(isIsoDate('12-10-2026'), isFalse);
      expect(isIsoDate(''), isFalse);
    });

    test('isoDay pads itself', () {
      expect(isoDay(DateTime(2026, 10, 2)), '2026-10-02');
    });

    test('relative day words: today, yesterday, a count, then the date', () {
      final now = DateTime(2026, 10, 12, 15, 30);
      String words(DateTime saved) => relativeDayWords(
        saved,
        now,
        today: () => 'today',
        yesterday: () => 'yesterday',
        daysAgo: (days) => '$days days ago',
        onDate: (date) => 'on $date',
      );
      expect(words(DateTime(2026, 10, 12, 1, 0)), 'today');
      expect(words(DateTime(2026, 10, 11, 23, 0)), 'yesterday');
      expect(words(DateTime(2026, 10, 2)), '10 days ago');
      expect(words(DateTime(2026, 8, 20)), 'on 2026-08-20');
      // A saved moment from the future (clock skew) still reads as today.
      expect(words(DateTime(2026, 10, 12, 23, 59)), 'today');
    });
  });
}
