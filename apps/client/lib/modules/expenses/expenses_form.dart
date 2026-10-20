import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'money.dart';
import 'strings.dart';

/// The editor's small pieces: an optional single-line field, and the
/// date and time rows. The date is typed civil text with the shared
/// calendar button under it (`NexModuleDateEntry`), which offers the
/// Jalali calendar when the app's calendar says so — see
/// `module_dates.dart` and the module's README.

/// The text the date field holds for a civil day: `2026/03/05`. Zero
/// padded, one separator style; `LocalValues.day` reads it back.
String expensesDateEntryText(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}/${two(date.month)}/${two(date.day)}';
}

class ExpensesOptionalField extends StatelessWidget {
  const ExpensesOptionalField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) => NexAutoDirection(
    controller: controller,
    builder: (context, direction) => TextField(
      controller: controller,
      textDirection: direction,
      decoration: InputDecoration(labelText: label, hintText: hint),
      onChanged: (_) => onChanged?.call(),
      maxLines: 1,
    ),
  );
}

/// The typed civil day, with the shared Jalali/civil calendar button
/// beside it. The field itself holds the text a person typed (or the
/// calendar wrote back); storage and parsing stay civil, exactly as
/// they were under the old date button. Typing is heard through the
/// controller, so a day the calendar writes in counts as a change too.
class ExpensesDateField extends StatelessWidget {
  const ExpensesDateField({
    super.key,
    required this.controller,
    this.errorText,
  });

  final TextEditingController controller;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return NexModuleDateEntry(
      key: const ValueKey('expenses-date-entry'),
      controller: controller,
      child: TextField(
        key: const ValueKey('expenses-date'),
        controller: controller,
        keyboardType: TextInputType.datetime,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: expenseStrings(context, 'dateLabel'),
          hintText: expenseStrings(context, 'dateHint'),
          errorText: errorText,
        ),
      ),
    );
  }
}

class ExpensesTimeButton extends StatelessWidget {
  const ExpensesTimeButton({
    super.key,
    required this.date,
    required this.onTap,
  });

  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final persian = NexModuleStrings.persian(context);
    String two(int v) => v.toString().padLeft(2, '0');
    final time = '${two(date.hour)}:${two(date.minute)}';
    return Semantics(
      // The button's own text is only the clock; the word says which
      // field it is.
      label:
          '${expenseStrings(context, 'timeLabel')} '
          '${persian ? persianDigits(time) : time}',
      button: true,
      excludeSemantics: true,
      child: OutlinedButton.icon(
        key: const ValueKey('expenses-time'),
        onPressed: onTap,
        icon: const Icon(Icons.schedule_outlined),
        label: Text(persian ? persianDigits(time) : time, maxLines: 1),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      ),
    );
  }
}
