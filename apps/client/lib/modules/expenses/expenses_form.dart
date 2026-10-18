import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'money.dart';
import 'strings.dart';

/// The editor's small pieces: an optional single-line field, and the
/// date and time buttons that open the platform's own pickers (the
/// Gregorian pickers; a Jalali picker is a platform request — see the
/// README).

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

class ExpensesDateButton extends StatelessWidget {
  const ExpensesDateButton({
    super.key,
    required this.date,
    required this.onTap,
    this.confirmed = true,
  });

  final DateTime date;
  final bool confirmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const ValueKey('expenses-date'),
      onPressed: onTap,
      icon: const Icon(Icons.calendar_today_outlined),
      label: Text(
        confirmed
            ? nexModuleDateLabel(context, date)
            : expenseStrings(context, 'dateRequired'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
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
    return OutlinedButton.icon(
      key: const ValueKey('expenses-time'),
      onPressed: onTap,
      icon: const Icon(Icons.schedule_outlined),
      label: Text(persian ? persianDigits(time) : time, maxLines: 1),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    );
  }
}
