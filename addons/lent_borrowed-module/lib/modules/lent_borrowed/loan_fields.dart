import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

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

/// The due-date question, asked the honest way: "in N days" with
/// one-tap presets of a week, two weeks and a month — and an empty field
/// meaning no due date at all, because most things between friends have
/// none.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings(context, 'dueLabel'), style: theme.textTheme.titleSmall),
        const SizedBox(height: NexSpacing.sm),
        LoanNumberField(
          key: const ValueKey('loan-field-due'),
          controller: controller,
          label: strings(context, 'dueOffsetLabel'),
          hint: strings(context, 'noDue'),
          errorText: errorText,
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
              label: Text(strings(context, 'dueToday')),
              onPressed: enabled ? () => controller.text = '0' : null,
            ),
            for (final days in const [7, 14, 30])
              ActionChip(
                key: ValueKey('loan-due-preset-$days'),
                label: Text(strings(context, 'dueDays', {'n': days})),
                onPressed: enabled ? () => controller.text = '$days' : null,
              ),
          ],
        ),
      ],
    );
  }
}
