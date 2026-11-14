import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/converter/converter_date.dart';

void main() {
  group('the solar calendar is the app\'s own', () {
    test('known days agree with nexPersianDate', () {
      expect(
        ConverterDate.of(
          DateTime(2026, 11, 13),
          ConverterCalendar.solar,
        )!.numeric,
        '1405/08/22',
      );
      expect(
        ConverterDate.of(
          DateTime(2026, 3, 21),
          ConverterCalendar.solar,
        )!.numeric,
        '1405/01/01',
      );
      expect(
        ConverterDate.of(
          DateTime(2025, 3, 20),
          ConverterCalendar.solar,
        )!.numeric,
        '1403/12/30',
      );
      expect(
        ConverterDate.of(
          DateTime(2026, 3, 20),
          ConverterCalendar.solar,
        )!.numeric,
        '1404/12/29',
      );
      expect(
        ConverterDate.of(
          DateTime(2024, 3, 20),
          ConverterCalendar.solar,
        )!.numeric,
        '1403/01/01',
      );
    });

    test('a leap Esfand is thirty days and a plain one is twenty-nine', () {
      expect(
        ConverterDate(ConverterCalendar.solar, 1403, 12, 30).civilDay,
        DateTime(2025, 3, 20),
      );
      expect(
        ConverterDate(ConverterCalendar.solar, 1404, 12, 30).civilDay,
        isNull,
      );
      expect(
        ConverterDate(ConverterCalendar.solar, 1405, 12, 30).civilDay,
        isNull,
      );
      expect(
        ConverterDate(ConverterCalendar.solar, 1408, 12, 30).civilDay,
        isNotNull,
      );
      expect(
        ConverterDate(ConverterCalendar.solar, 1405, 8, 22).monthLength,
        30,
      );
      expect(
        ConverterDate(ConverterCalendar.solar, 1405, 6, 1).monthLength,
        31,
      );
    });

    test('the edges of the range the app supports', () {
      expect(
        ConverterDate.of(DateTime(1899, 12, 31), ConverterCalendar.solar),
        isNull,
      );
      expect(
        ConverterDate.of(DateTime(2101, 1, 1), ConverterCalendar.solar),
        isNull,
      );
      expect(
        ConverterDate.of(DateTime(1900, 1, 1), ConverterCalendar.gregorian),
        isNotNull,
      );
      expect(
        ConverterDate.of(DateTime(2100, 12, 31), ConverterCalendar.gregorian),
        isNotNull,
      );
    });
  });

  group('the lunar calendar', () {
    test('starts on 19 July 622 in the proleptic Gregorian calendar', () {
      expect(converterLunarToCivil(1, 1, 1), (year: 622, month: 7, day: 19));
      expect(converterLunarFromCivil(DateTime(2026, 11, 13)), (
        year: 1448,
        month: 6,
        day: 2,
      ));
    });

    test('has eleven leap years in thirty, and months of 29 or 30', () {
      expect(converterLunarLeapYear(1445), isTrue);
      expect(converterLunarLeapYear(1446), isFalse);
      expect(converterLunarMonthDays(1445, 12), 30);
      expect(converterLunarMonthDays(1446, 12), 29);
      expect(converterLunarMonthDays(1445, 9), 30);
      expect(converterLunarMonthDays(1445, 10), 29);
      expect(() => converterLunarMonthDays(1445, 13), throwsRangeError);
    });

    test('every day of five years converts back to itself', () {
      var day = DateTime(2024, 1, 1);
      for (var index = 0; index < 1800; index++) {
        final lunar = converterLunarFromCivil(day);
        final back = converterLunarToCivil(lunar.year, lunar.month, lunar.day);
        expect(
          DateTime(back.year, back.month, back.day),
          day,
          reason: 'round trip on $day',
        );
        day = day.add(const Duration(days: 1));
      }
    });
  });

  group('moving between the calendars', () {
    test('a day is the same day in all three', () {
      final solar = ConverterDate(ConverterCalendar.solar, 1405, 8, 22);
      expect(solar.civilDay, DateTime(2026, 11, 13));
      expect(
        solar.inCalendar(ConverterCalendar.gregorian)!.numeric,
        '2026/11/13',
      );
      expect(solar.inCalendar(ConverterCalendar.lunar)!.numeric, '1448/06/02');
      final back = ConverterDate(ConverterCalendar.lunar, 1448, 6, 2);
      expect(back.inCalendar(ConverterCalendar.solar)!.numeric, '1405/08/22');
    });

    test('days can be added and counted, in the calendar you started in', () {
      final day = ConverterDate(ConverterCalendar.solar, 1405, 8, 22);
      expect(day.addDays(10)!.numeric, '1405/09/02');
      expect(day.addDays(-10)!.numeric, '1405/08/12');
      expect(day.addDays(45)!.numeric, '1405/10/07');
      expect(day.daysUntil(day.addDays(45)!), 45);
      expect(day.addDays(45)!.daysUntil(day), -45);
      expect(day.daysUntil(day), 0);
      final acrossYear = ConverterDate(
        ConverterCalendar.gregorian,
        2024,
        2,
        28,
      );
      expect(acrossYear.addDays(1)!.numeric, '2024/02/29');
      expect(acrossYear.addDays(2)!.numeric, '2024/03/01');
      expect(
        ConverterDate(
          ConverterCalendar.gregorian,
          2026,
          12,
          31,
        ).addDays(1)!.numeric,
        '2027/01/01',
      );
    });

    test('a date the calendar does not have is not a date', () {
      expect(
        ConverterDate(ConverterCalendar.solar, 1405, 13, 1).civilDay,
        isNull,
      );
      expect(
        ConverterDate(ConverterCalendar.solar, 1405, 8, 31).civilDay,
        isNull,
      );
      expect(
        ConverterDate(ConverterCalendar.gregorian, 2026, 2, 29).civilDay,
        isNull,
      );
      expect(
        ConverterDate(ConverterCalendar.lunar, 1446, 12, 30).civilDay,
        isNull,
      );
      expect(
        ConverterDate(ConverterCalendar.lunar, 1445, 12, 30).civilDay,
        isNotNull,
      );
    });
  });

  group('a typed date', () {
    test('reads Persian, Arabic and Latin digits and four separators', () {
      expect(
        ConverterDate.parse('1405/08/22', ConverterCalendar.solar)!.numeric,
        '1405/08/22',
      );
      expect(
        ConverterDate.parse('۱۴۰۵/۰۸/۲۲', ConverterCalendar.solar)!.numeric,
        '1405/08/22',
      );
      expect(
        ConverterDate.parse('١٤٠٥/٠٨/٢٢', ConverterCalendar.solar)!.numeric,
        '1405/08/22',
      );
      expect(
        ConverterDate.parse('2026-11-13', ConverterCalendar.gregorian)!.numeric,
        '2026/11/13',
      );
      expect(
        ConverterDate.parse('2026.11.13', ConverterCalendar.gregorian)!.numeric,
        '2026/11/13',
      );
      expect(
        ConverterDate.parse('2026 11 13', ConverterCalendar.gregorian)!.numeric,
        '2026/11/13',
      );
      expect(
        ConverterDate.parse('1448/06/02', ConverterCalendar.lunar)!.numeric,
        '1448/06/02',
      );
    });

    test('anything else is nothing, never a guess', () {
      expect(ConverterDate.parse('', ConverterCalendar.solar), isNull);
      expect(ConverterDate.parse('1405/08', ConverterCalendar.solar), isNull);
      expect(
        ConverterDate.parse('1405/08/22/1', ConverterCalendar.solar),
        isNull,
      );
      expect(
        ConverterDate.parse('1405/13/01', ConverterCalendar.solar),
        isNull,
      );
      expect(ConverterDate.parse('hello', ConverterCalendar.solar), isNull);
      expect(
        ConverterDate.parse('1800/01/01', ConverterCalendar.gregorian),
        isNull,
      );
      expect(
        ConverterDate.parse('2101/01/01', ConverterCalendar.gregorian),
        isNull,
      );
    });

    test('the numeric form is what the field and the record keep', () {
      expect(
        ConverterDate(ConverterCalendar.solar, 1405, 8, 2).numeric,
        '1405/08/02',
      );
      expect(
        ConverterDate(ConverterCalendar.gregorian, 2026, 11, 13).isoKey,
        '2026-11-13',
      );
    });
  });

  group('a date written the other ways people write one (2.7.1)', () {
    ConverterDate? solar(String text) =>
        ConverterDate.parse(text, ConverterCalendar.solar);

    test('an old solar date, in any digits', () {
      for (final text in ['1365/11/27', '۱۳۶۵/۱۱/۲۷', '١٣٦٥-١١-٢٧']) {
        expect(solar(text)?.civilDay, DateTime(1987, 2, 16), reason: text);
      }
    });

    test('the day first, as on an ID card', () {
      expect(solar('27/11/1365')?.numeric, '1365/11/27');
      expect(
        ConverterDate.parse('16.02.1987', ConverterCalendar.gregorian)?.numeric,
        '1987/02/16',
      );
    });

    test('the month by its name', () {
      expect(solar('۲۷ بهمن ۱۳۶۵')?.numeric, '1365/11/27');
      expect(solar('27 Bahman 1365')?.numeric, '1365/11/27');
      expect(solar('۱۳۶۵ بهمن ۲۷')?.numeric, '1365/11/27');
      expect(solar('۱ دی ۱۴۰۰')?.numeric, '1400/10/01');
      expect(solar('۱ مهر ۱۴۰۰')?.numeric, '1400/07/01', reason: 'not مه');
      expect(
        ConverterDate.parse(
          '16 Feb 1987',
          ConverterCalendar.gregorian,
        )?.numeric,
        '1987/02/16',
      );
      expect(
        ConverterDate.parse('March 3, 2026', ConverterCalendar.gregorian),
        isNull,
        reason: 'the month first is not a form the field reads',
      );
      expect(
        ConverterDate.parse(
          '3 March 2026',
          ConverterCalendar.gregorian,
        )?.numeric,
        '2026/03/03',
      );
    });

    test('lunar names with spaces, half-spaces and Arabic letters', () {
      ConverterDate? lunar(String text) =>
          ConverterDate.parse(text, ConverterCalendar.lunar);
      expect(lunar('۱۲ ربیع‌الاول ۱۴۴۷')?.month, 3);
      expect(lunar('۱۲ ربیع الاول ۱۴۴۷')?.month, 3);
      expect(lunar('12 Rabi II 1447')?.month, 4);
      expect(lunar('12 Rabi I 1447')?.month, 3);
      expect(lunar('۱ ذي‌الحجه ۱۴۴۶')?.month, 12);
    });

    test('still nothing for what is not a date', () {
      expect(solar('۲۷ بهمن'), isNull);
      expect(solar('بهمن ۲۷ ۱۳۶۵'), isNull);
      expect(solar('1365/13/01'), isNull);
      expect(solar('hello world now'), isNull);
    });
  });
}
