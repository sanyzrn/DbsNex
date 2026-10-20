/// Measurement and calendar arithmetic for the Maintenance Log: the
/// metre units an asset can count in, kilometre⇄mile conversion as
/// exact integer rationals (never floating point), and month addition
/// with a documented end-of-month convention.
///
/// A metre (odometer or hour counter) is an integer in the asset's
/// chosen unit. Kilometres and miles are **never** silently equated:
/// they convert only through [kmToMi]/[miToKm], which carry the exact
/// ratio 1 mi = 25146/15625 km, and every conversion result is
/// rounded half up and documented as such. Hours are never converted
/// into anything.
library;

import 'local_values.dart';

/// What an asset counts, if it counts at all.
enum MeterKind { none, distance, hours }

/// The distance unit an asset's odometer reads in.
enum DistanceUnit { km, mi }

/// 1 mile is exactly 25146/15625 kilometres (1609.344 m). These two
/// integers are the whole conversion; nothing here uses a double.
const _kmPerMiNumerator = 25146;
const _kmPerMiDenominator = 15625;

/// Rounds half up — the one rounding this module does, and it says so
/// wherever a conversion is shown.
int roundHalfUp(int value, int denominator) =>
    (value + denominator ~/ 2) ~/ denominator;

/// km → mi, exact rational, rounded half up to a whole unit.
int kmToMi(int km) => _convertRatio(km, _kmPerMiDenominator, _kmPerMiNumerator);

/// mi → km, exact rational, rounded half up to a whole unit.
int miToKm(int mi) => _convertRatio(mi, _kmPerMiNumerator, _kmPerMiDenominator);

/// The other side of a conversion, if [unit] has one.
int convertDistance(int value, DistanceUnit from, DistanceUnit to) => from == to
    ? value
    : (from == DistanceUnit.km ? kmToMi(value) : miToKm(value));

/// The bound every meter value carries: non-negative integers, capped so
/// arithmetic cannot overflow.
const meterMax = 1000000000; // 1e9 km / hours — beyond any odometer

/// Days in a month — February honours leap years.
int daysInMonth(int year, int month) {
  return DateTime.utc(year, month + 1, 0).day;
}

/// Adds [months] to [date]'s calendar month. The documented
/// end-of-month convention: **the day is kept when the target month
/// has it, and clamped to the target's last day when it does not** —
/// 31 January + 1 month is 28/29 February, not 3 March; 29 February
/// + 12 months is 28 February in a non-leap year.
DateTime addMonths(DateTime date, int months) {
  if (months.abs() > maxIntervalMonths) throw RangeError("Interval too large");
  final total = date.year * 12 + (date.month - 1) + months;
  final year = total ~/ 12;
  final month = total % 12 + 1;
  if (year < 1 || year > 9999) throw RangeError("Unsupported calendar year");
  final day = date.day > daysInMonth(year, month)
      ? daysInMonth(year, month)
      : date.day;
  return DateTime(year, month, day);
}

/// Adds [days] as calendar days.
DateTime addDays(DateTime date, int days) {
  if (days.abs() > maxIntervalDays) throw RangeError('Interval too large');
  final result = DateTime.utc(date.year, date.month, date.day + days);
  if (result.year < 1 || result.year > 9999) {
    throw RangeError('Unsupported calendar year');
  }
  return DateTime(result.year, result.month, result.day);
}

/// The day, without the time of day — the grain every due date and
/// grouping works at. A service logged at 07:00 and one logged at
/// 23:50 the same day are the same day.
DateTime dayOf(DateTime value) => DateTime(value.year, value.month, value.day);

/// Days from [a] to [b]: positive when [b] is later.
int daysBetween(DateTime a, DateTime b) =>
    LocalValues.civil(b).difference(LocalValues.civil(a)).inDays;

/// The unit's short label key in the module's strings — the words
/// themselves live there, not here.
String meterUnitLabelKey(DistanceUnit unit) =>
    unit == DistanceUnit.km ? 'unitKm' : 'unitMi';

String hoursLabelKey() => 'unitHours';

/// `1,250` → grouped digits in the locale's form. A local equivalent
/// of the app-wide helper, because the module API does not export it
/// (see README Platform requests). Same as the other modules keep.
String groupDigits(String digits, {required bool persian}) {
  final grouped = StringBuffer();
  var count = 0;
  for (var i = digits.length - 1; i >= 0; i--) {
    grouped.write(digits[i]);
    count++;
    if (count % 3 == 0 && i > 0) grouped.write(persian ? '٬' : ',');
  }
  final reversed = grouped.toString().split('').reversed.join('');
  return persian ? persianDigits(reversed) : reversed;
}

/// `123` → `۱۲۳`.
String persianDigits(String text) => text.replaceAllMapped(
  RegExp(r'[0-9]'),
  (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)],
);

const maxIntervalDays = 365250;
const maxIntervalMonths = 12000;
const meterScale = 1000;
const meterMilliMax = meterMax * meterScale;

int _convertRatio(int value, int numerator, int denominator) {
  if (value < 0 || value > LocalValues.maxExact) {
    throw RangeError('Unsupported meter');
  }
  final result =
      (BigInt.from(value) * BigInt.from(numerator) +
          BigInt.from(denominator) ~/ BigInt.two) ~/
      BigInt.from(denominator);
  if (result > BigInt.from(LocalValues.maxExact)) {
    throw RangeError('Converted meter too large');
  }
  return result.toInt();
}

int convertMilli(int milli, DistanceUnit from, DistanceUnit to) =>
    convertDistance(milli, from, to);
int? parseMeterInput(String input) {
  if (input.length > 20) return null;
  final text = LocalValues.ascii(input.trim());
  if (!RegExp(r'^\d+(?:\.\d{1,3})?$').hasMatch(text)) return null;
  final parts = text.split('.');
  final raw = parts[0] + (parts.length > 1 ? parts[1] : '').padRight(3, '0');
  final value = BigInt.tryParse(raw);
  return value != null && value <= BigInt.from(meterMilliMax)
      ? value.toInt()
      : null;
}

int? toMeterMilli(int? value, int scale) =>
    value == null ? null : value * (1000 ~/ scale);
String meterInputText(int value, {int scale = 1000}) {
  final milli = toMeterMilli(value, scale)!;
  final whole = milli ~/ 1000,
      fraction = (milli % 1000)
          .toString()
          .padLeft(3, '0')
          .replaceAll(RegExp(r'0+$'), '');
  return fraction.isEmpty ? '$whole' : '$whole.$fraction';
}

String formatMeterValue(int value, {int scale = 1000, required bool persian}) {
  final text = meterInputText(value, scale: scale), parts = text.split('.');
  final whole = groupDigits(parts[0], persian: persian);
  return parts.length == 1
      ? whole
      : '$whole.${persian ? persianDigits(parts[1]) : parts[1]}';
}

bool validMeterScale(Object? value) =>
    value is int && (value == 1 || value == 1000);
DateTime? maintenanceCalendar(Object? raw) {
  final civil = LocalValues.calendar(raw);
  return civil == null ? null : DateTime(civil.year, civil.month, civil.day);
}
