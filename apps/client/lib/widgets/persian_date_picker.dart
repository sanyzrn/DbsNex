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

  void move(int delta) => setState(() {
    final index = year * 12 + month - 1 + delta;
    year = index ~/ 12;
    month = index % 12 + 1;
  });
  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    final firstYear = nexPersianDate(widget.first).year;
    final lastYear = nexPersianDate(widget.last).year;
    final offset = (nexGregorianDate(year, month, 1).weekday + 1) % 7;
    final days = nexPersianMonthDays(year, month);
    return AlertDialog(
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
                        if (m != null) setState(() => month = m);
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
                value: year,
                items: [
                  for (var y = firstYear; y <= lastYear; y++)
                    DropdownMenuItem(value: y, child: Text(digits(y))),
                ],
                onChanged: (y) {
                  if (y != null) setState(() => year = y);
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
