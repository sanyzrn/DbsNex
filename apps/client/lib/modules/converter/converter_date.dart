import 'package:nex_client/modules/module_api.dart';

import 'converter_number.dart';

/// The three calendars a person in Iran meets in a normal week: the Solar
/// Hijri (Jalali) one the app itself uses, the Gregorian one on forms and
/// tickets, and the Lunar Hijri one for religious occasions.
enum ConverterCalendar { solar, gregorian, lunar }

/// The years this module covers.
///
/// Not a limit of the lunar arithmetic, which runs for millennia, but of the
/// Jalali code the app owns: it is the app's own conversion
/// (`nexPersianDate` / `nexGregorianDate`) or nothing, so the module can
/// never disagree with the rest of Nex about a date. Two centuries either
/// side of today is every date a person will type here.
const converterFirstCivilYear = 1900;
const converterLastCivilYear = 2100;

/// One day, named in one calendar.
///
/// A day is only worth having when it exists in its own calendar *and* inside
/// [converterFirstCivilYear]–[converterLastCivilYear]; [civilDay] answers null
/// otherwise, and the screen says so instead of guessing.
class ConverterDate {
  const ConverterDate(this.calendar, this.year, this.month, this.day);

  /// [day] written in [calendar], or null when it falls outside the years
  /// this module covers.
  static ConverterDate? of(DateTime day, ConverterCalendar calendar) {
    final civil = DateTime(day.year, day.month, day.day);
    if (civil.year < converterFirstCivilYear ||
        civil.year > converterLastCivilYear) {
      return null;
    }
    switch (calendar) {
      case ConverterCalendar.gregorian:
        return ConverterDate(calendar, civil.year, civil.month, civil.day);
      case ConverterCalendar.solar:
        final jalali = nexPersianDate(civil);
        return ConverterDate(calendar, jalali.year, jalali.month, jalali.day);
      case ConverterCalendar.lunar:
        final lunar = converterLunarFromCivil(civil);
        return ConverterDate(calendar, lunar.year, lunar.month, lunar.day);
    }
  }

  /// Today, in [calendar].
  static ConverterDate today(ConverterCalendar calendar) {
    final now = DateTime.now();
    return of(now, calendar) ??
        ConverterDate(calendar, now.year, now.month, now.day);
  }

