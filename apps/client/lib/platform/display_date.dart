import 'package:nex_core/nex_core.dart';

export 'package:nex_core/nex_core.dart'
    show
        nexDigits,
        nexDisplayDate,
        nexPersianDate,
        nexGregorianDate,
        nexPersianMonthDays;

const _faGregorianMonths = [
  'ژانویه',
  'فوریه',
  'مارس',
  'آوریل',
  'مه',
  'ژوئن',
  'ژوئیه',
  'اوت',
  'سپتامبر',
  'اکتبر',
  'نوامبر',
  'دسامبر',
];
const _enGregorianMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "20 Mehr 1405" or "12 October 2026" — the month in words, which reads at
/// a glance where "1405/07/20" has to be worked out. With [time], the hour
/// and minute follow, and never the seconds: they are for the Details list,
/// not for a heading.
String nexReadableDate(
  DateTime value, {
  required bool solar,
  required bool persian,
  bool time = false,
}) {
  final local = value.toLocal();
  final String date;
  if (solar) {
    final d = nexPersianDate(local);
    final month = persian
        ? nexPersianMonthNames[d.month - 1]
        : nexPersianMonthNamesLatin[d.month - 1];
    date = '${d.day} $month ${d.year}';
  } else {
    final month = persian
        ? _faGregorianMonths[local.month - 1]
        : _enGregorianMonths[local.month - 1];
    date = '${local.day} $month ${local.year}';
  }
  final clock =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  return nexDigits(time ? '$date · $clock' : date, persian: persian);
}
