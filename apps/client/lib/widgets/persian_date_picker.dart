import 'package:nex_ui/nex_ui.dart';
import 'package:flutter/material.dart';

import '../platform/display_date.dart';

/// Uses civil Gregorian values at its boundary; only the calendar UI is Solar.
class PersianDatePicker extends StatefulWidget {
  const PersianDatePicker({
    super.key,
    required this.initial,
    required this.first,
    required this.last,
  });
  final DateTime initial, first, last;
  @override
  State<PersianDatePicker> createState() => _PersianDatePickerState();
}

class _PersianDatePickerState extends State<PersianDatePicker> {
  late DateTime selected = DateUtils.dateOnly(widget.initial);
  late int year = nexPersianDate(selected).year;
  late int month = nexPersianDate(selected).month;
  bool get fa => Localizations.localeOf(context).languageCode == 'fa';
  String digits(Object value) => nexDigits('$value', persian: fa);
  static const monthsFa = [
    'فروردین',
    'اردیبهشت',
    'خرداد',
    'تیر',
    'مرداد',
    'شهریور',
    'مهر',
    'آبان',
    'آذر',
    'دی',
    'بهمن',
    'اسفند',
  ];
  static const monthsEn = [
    'Farvardin',
    'Ordibehesht',
    'Khordad',
    'Tir',
    'Mordad',
    'Shahrivar',
    'Mehr',
    'Aban',
    'Azar',
    'Dey',
    'Bahman',
    'Esfand',
  ];
  bool allowed(DateTime date) =>
      !date.isBefore(DateUtils.dateOnly(widget.first)) &&
      !date.isAfter(DateUtils.dateOnly(widget.last));
  bool canMove(int delta) {
    final index = year * 12 + month - 1 + delta;
    final y = index ~/ 12, m = index % 12 + 1;
    return !nexGregorianDate(
          y,
          m,
          nexPersianMonthDays(y, m),
        ).isBefore(DateUtils.dateOnly(widget.first)) &&
        !nexGregorianDate(y, m, 1).isAfter(DateUtils.dateOnly(widget.last));
  }

  void move(int delta) {
    final index = year * 12 + month - 1 + delta;
    show(index ~/ 12, index % 12 + 1);
  }

  /// Shows [y]/[m] and takes the chosen day along with it (2.7.1).
  ///
  /// The day used to stay where it was: picking 1365 and Bahman from the two
  /// lists and pressing OK gave back the day the picker opened on, because
  /// no day in Bahman 1365 had been tapped. Now the same day of the month is
  /// chosen in the month on show — the last day when the month is shorter,
  /// and the nearest allowed day at the ends of the range — so the title
  /// and OK always say the month that is on screen.
  void show(int y, int m) => setState(() {
    year = y;
    month = m;
    final want = nexPersianDate(selected).day;
    final day = want.clamp(1, nexPersianMonthDays(y, m));
    var date = nexGregorianDate(y, m, day);
    final first = DateUtils.dateOnly(widget.first);
    final last = DateUtils.dateOnly(widget.last);
    if (date.isBefore(first)) date = first;
    if (date.isAfter(last)) date = last;
    selected = date;
  });
  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    final firstYear = nexPersianDate(widget.first).year;
    final lastYear = nexPersianDate(widget.last).year;
    final offset = (nexGregorianDate(year, month, 1).weekday + 1) % 7;
    final days = nexPersianMonthDays(year, month);
    return NexAlertDialog(
      title: Text(nexDisplayDate(selected, solar: true, persian: fa)),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: material.previousMonthTooltip,
                    onPressed: canMove(-1) ? () => move(-1) : null,
                    icon: const BackButtonIcon(),
                  ),
                  Expanded(
                    child: DropdownButton<int>(
                      borderRadius: nexDropdownRadius,
                      dropdownColor: nexDropdownColor(context),
                      isExpanded: true,
                      value: month,
                      items: [
                        for (var m = 1; m <= 12; m++)
                          DropdownMenuItem(
                            value: m,
                            child: Text((fa ? monthsFa : monthsEn)[m - 1]),
                          ),
                      ],
                      onChanged: (m) {
                        if (m != null) show(year, m);
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: material.nextMonthTooltip,
                    onPressed: canMove(1) ? () => move(1) : null,
                    icon: const RotatedBox(
                      quarterTurns: 2,
                      child: BackButtonIcon(),
                    ),
                  ),
                ],
              ),
              DropdownButton<int>(
                key: const ValueKey('persian-picker-year'),
                borderRadius: nexDropdownRadius,
                dropdownColor: nexDropdownColor(context),
                // Two centuries of years: a list that scrolls, opened on the
                // year on show, rather than one taller than the screen.
                menuMaxHeight: 320,
                value: year,
                items: [
                  for (var y = firstYear; y <= lastYear; y++)
                    DropdownMenuItem(value: y, child: Text(digits(y))),
                ],
                onChanged: (y) {
                  if (y != null) show(y, month);
                },
              ),
              Row(
                children: [
                  for (final day
                      in fa
                          ? ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج']
                          : ['Sa', 'Su', 'Mo', 'Tu', 'We', 'Th', 'Fr'])
                    Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ),
                ],
              ),
              for (var row = 0; row < (offset + days + 6) ~/ 7; row++)
                Row(
                  children: [
                    for (var col = 0; col < 7; col++)
                      Expanded(child: _day(row * 7 + col - offset + 1, days)),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(material.cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, selected),
          child: Text(material.okButtonLabel),
        ),
      ],
    );
  }

  Widget _day(int day, int count) {
    if (day < 1 || day > count) return const SizedBox(height: 48);
    final date = nexGregorianDate(year, month, day);
    final active = DateUtils.isSameDay(selected, date);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: active,
      label: nexDisplayDate(date, solar: true, persian: fa),
      child: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(40, 48),
          padding: EdgeInsets.zero,
          backgroundColor: active ? scheme.primary : null,
          foregroundColor: active ? scheme.onPrimary : null,
        ),
        onPressed: allowed(date) ? () => setState(() => selected = date) : null,
        child: Text(digits(day)),
      ),
    );
  }
}