  /// A date typed as `year/month/day`, in [calendar], or null when it is not
  /// a real day. Persian, Arabic and Latin digits all read; `/`, `-`, `.` and
  /// a space all separate.
  ///
  /// Also the other ways a date is written (2.7.1): the day first, as on an
  /// ID card or a Gregorian form (`27/11/1365`), and the month by its name,
  /// in Persian or English (`۲۷ بهمن ۱۳۶۵`, `16 Feb 1987`). The year is the
  /// part with three or more digits, or past 31; with neither, year first,
  /// as the field's hint shows.
  static ConverterDate? parse(String text, ConverterCalendar calendar) {
    var latin = converterLatinDigits(text)
        .replaceAll('\u060C', ' ')
        .replaceAll(',', ' ');
    // Names first, before the separators split «ربیع الاول» or "Rabi I" in
    // two: each becomes one token, `@3`, that the split leaves whole.
    for (final (index, pattern) in _monthPatterns(calendar).indexed) {
      latin = latin.replaceAll(pattern, ' @${index + 1} ');
    }
    final parts = latin
        .trim()
        .split(RegExp(r'[/\-.\s]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length != 3) return null;
    int? year, month, day;
    if (parts[1].startsWith('@')) {
      month = int.tryParse(parts[1].substring(1));
      final a = int.tryParse(parts[0]);
      final b = int.tryParse(parts[2]);
      if (a == null || b == null) return null;
      final yearFirst = parts[0].length >= 3 || a > 31;
      year = yearFirst ? a : b;
      day = yearFirst ? b : a;
    } else {
      final numbers = [for (final part in parts) int.tryParse(part)];
      if (numbers.any((n) => n == null)) return null;
      final dayFirst =
          parts[0].length <= 2 &&
          numbers[0]! <= 31 &&
          (parts[2].length >= 3 || numbers[2]! > 31);
      year = dayFirst ? numbers[2] : numbers[0];
      month = numbers[1];
      day = dayFirst ? numbers[0] : numbers[2];
    }
    if (year == null || month == null || day == null) return null;
    final candidate = ConverterDate(calendar, year, month, day);
    return candidate.civilDay == null ? null : candidate;
  }

  /// One pattern per month of [calendar], matching any of its names as a
  /// whole word: any case; a space, half-space or hyphen inside a name, or
  /// none; the Arabic ي and ك for ی and ک.
  static List<RegExp> _monthPatterns(ConverterCalendar calendar) =>
      _patterns[calendar] ??= [
        for (final spellings in switch (calendar) {
          ConverterCalendar.solar => _solarNames,
          ConverterCalendar.gregorian => _gregorianNames,
          ConverterCalendar.lunar => _lunarNames,
        })
          RegExp(
            '(?<!\\p{L})(?:${_alternatives(spellings)})(?!\\p{L})',
            caseSensitive: false,
            unicode: true,
          ),
      ];

  static final _patterns = <ConverterCalendar, List<RegExp>>{};

  /// The longest spelling first, so "March" is not read as "Mar" and a dot.
  static String _alternatives(List<String> spellings) => ([
    ...spellings,
  ]..sort((a, b) => b.length - a.length)).map(_spellingPattern).join('|');

  static String _spellingPattern(String spelling) {
    final out = StringBuffer();
    for (final char in spelling.split('')) {
      out.write(switch (char) {
        ' ' || '\u200c' || '-' => '[\\s\u200c\\-]?',
        "'" => "['’ʿ]?",
        'ی' => '[یي]',
        'ک' => '[کك]',
        _ => RegExp.escape(char),
      });
    }
    return out.toString();
  }

  final ConverterCalendar calendar;
  final int year;
  final int month;
  final int day;

  /// The same day as a local civil date — the day the phone's clock and the
  /// rest of the app count in — or null when it does not exist here.
  DateTime? get civilDay {
    switch (calendar) {
      case ConverterCalendar.gregorian:
        if (month < 1 || month > 12) return null;
        if (day < 1 || day > DateTime(year, month + 1, 0).day) return null;
        return _inRange(DateTime(year, month, day));
      case ConverterCalendar.solar:
        if (year < 1 ||
            month < 1 ||
            month > 12 ||
            day < 1 ||
            day > nexPersianMonthDays(year, month)) {
          return null;
        }
        return _inRange(nexGregorianDate(year, month, day));
      case ConverterCalendar.lunar:
        if (year < 1 ||
            month < 1 ||
            month > 12 ||
            day < 1 ||
            day > converterLunarMonthDays(year, month)) {
          return null;
        }
        final civil = _jdnToCivil(_lunarToJdn(year, month, day));
        return _inRange(DateTime(civil.year, civil.month, civil.day));
    }
  }

  static DateTime? _inRange(DateTime day) =>
      day.year < converterFirstCivilYear || day.year > converterLastCivilYear
      ? null
      : day;

  /// How many days this month has in its own calendar.
  int get monthLength => switch (calendar) {
    ConverterCalendar.gregorian => DateTime(year, month + 1, 0).day,
    ConverterCalendar.solar => nexPersianMonthDays(year, month),
    ConverterCalendar.lunar => converterLunarMonthDays(year, month),
  };

  /// The day number in the Julian day count — what makes "days between" and
  /// "add ten days" one subtraction and one addition, with no daylight
  /// saving to trip over.
  int? get _dayNumber {
    final civil = civilDay;
    return civil == null ? null : _civilToJdn(civil);
  }

  /// This day in another calendar, or null when it is outside the module's
  /// years.
  ConverterDate? inCalendar(ConverterCalendar other) {
    final civil = civilDay;
    return civil == null ? null : of(civil, other);
  }

  /// This day moved by [days] (negative for earlier), in the same calendar.
  ConverterDate? addDays(int days) {
    final number = _dayNumber;
    if (number == null) return null;
    final moved = _jdnToCivil(number + days);
    return of(DateTime(moved.year, moved.month, moved.day), calendar);
  }

  /// Whole days from this day to [other]: positive when [other] is later.
  int? daysUntil(ConverterDate other) {
    final from = _dayNumber;
    final to = other._dayNumber;
    if (from == null || to == null) return null;
    return to - from;
  }

  /// `year/month/day` in Latin digits — what the field writes back, and the
  /// form a record keeps.
  String get numeric => '$year/${nexPad2(month)}/${nexPad2(day)}';

  /// The civil day as `yyyy-mm-dd`, for comparing two records.
  String get isoKey {
    final civil = civilDay;
    if (civil == null) return numeric;
    return '${civil.year.toString().padLeft(4, '0')}-'
        '${nexPad2(civil.month)}-${nexPad2(civil.day)}';
  }

  @override
  bool operator ==(Object other) =>
      other is ConverterDate &&
      other.calendar == calendar &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(calendar, year, month, day);

  @override
  String toString() => '${calendar.name} $numeric';
}

/// Month names the field reads, in each calendar's order.
const _solarNames = [
  ['فروردین', 'Farvardin'],
  ['اردیبهشت', 'Ordibehesht'],
  ['خرداد', 'Khordad'],
  ['تیر', 'Tir'],
  ['مرداد', 'امرداد', 'Mordad'],
  ['شهریور', 'Shahrivar'],
  ['مهر', 'Mehr'],
  ['آبان', 'Aban'],
  ['آذر', 'Azar'],
  ['دی', 'Dey', 'Dei'],
  ['بهمن', 'Bahman'],
  ['اسفند', 'Esfand'],
];
const _gregorianNames = [
  ['ژانویه', 'January', 'Jan'],
  ['فوریه', 'February', 'Feb'],
  ['مارس', 'March', 'Mar'],
  ['آوریل', 'April', 'Apr'],
  ['مه', 'می', 'May'],
  ['ژوئن', 'June', 'Jun'],
  ['ژوئیه', 'جولای', 'July', 'Jul'],
  ['اوت', 'آگوست', 'August', 'Aug'],
  ['سپتامبر', 'September', 'Sept', 'Sep'],
  ['اکتبر', 'October', 'Oct'],
  ['نوامبر', 'November', 'Nov'],
  ['دسامبر', 'December', 'Dec'],
];
const _lunarNames = [
  ['محرم', 'Muharram'],
  ['صفر', 'Safar'],
  ['ربیع‌الاول', 'Rabi I', "Rabi' al-Awwal"],
  ['ربیع‌الثانی', 'ربیع‌الآخر', 'Rabi II', "Rabi' al-Thani"],
  ['جمادی‌الاول', 'جمادی‌الاولی', 'Jumada I'],
  ['جمادی‌الثانی', 'جمادی‌الآخر', 'Jumada II'],
  ['رجب', 'Rajab'],
  ['شعبان', "Sha'ban"],
  ['رمضان', 'Ramadan', 'Ramazan'],
  ['شوال', 'Shawwal'],
  ['ذی‌القعده', "Dhu al-Qi'dah"],
  ['ذی‌الحجه', 'Dhu al-Hijjah'],
];

/* -------------------------------------------------------------------------
 * The lunar (qamari) calendar.
 *
 * Iran's official lunar dates are announced after a moon sighting, so no
 * arithmetic can reproduce them exactly: the Encyclopaedia Iranica notes that
 * computed almanac dates can differ from the announced ones by a day or two.
 * The module therefore uses the tabular (arithmetical) Islamic calendar — the
 * one every calculator means by "the Islamic calendar": a 30-year cycle with
 * eleven leap years. It is deterministic, has no data table to go stale, and
 * against 32 official Iranian month starts from 1440 to 1447 AH it was exact
 * 21 times and one day out 11 times — never two. The screen always says so.
 * ---------------------------------------------------------------------- */

/// 1 Muharram 1 AH in the Julian day count: Friday 16 July 622 in the Julian
/// calendar, 19 July 622 in the proleptic Gregorian one.
const _lunarEpoch = 1948440;

int _civilToJdn(DateTime day) {
  final a = (14 - day.month) ~/ 12;
  final y = day.year + 4800 - a;
  final m = day.month + 12 * a - 3;
  return day.day +
      (153 * m + 2) ~/ 5 +
      365 * y +
      y ~/ 4 -
      y ~/ 100 +
      y ~/ 400 -
      32045;
}

({int year, int month, int day}) _jdnToCivil(int jdn) {
  final a = jdn + 32044;
  final b = (4 * a + 3) ~/ 146097;
  final c = a - (146097 * b) ~/ 4;
  final d = (4 * c + 3) ~/ 1461;
  final e = c - (1461 * d) ~/ 4;
  final m = (5 * e + 2) ~/ 153;
  return (
    year: 100 * b + d - 4800 + m ~/ 10,
    month: m + 3 - 12 * (m ~/ 10),
    day: e - (153 * m + 2) ~/ 5 + 1,
  );
}

int _lunarToJdn(int year, int month, int day) =>
    _lunarEpoch +
    (year - 1) * 354 +
    (3 + 11 * year) ~/ 30 +
    29 * (month - 1) +
    month ~/ 2 +
    day -
    1;

({int year, int month, int day}) _jdnToLunar(int jdn) {
  final days = jdn - _lunarEpoch;
  final year = (30 * days + 10646) ~/ 10631;
  final left = days - ((year - 1) * 354 + (3 + 11 * year) ~/ 30);
  final month = (11 * left + 330) ~/ 325;
  final day = left - (29 * (month - 1) + month ~/ 2) + 1;
  return (year: year, month: month, day: day);
}

/// The lunar day that falls on [civil].
({int year, int month, int day}) converterLunarFromCivil(DateTime civil) =>
    _jdnToLunar(_civilToJdn(civil));

/// The civil day [year]-[month]-[day] falls on in the lunar calendar.
({int year, int month, int day}) converterLunarToCivil(
  int year,
  int month,
  int day,
) => _jdnToCivil(_lunarToJdn(year, month, day));

/// Whether lunar [year] is a leap year — twelve 30-day months instead of one
/// 29-day Dhu al-Hijja.
bool converterLunarLeapYear(int year) => (11 * year + 14) % 30 < 11;

/// How many days lunar [month] has in [year]. Asked of the calendar itself —
/// the day before the next month starts — so it can never disagree with the
/// conversions above.
int converterLunarMonthDays(int year, int month) {
  if (month < 1 || month > 12) throw RangeError('Lunar month');
  final start = _lunarToJdn(year, month, 1);
  final next = month == 12
      ? _lunarToJdn(year + 1, 1, 1)
      : _lunarToJdn(year, month + 1, 1);
  return next - start;
}
