import 'package:nex_client/modules/module_api.dart';

import 'occasion_model.dart';

/// One time an occasion falls: the civil date it lands on, and which year of
/// its own calendar that is (what an age is counted from).
typedef OccasionDay = ({DateTime date, int calendarYear});

int _gregorianMonthDays(int year, int month) =>
    DateTime.utc(year, month + 1, 0).day;

/// Where [occasion] lands in [calendarYear] of its own calendar, or null if
/// it cannot (an impossible date, or a year the calendar code cannot reach).
///
/// A day a year lacks — 29 February, 30 Esfand — falls on the last day of
/// that month, or on the first day of the next one if the person chose so.
/// Nothing rolls over by accident: `DateTime(2027, 2, 29)` would quietly be
/// 1 March, and that is only right when it was asked for.
OccasionDay? occasionIn(Occasion occasion, int calendarYear) {
  if (!occasion.valid) return null;
  try {
    if (occasion.calendar == OccasionCalendar.gregorian) {
      if (calendarYear < 1 || calendarYear > 9999) return null;
      final length = _gregorianMonthDays(calendarYear, occasion.month);
      if (occasion.day <= length) {
        return (
          date: DateTime(calendarYear, occasion.month, occasion.day),
          calendarYear: calendarYear,
        );
      }
      // Only 29 February can be missing (30 and 31 never exist in
      // February, and every other month holds its own days).
      if (occasion.month != 2 || occasion.day != 29) return null;
      return (
        date: occasion.nextDayInShortYears
            ? DateTime(calendarYear, 3)
            : DateTime(calendarYear, 2, length),
        calendarYear: calendarYear,
      );
    }
    final length = nexPersianMonthDays(calendarYear, occasion.month);
    if (occasion.day <= length) {
      return (
        date: nexGregorianDate(calendarYear, occasion.month, occasion.day),
        calendarYear: calendarYear,
      );
    }
    if (occasion.month != 12 || occasion.day != 30) return null;
    return (
      date: occasion.nextDayInShortYears
          ? nexGregorianDate(calendarYear + 1, 1, 1)
          : nexGregorianDate(calendarYear, 12, length),
      calendarYear: calendarYear,
    );
  } on RangeError {
    return null;
  }
}

/// The year of [occasion]'s calendar that [day] falls in.
int calendarYearOf(Occasion occasion, DateTime day) =>
    occasion.calendar == OccasionCalendar.jalali
    ? nexPersianDate(day).year
    : day.year;

/// The next [count] times [occasion] falls on or after [today], nearest
/// first. Empty for an invalid date.
List<OccasionDay> upcomingDays(Occasion occasion, DateTime today, int count) {
  final from = DateTime(today.year, today.month, today.day);
  final start = calendarYearOf(occasion, from);
  final found = <OccasionDay>[];
  // One year back covers a 1 Farvardin that belongs to the year before; a
  // few ahead cover the count asked for.
  for (var year = start - 1; year <= start + count + 1; year++) {
    final day = occasionIn(occasion, year);
    if (day != null && !day.date.isBefore(from)) found.add(day);
  }
  found.sort((a, b) => a.date.compareTo(b.date));
  return found.take(count).toList();
}

/// The next time [occasion] falls on or after [today], or null.
OccasionDay? nextOccasionDay(Occasion occasion, DateTime today) {
  final days = upcomingDays(occasion, today, 1);
  return days.isEmpty ? null : days.first;
}

/// Whole civil days from [today] to [date]; DST cannot shift it.
int daysUntil(DateTime today, DateTime date) => DateTime.utc(
  date.year,
  date.month,
  date.day,
).difference(DateTime.utc(today.year, today.month, today.day)).inDays;

/// The age (or the year of the marriage…) the occasion comes to on [day]:
/// null when the start year is unknown or is not before it.
int? yearsAt(Occasion occasion, OccasionDay day) {
  final start = occasion.year;
  if (start == null) return null;
  final years = day.calendarYear - start;
  return years >= 1 ? years : null;
}

/// Whether this date can fall short in some year (29 Feb, 30 Esfand), which
/// is when the choice between the last day and the next one matters.
bool canFallShort(OccasionCalendar calendar, int month, int day) =>
    calendar == OccasionCalendar.gregorian
    ? month == 2 && day == 29
    : month == 12 && day == 30;

/// [date] written as a day and month of [calendar]'s own year, for a form to
/// fill in: the Gregorian date a picker gives, expressed in the occasion's
/// calendar.
({int year, int month, int day}) dateIn(
  OccasionCalendar calendar,
  DateTime date,
) => calendar == OccasionCalendar.jalali
    ? nexPersianDate(date)
    : (year: date.year, month: date.month, day: date.day);

/// Whether [day] of [month] exists in some year of [calendar] — what a form
/// may accept before the year is known.
bool dayExistsSomeYear(OccasionCalendar calendar, int month, int day) {
  if (month < 1 || month > 12 || day < 1) return false;
  if (calendar == OccasionCalendar.gregorian) {
    return day <= (month == 2 ? 29 : _gregorianMonthDays(2001, month));
  }
  return day <= (month <= 6 ? 31 : 30);
}

/// Whether [day] of [month] exists in [year] of [calendar].
bool dayExistsIn(OccasionCalendar calendar, int year, int month, int day) {
  if (!dayExistsSomeYear(calendar, month, day)) return false;
  try {
    return calendar == OccasionCalendar.gregorian
        ? day <= _gregorianMonthDays(year, month)
        : day <= nexPersianMonthDays(year, month);
  } on RangeError {
    return false;
  }
}
