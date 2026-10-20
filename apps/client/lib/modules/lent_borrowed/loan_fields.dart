import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'loan_date_entry.dart';
import 'loan_dates.dart';
import 'module.dart';

/// A whole-number field: left-to-right digits, a plain keyboard, an
/// optional suffix and hint.
class LoanNumberField extends StatelessWidget {
  const LoanNumberField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.errorText,
    this.suffix,
    this.decimal = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? errorText;
  final String? suffix;
  final bool decimal;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: TextInputType.numberWithOptions(
      decimal: decimal,
      signed: true,
    ),
    textDirection: TextDirection.ltr,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      suffixText: suffix,
      border: const OutlineInputBorder(),
    ),
  );
}

/// The due-date question, asked on the calendar: an absolute date with the
/// shared picker beside it, and one-tap shortcuts — a week, two weeks, a
/// month, today, or none at all, because most things between friends have
/// no deadline. An empty field means no due date.
class LoanDueField extends StatelessWidget {
  const LoanDueField({
    super.key,
    required this.controller,
    required this.enabled,
    this.errorText,
  });

  final TextEditingController controller;
  final bool enabled;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    final theme = Theme.of(context);
    String entry(int daysFromToday) =>
        dateEntryText(shiftCivilDate(DateTime.now(), daysFromToday));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings(context, 'dueLabel'), style: theme.textTheme.titleSmall),
        const SizedBox(height: NexSpacing.sm),
        NexModuleDateEntry(
          key: const ValueKey('loan-due-date-entry'),
          controller: controller,
          child: TextField(
            key: const ValueKey('loan-field-due'),
            controller: controller,
            keyboardType: TextInputType.datetime,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: strings(context, 'dateFieldLabel'),
              hintText: strings(context, 'dateHint'),
              errorText: errorText,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: NexSpacing.sm),
        Wrap(
          spacing: NexSpacing.sm,
          runSpacing: NexSpacing.sm,
          children: [
            ActionChip(
              key: const ValueKey('loan-due-none'),
              label: Text(strings(context, 'noDue')),
              onPressed: enabled ? controller.clear : null,
            ),
            ActionChip(
              key: const ValueKey('loan-due-today'),
              label: Text(strings(context, 'todayWord')),
              onPressed: enabled ? () => controller.text = entry(0) : null,
            ),
            for (final days in const [7, 14, 30])
              ActionChip(
                key: ValueKey('loan-due-preset-$days'),
                label: Text(strings(context, 'dueDays', {'n': days})),
                onPressed: enabled ? () => controller.text = entry(days) : null,
              ),
          ],
        ),
      ],
    );
  }
}
