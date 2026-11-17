import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/lent_borrowed/irr_unit.dart';
import 'package:nex_client/modules/lent_borrowed/money_format.dart';
import 'package:nex_client/modules/lent_borrowed/money_input.dart';
import 'package:nex_client/modules/lent_borrowed/money_words.dart';

/// Saying money out loud, in both languages: the words a Persian speaker
/// actually reads, and the rules Persian numbers follow — «و» between every
/// part, «صد» and «هزار» standing alone, «هزار میلیارد» for 10¹².
void main() {
  group('Persian numbers in words', () {
    const cases = <int, String>{
      0: 'صفر',
      1: 'یک',
      9: 'نه',
      10: 'ده',
      11: 'یازده',
      19: 'نوزده',
      20: 'بیست',
      21: 'بیست و یک',
      99: 'نود و نه',
      100: 'صد',
      101: 'صد و یک',
      110: 'صد و ده',
      345: 'سیصد و چهل و پنج',
      999: 'نهصد و نود و نه',
      1000: 'هزار',
      1001: 'هزار و یک',
      1100: 'هزار و صد',
      1200: 'هزار و دویست',
      12345: 'دوازده هزار و سیصد و چهل و پنج',
      100000: 'صد هزار',
      1200000: 'یک میلیون و دویست هزار',
      2345678: 'دو میلیون و سیصد و چهل و پنج هزار و ششصد و هفتاد و هشت',
    };
    for (final MapEntry(key: value, value: words) in cases.entries) {
      test('$value is «$words»', () {
        expect(persianNumberWords(value), words);
      });
    }

    test('the scale words run to hundreds of billions', () {
      expect(persianNumberWords(1000000000), 'یک میلیارد');
      expect(persianNumberWords(2500000000), 'دو میلیارد و پانصد میلیون');
      expect(
        persianNumberWords(123456789012),
        'صد و بیست و سه میلیارد و چهارصد و پنجاه و شش میلیون و '
        'هفتصد و هشتاد و نه هزار و دوازده',
      );
      expect(persianNumberWords(456000000000), 'چهارصد و پنجاه و شش میلیارد');
    });

    test('10¹² is «هزار میلیارد», never «تریلیون»', () {
      expect(persianNumberWords(1000000000000), 'هزار میلیارد');
      expect(persianNumberWords(3000000000000), 'سه هزار میلیارد');
    });

    test('the largest amount the module stores still has words', () {
      expect(
        persianNumberWords(maxMoney),
        'نه میلیون میلیارد و هفت هزار میلیارد و صد و نود و نه میلیارد و '
        'دویست و پنجاه و چهار میلیون و هفتصد و چهل هزار و نهصد و نود و یک',
      );
    });

    test('a stray negative keeps its sign rather than saying nonsense', () {
      expect(persianNumberWords(-1200), '−هزار و دویست');
    });
  });

  group('English numbers in words', () {
    test('the short scale, hyphenated between twenty and ninety-nine', () {
      expect(englishNumberWords(0), 'zero');
      expect(englishNumberWords(1), 'one');
      expect(englishNumberWords(21), 'twenty-one');
      expect(englishNumberWords(100), 'one hundred');
      expect(englishNumberWords(101), 'one hundred one');
      expect(englishNumberWords(1000), 'one thousand');
      expect(englishNumberWords(1200000), 'one million two hundred thousand');
      expect(
        englishNumberWords(2345678),
        'two million three hundred forty-five thousand six hundred '
        'seventy-eight',
      );
      expect(englishNumberWords(1000000000), 'one billion');
      expect(
        englishNumberWords(123456789012),
        'one hundred twenty-three billion four hundred fifty-six million '
        'seven hundred eighty-nine thousand twelve',
      );
    });
  });

  group('an amount in words', () {
    test('toman and rial say the same stored amount differently', () {
      // 500,000 rials is 50,000 tomans.
      expect(
        amountInWords(
          minor: 500000,
          digits: 1,
          persian: true,
          unit: 'تومان',
          unitOne: 'تومان',
        ),
        'پنجاه هزار تومان',
      );
      expect(
        amountInWords(minor: 500000, digits: 0, persian: false, unit: 'rials'),
        'five hundred thousand rials',
      );
    });

    test('one is singular, and a fraction is never dropped', () {
      expect(
        amountInWords(
          minor: 10,
          digits: 1,
          persian: true,
          unit: 'تومان',
          unitOne: 'تومان',
        ),
        'یک تومان',
      );
      expect(
        amountInWords(
          minor: 1,
          digits: 0,
          persian: false,
          unit: 'rials',
          unitOne: 'rial',
        ),
        'one rial',
      );
      // 50,000.5 tomans: half a toman, which is five rials.
      expect(
        amountInWords(
          minor: 500005,
          digits: 1,
          persian: true,
          unit: 'تومان',
          unitOne: 'تومان',
        ),
        'پنجاه هزار تومان و پنج دهم',
      );
      expect(
        amountInWords(
          minor: 1234,
          digits: 2,
          persian: false,
          unit: 'dollars',
          unitOne: 'dollar',
        ),
        'twelve dollars and thirty-four hundredths',
      );
    });
  });

  group('the unit words', () {
    test('the rial is spoken as toman or rial, never as IRR', () {
      expect(currencyUnitWord('IRR', IrrUnit.toman, persian: false), 'tomans');
      expect(currencyUnitWord('IRR', IrrUnit.rial, persian: true), 'ریال');
      expect(currencyUnitWord('USD', IrrUnit.toman, persian: true), 'دلار');
    });

    test('an unknown code is said as itself, never guessed', () {
      expect(currencyUnitWord('XTS', IrrUnit.toman, persian: true), 'XTS');
    });
  });

  group('formatting and parsing in the chosen unit', () {
    test('a stored rial amount reads as toman or rial', () {
      expect(
        formatAmount(500000, 'IRR', 0, false, IrrUnit.toman),
        '50,000 tomans',
      );
      expect(
        formatAmount(500000, 'IRR', 0, false, IrrUnit.rial),
        '500,000 rials',
      );
      expect(formatAmount(1, 'IRR', 0, false, IrrUnit.rial), '1 rial');
      expect(formatAmount(50000, 'IRR', 0, true, IrrUnit.toman), '۵٬۰۰۰ تومان');
      // A half-toman is one rial, and is shown as such rather than hidden.
      expect(
        formatAmount(500005, 'IRR', 0, false, IrrUnit.toman),
        '50,000.5 tomans',
      );
    });

    test('a foreign currency keeps its code and its own precision', () {
      expect(
        formatAmount(123456, 'USD', 2, false, IrrUnit.toman),
        '1,234.56 \u2066USD\u2069',
      );
      expect(
        formatAmount(1, 'KWD', 3, false, IrrUnit.toman),
        '0.001 \u2066KWD\u2069',
      );
    });

    test('what is typed in toman is stored as rials, exactly', () {
      expect(parseAmount('50,000', 'IRR', 0, IrrUnit.toman), 500000);
      expect(parseAmount('50000', 'IRR', 0, IrrUnit.toman), 500000);
      expect(parseAmount('50000.1', 'IRR', 0, IrrUnit.toman), 500001);
      expect(parseAmount('0.5', 'IRR', 0, IrrUnit.toman), 5);
      expect(parseAmount('500000', 'IRR', 0, IrrUnit.rial), 500000);
      expect(parseAmount('1.23', 'USD', 2, IrrUnit.toman), 123);
    });

    test('more precision than the unit has is refused, not rounded', () {
      expect(parseAmount('50000.05', 'IRR', 0, IrrUnit.toman), isNull);
      expect(parseAmount('500000.5', 'IRR', 0, IrrUnit.rial), isNull);
      expect(parseAmount('', 'IRR', 0, IrrUnit.toman), isNull);
      expect(parseAmount('abc', 'IRR', 0, IrrUnit.toman), isNull);
      expect(parseAmount('-5', 'IRR', 0, IrrUnit.toman), isNull);
      expect(
        parseAmount('9007199254740992', 'IRR', 0, IrrUnit.rial),
        isNull,
        reason: 'beyond the exact range a new amount may use',
      );
    });

    test('every stored amount survives the trip through the field', () {
      for (final unit in IrrUnit.values) {
        for (final value in [
          0,
          1,
          5,
          10,
          500000,
          500005,
          123456789,
          maxMoney,
        ]) {
          final text = amountInput(value, 'IRR', 0, unit);
          expect(
            parseAmount(text, 'IRR', 0, unit),
            value,
            reason: '$unit $value',
          );
        }
      }
    });

    test('the field text keeps whole numbers whole', () {
      expect(amountInput(500000, 'IRR', 0, IrrUnit.toman), '50000');
      expect(amountInput(500005, 'IRR', 0, IrrUnit.toman), '50000.5');
      expect(amountInput(500000, 'IRR', 0, IrrUnit.rial), '500000');
    });
  });

  group('grouping while typing', () {
    test('thousands are grouped as the number grows', () {
      expect(groupAmountText('5', 0), '5');
      expect(groupAmountText('50', 0), '50');
      expect(groupAmountText('500', 0), '500');
      expect(groupAmountText('5000', 0), '5,000');
      expect(groupAmountText('500000', 0), '500,000');
      expect(groupAmountText('1200000000', 0), '1,200,000,000');
    });

    test('only digits and one separator survive', () {
      expect(groupAmountText('12a34', 0), '1,234');
      expect(groupAmountText('1,2,3', 0), '123');
      expect(groupAmountText('0007', 0), '7');
      expect(groupAmountText('0', 0), '0');
      expect(groupAmountText('', 0), '');
      expect(groupAmountText('5.4.3', 1), '5.4');
      expect(groupAmountText('50,000.55', 1), '50,000.5');
      expect(groupAmountText('50,000', 0), '50,000');
    });

    test('Persian and Arabic digits are kept as typed', () {
      expect(groupAmountText('۱۲۳۴', 0), '۱,۲۳۴');
      expect(groupAmountText('١٢٣٤', 0), '١,٢٣٤');
    });

    test('on the Persian side the field itself reads in Persian', () {
      expect(groupAmountText('1200000', 0, persian: true), '۱٬۲۰۰٬۰۰۰');
      expect(groupAmountText('1234.5', 1, persian: true), '۱٬۲۳۴٫۵');
      expect(groupAmountText('', 0, persian: true), '');
      // What the field shows is what the parser reads back, either script.
      expect(parseAmount('۱٬۲۰۰٬۰۰۰', 'IRR', 0, IrrUnit.toman), 12000000);
      expect(parseAmount('1,200,000', 'IRR', 0, IrrUnit.toman), 12000000);
      expect(parseAmount('۱٬۲۳۴٫۵', 'USD', 2, IrrUnit.toman), 123450);
    });

    test('the caret stays where the person was typing', () {
      expect(groupAmountEdit('500000', 6, 0), (text: '500,000', caret: 7));
      expect(groupAmountEdit('500000', 3, 0), (text: '500,000', caret: 3));
      expect(groupAmountEdit('50000.5', 7, 1), (text: '50,000.5', caret: 8));
    });
  });
}
