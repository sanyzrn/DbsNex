import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/smoke_free/money_format.dart';
import 'package:nex_client/modules/smoke_free/currency_scales.dart';
import 'package:nex_client/modules/smoke_free/number_input.dart';

void main() {
  test('currency scales and every supported amount round-trip exactly', () {
    expect(currencyScales.length, greaterThan(150));
    for (final entry in currencyScales.entries) {
      for (final minor in [0, 1, 12345, maxMoney]) {
        expect(
          parseMoney(moneyInput(minor, entry.value), entry.value),
          minor,
          reason: entry.key,
        );
      }
    }
    expect(moneyDigits('IRR'), 0);
    expect(moneyDigits('USD'), 2);
    expect(moneyDigits('JPY'), 0);
    expect(moneyDigits('KWD'), 3);
    expect(moneyDigits('CLF'), 4);
  });
  test('localized and grouped decimal input is exact', () {
    expect(parseMoney('۱٬۲۳۴٫۵۶', 2), 123456);
    expect(parseMoney('١٢٫٣٤٥', 3), 12345);
    expect(parseMoney('1,234.50', 2), 123450);
    expect(parseMoney('100', 0), 100);
    expect(parseWhole('−۱۴', signed: true), -14);
  });
  test(
    'excess precision, ambiguity, negatives and out-of-range money are refused',
    () {
      for (final text in [
        '-1',
        '1e3',
        'NaN',
        'Infinity',
        '12,34',
        '1.234',
        '1..2',
        '1.',
        '',
      ]) {
        expect(parseMoney(text, 2), isNull, reason: text);
      }
      expect(parseMoney('0.1', 0), isNull);
      expect(parseMoney('9007199254740992', 0), isNull);
      expect(safeWhole(double.nan), 0);
      expect(safeWhole(double.infinity), 0);
      expect(safeWhole(1.5), 0);
    },
  );
  test('RTL formatting includes a stable currency identity', () {
    expect(formatMoney(123456, 'USD', 2, true), '۱٬۲۳۴٫۵۶ \u2066USD\u2069');
    expect(formatMoney(1, 'KWD', 3, false), '0.001 \u2066KWD\u2069');
    expect(formatRials(-1234, false), '−1,234');
  });
}
