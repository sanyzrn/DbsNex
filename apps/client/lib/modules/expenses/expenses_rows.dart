import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'logic.dart';
import 'models.dart';
import 'money.dart';
import 'strings.dart';

/// Budget rows, the category filter chips and the record rows — the
/// parts of the Expenses screen that repeat once per thing.

/// One budget's standing, arithmetic on show: spent of budget, left or
/// over by, and a calm bar that is never red — over is information
/// here, not damage.
class ExpensesBudgetsPanel extends StatelessWidget {
  const ExpensesBudgetsPanel({
    super.key,
    required this.statuses,
    required this.onEdit,
    required this.categoryName,
  });

  final List<ExpenseBudgetStatus> statuses;
  final ValueChanged<ExpenseBudgetStatus> onEdit;
  final String Function(String) categoryName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = NexModuleStrings.persian(context);
    final withinHue = NexHue.teal.of(theme.brightness);
    final overHue = NexHue.amber.of(theme.brightness);
    return NexPanel(
      title: expenseStrings(context, 'budgetsTitle'),
      icon: Icons.savings_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final status in statuses) ...[
            InkWell(
              onTap: () => onEdit(status),
              borderRadius: BorderRadius.circular(NexRadius.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: NexSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          status.budget.categoryId == null
                              ? expenseStrings(context, 'overallLimit')
                              : categoryName(status.budget.categoryId!),
                          style: theme.textTheme.bodyLarge,
                        ),
                        Text(
                          '${formatExpenseNumber(status.spent, expenseExponentOf(status.budget.currency, null), persian: persian)} / ${formatExpenseNumber(status.budget.amount, expenseExponentOf(status.budget.currency, null), persian: persian)} ${status.budget.currency}',
                          textDirection: TextDirection.ltr,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: NexSpacing.xs),
                    ExcludeSemantics(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(NexRadius.xs),
                        child: SizedBox(
                          height: 6,
                          child: LinearProgressIndicator(
                            value: status.progress,
                            minHeight: 6,
                            backgroundColor: scheme.surfaceContainerHighest
                                .withValues(alpha: 0.8),
                            valueColor: AlwaysStoppedAnimation(
                              status.isOver ? overHue : withinHue,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: NexSpacing.xs),
                    Text(
                      _line(context, status, persian),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: status.isOver
                            ? overHue
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: NexSpacing.xs),
          Text(
            expenseStrings(context, 'budgetNote'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _line(BuildContext context, ExpenseBudgetStatus status, bool persian) {
    final exponent = expenseExponentOf(status.budget.currency, null);
    final amount = formatExpenseNumber(
      status.isOver ? status.overage : status.left,
      exponent,
      persian: persian,
    );
    if (status.isOver) {
      return '${expenseStrings(context, 'budgetOver')} $amount '
          '${status.budget.currency}';
    }
    return '${expenseStrings(context, 'budgetLeft')} $amount '
        '${status.budget.currency}';
  }
}

/// Category filter chips: "All" plus every category with a record in
/// the view, one selection, 48dp at the tap floor.
class ExpensesFilterChips extends StatelessWidget {
  const ExpensesFilterChips({
    super.key,
    required this.categories,
    required this.selected,
    required this.categoryName,
    required this.onSelect,
  });

  final List<String> categories;
  final String? selected;
  final String Function(String id) categoryName;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    Widget chip(String id, String label, bool isSelected) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: NexSpacing.sm),
        child: Material(
          color: isSelected ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(NexRadius.pill),
          child: InkWell(
            borderRadius: BorderRadius.circular(NexRadius.pill),
            // The "All" chip clears the filter; it never sets one.
            onTap: () => onSelect(isSelected || id.isEmpty ? null : id),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: NexSpacing.md,
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                maxLines: 1,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: isSelected ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip('', expenseStrings(context, 'filterAll'), selected == null),
          for (final id in categories)
            chip(id, categoryName(id), selected == id),
        ],
      ),
    );
  }
}

/// One record row: what it was, where, when — and the amount in its
/// own currency. Income carries a plus sign; an incomplete record says
/// so instead of pretending.
class ExpensesTxRow extends StatelessWidget {
  const ExpensesTxRow({
    super.key,
    required this.tx,
    required this.categoryName,
    required this.onTap,
    required this.now,
  });

  final ExpenseTx tx;
  final String Function(String id) categoryName;
  final VoidCallback onTap;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = NexModuleStrings.persian(context);
    final exponent = expenseExponentOf(tx.currency, null);
    final income = tx.isIncome;
    final hue = NexHue.teal.of(theme.brightness);
    final category = categoryName(tx.categoryId ?? 'cat-other');
    final title = tx.valid
        ? (tx.note?.isNotEmpty == true
              ? tx.note!
              : tx.merchant?.isNotEmpty == true
              ? tx.merchant!
              : category)
        : expenseStrings(context, 'incompleteRecord');
    final subtitle = tx.valid
        ? [
            category,
            txDateLabel(context, tx.date, now),
            if (tx.account?.isNotEmpty == true) tx.account!,
          ].join(' · ')
        : expenseStrings(context, 'incompleteHint');
    final amount = tx.valid
        ? '${income ? '+' : ''}${formatExpenseNumber(tx.amount, exponent, persian: persian)} ${tx.currency}'
        : '—';
    final semantics = expenseStrings(context, 'txSemantics', {
      'type': income
          ? expenseStrings(context, 'typeIncome')
          : expenseStrings(context, 'typeExpense'),
      'amount': amount,
      'category': category,
      'date': txDateLabel(context, tx.date, now),
    });
    return Semantics(
      label: semantics,
      button: true,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: NexSpacing.xs),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: NexSpacing.xs),
              Text(
                amount,
                textDirection: TextDirection.ltr,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: income ? hue : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Today", "Yesterday", or "13 October" — calendar-relative, honest,
/// and never a Jalali date in Persian (the API offers no Jalali
/// formatter; see the README's Platform requests).
String txDateLabel(BuildContext context, DateTime date, DateTime now) {
  final persian = NexModuleStrings.persian(context);
  final localDate = DateTime.utc(date.year, date.month, date.day);
  final localNow = DateTime.utc(now.year, now.month, now.day);
  if (localDate == localNow) return expenseStrings(context, 'today');
  if (localDate == localNow.subtract(const Duration(days: 1))) {
    return expenseStrings(context, 'yesterday');
  }
  final month = expenseStrings(context, 'month${date.month.clamp(1, 12)}');
  final day = persian ? persianDigits('${date.day}') : '${date.day}';
  final withYear = date.year != now.year;
  final year = persian ? persianDigits('${date.year}') : '${date.year}';
  return withYear ? '$day $month $year' : '$day $month';
}
