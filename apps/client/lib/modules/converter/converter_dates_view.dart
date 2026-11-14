import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'converter_date.dart';
import 'converter_strings.dart';
import 'converter_widgets.dart';

/// The Dates tab: a date in any of the three calendars, the other two ready
/// to read, and the two date sums people actually need — how many days
/// between two dates, and what day it is plus or minus a number of days.
class ConverterDatesView extends StatelessWidget {
  const ConverterDatesView({
    super.key,
    required this.calendar,
    required this.controller,
    required this.errorText,
    required this.onCalendar,
    required this.onChanged,
    required this.onToday,
    required this.onPick,
    required this.onDaysBetween,
    required this.onAddDays,
  });

  final ConverterCalendar calendar;
  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<ConverterCalendar> onCalendar;
  final ValueChanged<String> onChanged;
  final VoidCallback onToday;
  final Future<void> Function() onPick;
  final VoidCallback onDaysBetween;
  final VoidCallback onAddDays;

  @override
  Widget build(BuildContext context) {
    final strings = converterStrings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NexPanel(
          title: strings(context, 'dateInCalendar'),
          icon: Icons.event_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NexAdaptiveSegments<ConverterCalendar>(
                segments: [
                  for (final value in ConverterCalendar.values)
                    ButtonSegment<ConverterCalendar>(
                      value: value,
                      label: Text(
                        strings(context, switch (value) {
                          ConverterCalendar.solar => 'calSolarShort',
                          ConverterCalendar.gregorian => 'calGregorianShort',
                          ConverterCalendar.lunar => 'calLunarShort',
                        }),
                      ),
                    ),
                ],
                selected: {calendar},
                onSelectionChanged: (choice) {
                  if (choice.isNotEmpty) onCalendar(choice.first);
                },
              ),
              const SizedBox(height: NexSpacing.md),
              ConverterDateField(
                fieldKey: const ValueKey('converter-date'),
                controller: controller,
                onChanged: onChanged,
                onPick: onPick,
                errorText: errorText,
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('converter-today'),
                  onPressed: onToday,
                  icon: const Icon(Icons.today_outlined),
                  label: Text(strings(context, 'today')),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: NexSpacing.md),
        // The two sums are their own small tools, so the main screen stays
        // one date and one answer.
        Wrap(
          spacing: NexSpacing.sm,
          runSpacing: NexSpacing.sm,
          children: [
            FilledButton.tonalIcon(
              key: const ValueKey('converter-days-between'),
              onPressed: onDaysBetween,
              icon: const Icon(Icons.date_range_outlined),
              label: Text(strings(context, 'daysBetween')),
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('converter-add-days'),
              onPressed: onAddDays,
              icon: const Icon(Icons.event_repeat_outlined),
              label: Text(strings(context, 'addDays')),
            ),
          ],
        ),
      ],
    );
  }
}
