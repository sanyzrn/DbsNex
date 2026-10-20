import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart'
    show nexPersianMonthNames, nexPersianMonthNamesLatin;
import 'package:nex_ui/nex_ui.dart' show NexSpacing;
import '../platform/display_date.dart';
import '../widgets/nex_time_picker.dart';

/// The app's time picker, for a module's own reminder rows.
Future<TimeOfDay?> nexPickModuleTime(
  BuildContext context, {
  required TimeOfDay initial,
}) => nexPickTime(context, initial: initial);

class NexModuleCalendar extends InheritedWidget {
  const NexModuleCalendar({
    super.key,
    required this.solar,
    required super.child,
  });
  final bool solar;
  static bool solarOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NexModuleCalendar>()?.solar ??
      (Localizations.localeOf(context).languageCode == 'fa');
  @override
  bool updateShouldNotify(NexModuleCalendar oldWidget) =>
      solar != oldWidget.solar;
}

Future<DateTime?> nexPickModuleDate(
  BuildContext context, {
  required DateTime initial,
  required DateTime first,
  required DateTime last,
}) => nexPickDate(
  context,
  initial: initial,
  first: first,
  last: last,
  solar: NexModuleCalendar.solarOf(context),
);

String nexModuleDateLabel(BuildContext context, DateTime date) =>
    nexDisplayDate(
      date,
      solar: NexModuleCalendar.solarOf(context),
      persian: Localizations.localeOf(context).languageCode == 'fa',
    );

/// Existing civil text entry remains available. The calendar button lets a
/// person choose a Jalali day without changing record formats or parsers.
class NexModuleDateEntry extends StatelessWidget {
  const NexModuleDateEntry({
    super.key,
    required this.controller,
    required this.child,
    this.hyphenated = false,
  });
  final TextEditingController controller;
  final Widget child;
  final bool hyphenated;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: child),
      // Beside the field, not under it: a calendar button on a row
      // of its own read as belonging to nothing, and cost every form 48dp.
      Padding(
        padding: const EdgeInsetsDirectional.only(start: NexSpacing.xs, top: 4),
        child: IconButton(
          tooltip: MaterialLocalizations.of(context).datePickerHelpText,
          icon: const Icon(Icons.calendar_month_outlined),
          onPressed: () async {
            final parsed = DateTime.tryParse(
              controller.text.replaceAll('/', '-'),
            );
            final first = DateTime(1900), last = DateTime(2100, 12, 31);
            final candidate = parsed ?? DateTime.now();
            final picked = await nexPickModuleDate(
              context,
              initial: candidate.isBefore(first)
                  ? first
                  : candidate.isAfter(last)
                  ? last
                  : candidate,
              first: first,
              last: last,
            );
            if (picked == null || !context.mounted) return;
            final separator = hyphenated ? '-' : '/';
            controller.text =
                '${picked.year}$separator${picked.month.toString().padLeft(2, '0')}$separator${picked.day.toString().padLeft(2, '0')}';
          },
        ),
      ),
    ],
  );
}

const _gregorianMonthsEn = [
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
const _gregorianMonthsFa = [
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

/// The name of month [month] (1–12) in the calendar [solar] picks, in the
/// reader's language — «Mehr» / «مهر», «October» / «اکتبر».
String nexModuleMonthName(
  BuildContext context, {
  required bool solar,
  required int month,
}) {
  final persian = Localizations.localeOf(context).languageCode == 'fa';
  final index = (month.clamp(1, 12)) - 1;
  return solar
      ? (persian ? nexPersianMonthNames : nexPersianMonthNamesLatin)[index]
      : (persian ? _gregorianMonthsFa : _gregorianMonthsEn)[index];
}

/// One month of the calendar a person reads — Jalali or Gregorian — laid
/// out for a grid. The days are real civil days: a Jalali month starts on
/// the Gregorian date the calendar says it does, and ends on the one before
/// the next, so a record keyed by Gregorian date lands in the right cell.
class NexModuleMonth {
  const NexModuleMonth(this.solar, this.year, this.month);

  /// The month [day] falls in, in the calendar [solar] picks.
  factory NexModuleMonth.of(DateTime day, {required bool solar}) {
    if (!solar) return NexModuleMonth(false, day.year, day.month);
    final p = nexPersianDate(day);
    return NexModuleMonth(true, p.year, p.month);
  }

  final bool solar;
  final int year;
  final int month;

  /// The first day of the month, as a local civil date.
  DateTime get first =>
      solar ? nexGregorianDate(year, month, 1) : DateTime(year, month);

  int get days => solar
      ? nexPersianMonthDays(year, month)
      : DateTime(year, month + 1, 0).day;

  /// The civil date of day number [day] (1-based) in this month.
  DateTime dayAt(int day) =>
      solar ? nexGregorianDate(year, month, day) : DateTime(year, month, day);

  /// This month moved by [by] months (negative for earlier).
  NexModuleMonth shift(int by) {
    final index = year * 12 + (month - 1) + by;
    return NexModuleMonth(solar, index ~/ 12, index % 12 + 1);
  }

  /// Empty cells before day 1 when weeks start on [firstWeekday] (Dart's
  /// numbering: Monday 1 … Sunday 7).
  int leadingBlanks(int firstWeekday) =>
      (first.weekday - firstWeekday.clamp(1, 7)) % 7;

  /// «Mehr 1405» / «October 2026», in the reader's language and digits.
  String title(BuildContext context) {
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    final name = solar
        ? (persian ? nexPersianMonthNames : nexPersianMonthNamesLatin)[month -
              1]
        : (persian ? _gregorianMonthsFa : _gregorianMonthsEn)[month - 1];
    return nexDigits('$name $year', persian: persian);
  }

  @override
  bool operator ==(Object other) =>
      other is NexModuleMonth &&
      other.solar == solar &&
      other.year == year &&
      other.month == month;

  @override
  int get hashCode => Object.hash(solar, year, month);
}
