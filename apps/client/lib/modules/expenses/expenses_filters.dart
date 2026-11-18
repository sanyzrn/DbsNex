import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'money.dart';
import 'strings.dart';

/// The amount range: two plain fields, in the unit the person says amounts
/// in. Typing filters as they go; the clear button lifts the range and the
/// words in one tap.
class ExpensesRangeFilter extends StatelessWidget {
  const ExpensesRangeFilter({
    super.key,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController min;
  final TextEditingController max;
  final ExpenseUnit unit;
  final VoidCallback onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final s = expenseStrings;
    final persian = NexModuleStrings.persian(context);
    final suffix = expenseUnitWord(unit, persian: persian);
    Widget field(TextEditingController controller, String label, Key key) =>
        Expanded(
          child: TextField(
            key: key,
            controller: controller,
            // An amount is read left to right in either language.
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.numberWithOptions(
              decimal: unit.decimals > 0,
            ),
            decoration: InputDecoration(labelText: label, suffixText: suffix),
            onChanged: (_) => onChanged(),
          ),
        );
    return Row(
      children: [
        field(min, s(context, 'minLabel'), const ValueKey('expenses-min')),
        const SizedBox(width: NexSpacing.sm),
        field(max, s(context, 'maxLabel'), const ValueKey('expenses-max')),
        IconButton(
          tooltip: s(context, 'clearFilters'),
          onPressed: onClear,
          icon: const Icon(Icons.filter_alt_off_outlined),
        ),
      ],
    );
  }
}

/// The all-time header: what it is, and the way back to this month.
class ExpensesAllTimeHeader extends StatelessWidget {
  const ExpensesAllTimeHeader({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            expenseStrings(context, 'allTime'),
            style: theme.textTheme.titleMedium,
          ),
        ),
        Flexible(
          child: TextButton(
            onPressed: onBack,
            child: Text(
              expenseStrings(context, 'thisMonth'),
              textAlign: TextAlign.end,
            ),
          ),
        ),
      ],
    );
  }
}
