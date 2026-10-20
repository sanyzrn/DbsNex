import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/occasions/occasion_math.dart';
import 'package:nex_client/modules/occasions/occasion_model.dart';

Occasion occasion({
  OccasionCalendar calendar = OccasionCalendar.gregorian,
  required int month,
  required int day,
  int? year,
  bool nextDay = false,
  OccasionKind kind = OccasionKind.birthday,
}) => Occasion(
  id: 'o1',
  title: 'Sara',
  kind: kind,
  calendar: calendar,
  month: month,
  day: day,
  year: year,
  nextDayInShortYears: nextDay,
  createdAt: DateTime(2026),
);

void main() {
  group('a Gregorian date returns on its Gregorian day', () {
    test('later this year, and next year once it has passed', () {
      final o = occasion(month: 12, day: 25);
      expect(
        nextOccasionDay(o, DateTime(2026, 10, 20))!.date,
        DateTime(2026, 12, 25),
      );
      expect(
        nextOccasionDay(o, DateTime(2026, 12, 26))!.date,
        DateTime(2027, 12, 25),
      );
    });

    test('the day itself is today, not next year', () {
      final o = occasion(month: 10, day: 20);
      final next = nextOccasionDay(o, DateTime(2026, 10, 20, 23, 59))!;
      expect(next.date, DateTime(2026, 10, 20));
      expect(daysUntil(DateTime(2026, 10, 20, 23, 59), next.date), 0);
    });

    test('29 February: the last day of February, or 1 March, as chosen', () {
      final last = occasion(month: 2, day: 29);
      final next = occasion(month: 2, day: 29, nextDay: true);
      expect(occasionIn(last, 2027)!.date, DateTime(2027, 2, 28));
      expect(occasionIn(next, 2027)!.date, DateTime(2027, 3, 1));
      // In a leap year it is the day itself, whatever was chosen.
      expect(occasionIn(last, 2028)!.date, DateTime(2028, 2, 29));
      expect(occasionIn(next, 2028)!.date, DateTime(2028, 2, 29));
      // 1900 was not a leap year; 2000 was.
      expect(occasionIn(last, 1900)!.date, DateTime(1900, 2, 28));
      expect(occasionIn(last, 2000)!.date, DateTime(2000, 2, 29));
    });

    test('30 February and 31 April never exist', () {
      expect(occasionIn(occasion(month: 2, day: 30), 2028), isNull);
      expect(occasionIn(occasion(month: 4, day: 31), 2028), isNull);
      expect(
        nextOccasionDay(occasion(month: 2, day: 30), DateTime(2026)),
        isNull,
      );
    });
  });

  group('a Jalali date returns on its Jalali day', () {
    const jalali = OccasionCalendar.jalali;

    test('15 Mehr is 7 October in 1405 and 7 October-ish next year', () {
      final o = occasion(calendar: jalali, month: 7, day: 15);
      final a = nextOccasionDay(o, DateTime(2026, 10, 20))!;
      // 15 Mehr 1405 = 7 October 2026 has passed; the next is 15 Mehr 1406.
      expect(a.calendarYear, 1406);
      expect(a.date, DateTime(2027, 10, 7));
      final b = nextOccasionDay(o, DateTime(2026, 9, 1))!;
      expect(b.calendarYear, 1405);
      expect(b.date, DateTime(2026, 10, 7));
    });

    test('Nowruz stays on 1 Farvardin however the Gregorian date moves', () {
      final o = occasion(calendar: jalali, month: 1, day: 1);
      final dates = [
        for (var year = 1403; year <= 1408; year++) occasionIn(o, year)!.date,
      ];
      // 21 March in some years, 20 in others; never 1 Farvardin changing.
      expect(dates.map((d) => d.month), everyElement(3));
      expect(dates.map((d) => d.day).toSet().length, greaterThan(1));
      for (final d in dates) {
        expect(
          nextOccasionDay(o, d.subtract(const Duration(days: 1)))!.date,
          d,
        );
      }
    });

    test('30 Esfand: last day in a short year, 1 Farvardin if chosen', () {
      final last = occasion(calendar: jalali, month: 12, day: 30);
      final next = occasion(
        calendar: jalali,
        month: 12,
        day: 30,
        nextDay: true,
      );
      // 1403 is a leap year (30 Esfand exists); 1404 is not.
      final leapDay = occasionIn(last, 1403)!;
      expect(leapDay.date, DateTime(2025, 3, 20));
      final short = occasionIn(last, 1404)!;
      expect(short.date, DateTime(2026, 3, 20));
      final rolled = occasionIn(next, 1404)!;
      expect(rolled.date, DateTime(2026, 3, 21));
      expect(rolled.calendarYear, 1404);
    });

    test('a 1 Farvardin that belongs to last year still counts as upcoming', () {
      final next = occasion(
        calendar: jalali,
        month: 12,
        day: 30,
        nextDay: true,
      );
      // On the last day of 1404 the "30 Esfand 1404" occurrence is 1 Farvardin
      // 1405 — tomorrow-ish, and must be found, not skipped.
      final found = nextOccasionDay(next, DateTime(2026, 3, 19))!;
      expect(found.date, DateTime(2026, 3, 21));
    });
  });

  group('age and years', () {
    test('known year: the age it comes to', () {
      final o = occasion(
        calendar: OccasionCalendar.jalali,
        month: 7,
        day: 15,
        year: 1378,
      );
      final next = nextOccasionDay(o, DateTime(2026, 10, 20))!;
      expect(yearsAt(o, next), 1406 - 1378);
    });

    test('unknown year: no age, none guessed', () {
      final o = occasion(month: 7, day: 15);
      expect(yearsAt(o, nextOccasionDay(o, DateTime(2026, 1, 1))!), isNull);
    });

    test('a start year that is not before it gives no age', () {
      final o = occasion(month: 12, day: 25, year: 2026);
      expect(yearsAt(o, occasionIn(o, 2026)!), isNull);
      expect(yearsAt(o, occasionIn(o, 2027)!), 1);
    });
  });

  group('the form\'s questions', () {
    test('which days exist, before and after the year is known', () {
      const greg = OccasionCalendar.gregorian;
      const jal = OccasionCalendar.jalali;
      expect(dayExistsSomeYear(greg, 2, 29), isTrue);
      expect(dayExistsSomeYear(greg, 2, 30), isFalse);
      expect(dayExistsSomeYear(greg, 4, 31), isFalse);
      expect(dayExistsSomeYear(jal, 6, 31), isTrue);
      expect(dayExistsSomeYear(jal, 7, 31), isFalse);
      expect(dayExistsSomeYear(jal, 12, 30), isTrue);
      expect(dayExistsIn(greg, 2027, 2, 29), isFalse);
      expect(dayExistsIn(greg, 2028, 2, 29), isTrue);
      expect(dayExistsIn(jal, 1404, 12, 30), isFalse);
      expect(dayExistsIn(jal, 1403, 12, 30), isTrue);
    });

    test('only 29 Feb and 30 Esfand can fall short', () {
      expect(canFallShort(OccasionCalendar.gregorian, 2, 29), isTrue);
      expect(canFallShort(OccasionCalendar.gregorian, 2, 28), isFalse);
      expect(canFallShort(OccasionCalendar.jalali, 12, 30), isTrue);
      expect(canFallShort(OccasionCalendar.jalali, 12, 29), isFalse);
    });

    test('a picked Gregorian day, written in the occasion\'s calendar', () {
      final d = dateIn(OccasionCalendar.jalali, DateTime(2026, 10, 7));
      expect((d.year, d.month, d.day), (1405, 7, 15));
      final g = dateIn(OccasionCalendar.gregorian, DateTime(2026, 10, 7));
      expect((g.year, g.month, g.day), (2026, 10, 7));
    });
  });

  group('reading a record', () {
    test('defaults are safe; nothing invented', () {
      final o = Occasion.fromBody('x', {
        'title': ' Ali ',
        'month': 13,
        'day': 5,
      });
      expect(o.title, 'Ali');
      expect(o.valid, isFalse);
      expect(o.kind, OccasionKind.other);
      expect(o.year, isNull);
      expect(nextOccasionDay(o, DateTime(2026)), isNull);
    });

    test('unknown fields do not break it; year can be marked unknown', () {
      final o = Occasion.fromBody('x', {
        'title': 'T',
        'kind': 'birthday',
        'calendar': 'jalali',
        'month': 7,
        'day': 15,
        'yearKnown': false,
        'year': 1378,
        'future': {'a': 1},
        'remindDays': 3,
      });
      expect(o.year, isNull);
      expect(o.calendar, OccasionCalendar.jalali);
      expect(o.remindDays, 3);
      expect(o.toJson()['yearKnown'], false);
      expect(o.toJson().containsKey('year'), isFalse);
    });
  });
}
