import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/converter/converter_number.dart';

void main() {
  group('reading a number', () {
    test('Latin, Persian and Arabic digits all read', () {
      expect(converterParseNumber('12.5'), 12.5);
      expect(converterParseNumber('۱۲٫۵'), 12.5);
      expect(converterParseNumber('١٢.٥'), 12.5);
      expect(converterParseNumber('١٢٣٤'), 1234);
      expect(converterLatinDigits('۱۴۰۵/۰۸/۲۲'), '1405/08/22');
    });

    test('signs, spaces and thousands separators are read', () {
      expect(converterParseNumber('-3'), -3);
      expect(converterParseNumber('\u221212'), -12);
      expect(converterParseNumber('1\u00A0234'), 1234);
      expect(converterParseNumber('1,234'), 1234);
      expect(converterParseNumber('1\u066C234'), 1234);
      expect(converterParseNumber(' 7 '), 7);
      expect(converterParseNumber('.5'), 0.5);
      expect(converterParseNumber('5.'), 5);
    });

    test('anything that is not a number answers null', () {
      expect(converterParseNumber(''), isNull);
      expect(converterParseNumber('   '), isNull);
      expect(converterParseNumber('.'), isNull);
      expect(converterParseNumber('-'), isNull);
      expect(converterParseNumber('1.2.3'), isNull);
      expect(converterParseNumber('12abc'), isNull);
      expect(converterParseNumber('1e9'), isNull);
      expect(converterParseNumber('١٢٣x'), isNull);
    });

    test('a very large number is still a number', () {
      expect(converterParseNumber('123456789012345'), 123456789012345);
    });
  });

  group('writing a number', () {
    test('trailing zeros are trimmed and small numbers stay readable', () {
      expect(converterFormatNumber(0, persian: false), '0');
      expect(converterFormatNumber(77, persian: false), '77');
      expect(
        converterFormatNumber(154.3235835294143, persian: false),
        '154.3236',
      );
      expect(
        converterFormatNumber(3.280839895013123, persian: false),
        '3.2808',
      );
      expect(
        converterFormatNumber(0.000000621371192237334, persian: false),
        '0.0000006214',
      );
      expect(converterFormatNumber(-12.5, persian: false), '-12.5');
    });

    test('thousands are grouped', () {
      expect(converterFormatNumber(1234567, persian: false), '1,234,567');
      expect(
        converterFormatNumber(1000000000, persian: false),
        '1,000,000,000',
      );
      expect(converterFormatNumber(1234.5, persian: false), '1,234.5');
    });

    test('the Persian side gets Persian digits and the Persian separator', () {
      expect(converterFormatNumber(154.3236, persian: true), '۱۵۴٫۳۲۳۶');
      expect(converterFormatNumber(1234567, persian: true), '۱٬۲۳۴٬۵۶۷');
      expect(converterFormatNumber(-12.5, persian: true), '-۱۲٫۵');
    });

    test('a value that is not finite is not written as a number', () {
      expect(converterFormatNumber(double.nan, persian: false), '—');
      expect(converterFormatNumber(double.infinity, persian: false), '—');
    });
  });
}
