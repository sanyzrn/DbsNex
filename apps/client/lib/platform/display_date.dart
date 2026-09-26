// Persian New Year calculation adapted from jalaali-js v1.2.8 (MIT).
// https://github.com/jalaali/jalaali-js/tree/v1.2.8
// Copyright (c) 2020 Behrang Norouzinia.
// See third_party/jalaali-js-LICENSE.txt.

String nexDigits(String text, {required bool persian}) => !persian
    ? text
    : text.replaceAllMapped(
        RegExp(r'[0-9]'),
        (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)],
      );

({int year, int month, int day}) nexPersianDate(DateTime value) {
  final date = DateTime.utc(value.year, value.month, value.day);
  var year = value.year - 621;
  var start = DateTime.utc(year + 621, 3, _marchDay(year));
  if (date.isBefore(start)) {
    year--;
    start = DateTime.utc(year + 621, 3, _marchDay(year));
  }
  final days = date.difference(start).inDays;
  return days < 186
      ? (year: year, month: 1 + days ~/ 31, day: 1 + days % 31)
      : (year: year, month: 7 + (days - 186) ~/ 30, day: 1 + (days - 186) % 30);
}

int _marchDay(int year) {
  const breaks = [
    -61,
    9,
    38,
    199,
    426,
    686,
    756,
    818,
    1111,
    1181,
    1210,
    1635,
    2060,
    2097,
    2192,
    2262,
    2324,
    2394,
    2456,
    3178,
  ];
  if (year < breaks.first || year >= breaks.last) {
    throw RangeError('Persian calendar year');
  }
  var previous = breaks.first;
  var leap = -14;
  var jump = 0;
  for (final next in breaks.skip(1)) {
    jump = next - previous;
    if (year < next) break;
    leap += (jump ~/ 33) * 8 + (jump % 33) ~/ 4;
    previous = next;
  }
  final n = year - previous;
  leap += (n ~/ 33) * 8 + ((n % 33) + 3) ~/ 4;
  if (jump % 33 == 4 && jump - n == 4) leap++;
  final gregorian = year + 621;
  final gregorianLeap =
      gregorian ~/ 4 - (((gregorian ~/ 100) + 1) * 3) ~/ 4 - 150;
  return 20 + leap - gregorianLeap;
}

String nexDisplayDate(
  DateTime value, {
  bool solar = false,
  bool persian = false,
  bool time = false,
  bool seconds = false,
}) {
  final local = value.toLocal();
  final date = solar && local.year >= 561 && local.year <= 3797
      ? nexPersianDate(local)
      : (year: local.year, month: local.month, day: local.day);
  String two(int v) => v.toString().padLeft(2, '0');
  final text =
      '${date.year}/${two(date.month)}/${two(date.day)}'
      '${time ? '  ${two(local.hour)}:${two(local.minute)}${seconds ? ':${two(local.second)}' : ''}' : ''}';
  return nexDigits(text, persian: persian);
}
