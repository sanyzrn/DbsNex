import 'package:nex_client/modules/module_api.dart';

import 'models.dart';
import 'units.dart';

/// The car-specific arithmetic: insurance and inspection countdowns, the
/// fuel month (a Jalali month for a solar reader), and the text forms of
/// litres and tomans. No price, rate or legal date is known by the module —
/// every number here comes from a record the person wrote.
class CarLogic {
  const CarLogic._();

  /// How many days from [now] to [date]; negative when it has passed.
  static int? daysLeft(DateTime? date, DateTime now) =>
      date == null ? null : daysBetween(dayOf(now), dayOf(date));

  /// The moment a reminder should ring: [days] before [date], in the
  /// morning. The sheet refuses a moment already in the past.
  static DateTime reminderAt(DateTime date, int days) => DateTime(
    date.year,
    date.month,
    date.day,
    9,
  ).subtract(Duration(days: days));

  static bool reminderFits(DateTime date, int days, DateTime now) =>
      days >= 0 &&
      days <= 365 &&
      reminderAt(date, days).isAfter(now) &&
      !dayOf(date).isBefore(dayOf(now));

  /// The month a fill-up belongs to: the Jalali year and month for a solar
  /// reader, the civil one otherwise. A fuel quota is a monthly allowance,
  /// so the month is the person's month, not a rolling 30 days.
  static int monthKey(DateTime date, {required bool solar}) {
    if (!solar) return date.year * 100 + date.month;
    final p = nexPersianDate(date);
    return p.year * 100 + p.month;
  }

  static bool inMonth(DateTime date, DateTime now, {required bool solar}) =>
      monthKey(date, solar: solar) == monthKey(now, solar: solar);
}

/// What the fuel log adds up to this month.
class FuelMonthSummary {
  const FuelMonthSummary({required this.litresByRate, required this.priceRial});

  final Map<String, int> litresByRate;
  final int priceRial;

  int get litres =>
      litresByRate.values.fold(0, (total, litres) => total + litres);

  int usedFor(Iterable<FuelRate> rates) {
    var total = 0;
    for (final rate in rates) {
      total += litresByRate[rate.name] ?? 0;
    }
    return total;
  }

  int leftFor(FuelRate rate) => rate.quota - (litresByRate[rate.name] ?? 0);
}

/// This month's fuel, from the entries only. A malformed record never adds
/// to a total; it is simply not a [FuelEntry].
FuelMonthSummary fuelMonthSummary(
  Iterable<FuelEntry> entries,
  DateTime now, {
  required bool solar,
}) {
  final litres = <String, int>{};
  var price = 0;
  for (final entry in entries) {
    if (!CarLogic.inMonth(entry.date, now, solar: solar)) continue;
    litres[entry.rate] = (litres[entry.rate] ?? 0) + entry.litres;
    price += entry.priceRial;
  }
  return FuelMonthSummary(litresByRate: litres, priceRial: price);
}

/// Litres as typed: up to three decimals, grouped in the interface's digits.
String formatLitres(int milli, {required bool persian}) =>
    formatMeterValue(milli, scale: 1000, persian: persian);

/// A rial amount shown in tomans, exactly: `1,250` or `1,250.5`, never a
/// rounded or silently converted number.
String formatToman(int rial, {required bool persian}) {
  final whole = rial ~/ 10;
  final tenth = rial % 10;
  final grouped = groupDigits('$whole', persian: persian);
  if (tenth == 0) return grouped;
  return '$grouped.${persian ? persianDigits('$tenth') : '$tenth'}';
}

/// Toman typed by a person as an exact number of rials. `12,500` tomans is
/// 125,000 rials; more than one decimal of a toman cannot be a rial amount,
/// so it is refused instead of rounded.
int? rialFromTomanInput(String input) {
  final milli = parseMeterInput(nexUngroupMoney(input));
  if (milli == null || milli % 100 != 0) return null;
  return milli ~/ 100;
}
