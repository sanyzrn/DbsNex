import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'expenses_fields.dart' show expenseCategoryIcon;
import 'logic.dart';
import 'models.dart';
import 'money.dart';
import 'strings.dart';

/// Budget rows, the recurring offers, the category filter chips and the
/// record rows — the parts of the Expenses screen that repeat once per thing.

/// One budget's standing, arithmetic on show: spent of budget, left or over
/// by, and a calm bar that is never red — over is information here, not
/// damage.
class ExpensesBudgetsPanel extends StatelessWidget {
  const ExpensesBudgetsPanel({
    super.key,
    required this.statuses,
    required this.onEdit,
    required this.categoryName,
    required this.unit,
    this.hidden = false,
    this.onAdd,
    this.onCopyLastMonth,
    this.hasPrevious = false,
  });

  final List<ExpenseBudgetStatus> statuses;
  final ValueChanged<ExpenseBudgetStatus> onEdit;
  final String Function(String) categoryName;
  final ExpenseUnit unit;
  final bool hidden;

  /// Sets another budget for this month (a category, or the overall one).
  final VoidCallback? onAdd;

  /// Carries last month's budgets into this one, when it has none.
  final VoidCallback? onCopyLastMonth;

  /// Whether the month before had budgets worth carrying over.
  final bool hasPrevious;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = NexModuleStrings.persian(context);
    final s = expenseStrings;
    final withinHue = NexHue.teal.of(theme.brightness);
    final overHue = NexHue.amber.of(theme.brightness);
    String money(BigInt rials) => hidden
        ? s(context, 'hiddenAmount')
        : formatExpenseAmount(rials.toInt(), unit, persian: persian);
    return NexPanel(
      title: s(context, 'budgetsTitle'),
      icon: Icons.savings_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (statuses.isEmpty)
            Text(
              s(context, 'budgetNone'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          for (final status in statuses) ...[
            InkWell(
              onTap: () => onEdit(status),
              borderRadius: BorderRadius.circular(NexRadius.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: NexSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.budget.categoryId == null
                          ? s(context, 'overallLimit')
                          : categoryName(status.budget.categoryId!),
                      style: theme.textTheme.bodyLarge,
                    ),
                    Text(
                      '${money(status.spent)} / ${money(BigInt.from(status.budget.amountRial))}',
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
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
                      _line(context, status, money),
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
            s(context, 'budgetNote'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (onAdd != null || (onCopyLastMonth != null && hasPrevious)) ...[
            const SizedBox(height: NexSpacing.xs),
            Wrap(
              spacing: NexSpacing.sm,
              runSpacing: NexSpacing.xs,
              children: [
                if (onCopyLastMonth != null && hasPrevious)
                  TextButton.icon(
                    key: const ValueKey('expenses-copy-budgets'),
                    onPressed: onCopyLastMonth,
                    icon: const Icon(Icons.copy_all_outlined, size: 18),
                    label: Text(s(context, 'copyBudgets')),
                  ),
                if (onAdd != null)
                  TextButton.icon(
                    key: const ValueKey('expenses-add-budget'),
                    onPressed: onAdd,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(s(context, 'addBudget')),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _line(
    BuildContext context,
    ExpenseBudgetStatus status,
    String Function(BigInt) money,
  ) => status.isOver
      ? '${expenseStrings(context, 'budgetOver')} ${money(status.overage)}'
      : '${expenseStrings(context, 'budgetLeft')} ${money(status.left)}';
}

/// One recurring payment that has come due this month and is not written
/// down yet — with the one tap that writes it. Nothing is ever logged by
/// itself, and the offer says so.
class ExpensesDueOffer {
  const ExpensesDueOffer({required this.template, required this.at});

  final ExpenseTemplate template;
  final DateTime at;
}

class ExpensesDuePanel extends StatelessWidget {
  const ExpensesDuePanel({
    super.key,
    required this.offers,
    required this.unit,
    required this.onLog,
    this.hidden = false,
  });

  final List<ExpensesDueOffer> offers;
  final ExpenseUnit unit;
  final ValueChanged<ExpensesDueOffer> onLog;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final persian = NexModuleStrings.persian(context);
    final s = expenseStrings;
    if (offers.isEmpty) return const SizedBox.shrink();
    final today = DateTime.now();
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: NexSpacing.md),
      child: NexPanel(
        title: s(context, 'dueTitle'),
        icon: Icons.event_repeat_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s(context, 'dueHint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: NexSpacing.sm),
            for (final offer in offers) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          offer.template.label,
                          style: theme.textTheme.bodyLarge,
                        ),
                        Text(
                          [
                            offer.at.year == today.year &&
                                    offer.at.month == today.month &&
                                    offer.at.day == today.day
                                ? s(context, 'dueToday')
                                : s(context, 'dueOn', {
                                    'date': nexModuleDateLabel(
                                      context,
                                      offer.at,
                                    ),
                                  }),
                            hidden
                                ? s(context, 'hiddenAmount')
                                : formatExpenseAmount(
                                    offer.template.amountRial,
                                    unit,
                                    persian: persian,
                                  ),
                          ].join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: NexSpacing.sm),
                  FilledButton.tonal(
                    key: ValueKey('expenses-log-${offer.template.id}'),
                    onPressed: () => onLog(offer),
                    child: Text(s(context, 'logThisMonth')),
                  ),
                ],
              ),
              const SizedBox(height: NexSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}

/// Category filter chips: "All" plus every category with a record in the
/// view, one selection, 48dp at the tap floor.
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

/// One record row: what it was, where, when — and the amount in rials or
/// tomans, hidden when the person asked. Income carries a plus sign; an
/// incomplete record says so instead of pretending.
class ExpensesTxRow extends StatelessWidget {
  const ExpensesTxRow({
    super.key,
    required this.tx,
    required this.categoryName,
    required this.onTap,
    required this.now,
    required this.unit,
    this.label,
    this.hidden = false,
  });

  final ExpenseTx tx;
  final String Function(String id) categoryName;
  final VoidCallback onTap;
  final DateTime now;
  final ExpenseUnit unit;

  /// The recurring template's name, when the payment came from one.
  final String? label;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = NexModuleStrings.persian(context);
    final income = tx.isIncome;
    final hue = NexHue.teal.of(theme.brightness);
    final category = categoryName(tx.categoryId ?? 'cat-other');
    final title = tx.valid
        ? (label ??
              (tx.note?.isNotEmpty == true
                  ? tx.note!
                  : tx.merchant?.isNotEmpty == true
                  ? tx.merchant!
                  : category))
        : expenseStrings(context, 'incompleteRecord');
    final subtitle = tx.valid
        ? [
            category,
            txDateLabel(context, tx.date, now),
            if (tx.account?.isNotEmpty == true) tx.account!,
          ].join(' · ')
        : expenseStrings(context, 'incompleteHint');
    final amount = tx.valid
        ? (hidden
              ? expenseStrings(context, 'hiddenAmount')
              : '${income ? '+' : ''}'
                    '${formatExpenseAmount(tx.amountRial, unit, persian: persian)}')
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CategoryMark(
                icon: tx.valid
                    ? expenseCategoryIcon(tx.categoryId ?? 'cat-other')
                    : Icons.report_outlined,
                invalid: !tx.valid,
              ),
              const SizedBox(width: NexSpacing.sm),
              Expanded(
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
            ],
          ),
        ),
      ),
    );
  }
}

/// A category's mark on a soft tile, so a row is recognisable before it is
/// read. Income takes the module's own hue, an incomplete record the theme's
/// error tint — never colour alone: the row still says which it is.
class _CategoryMark extends StatelessWidget {
  const _CategoryMark({required this.icon, required this.invalid});

  final IconData icon;
  final bool invalid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = invalid
        ? theme.colorScheme.error
        : NexHue.teal.of(theme.brightness);
    return ExcludeSemantics(
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(NexRadius.sm),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }
}

/// One day of records: its name in the person's calendar and what that day
/// cost — the question a list of payments is really asked.
class ExpensesDayHeader extends StatelessWidget {
  const ExpensesDayHeader({
    super.key,
    required this.day,
    required this.totals,
    required this.now,
    required this.unit,
    this.hidden = false,
    this.showTotal = true,
  });

  final DateTime? day;
  final ExpenseTotals totals;
  final DateTime now;
  final ExpenseUnit unit;
  final bool hidden;

  /// False while a search or filter is narrowing the list: the figure would
  /// then be the day's *matching* spending, which is not the day's spending,
  /// so the header says only which day it is.
  final bool showTotal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = NexModuleStrings.persian(context);
    final s = expenseStrings;
    final label = day == null
        ? s(context, 'incompleteGroup')
        : txDateLabel(context, day!, now);
    String money(BigInt rials) => hidden
        ? s(context, 'hiddenAmount')
        : formatExpenseAmount(rials.toInt(), unit, persian: persian);
    final spent = totals.expense;
    final came = totals.income;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        top: NexSpacing.md,
        bottom: NexSpacing.xs,
      ),
      child: Semantics(
        label: showTotal
            ? s(context, 'dayTotalSemantics', {
                'date': label,
                'amount': money(spent),
              })
            : label,
        excludeSemantics: true,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: NexSpacing.sm,
          children: [
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (showTotal && (spent > BigInt.zero || came == BigInt.zero))
              Text(
                money(spent),
                textDirection: TextDirection.ltr,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            if (showTotal && came > BigInt.zero)
              Text(
                '+${money(came)}',
                textDirection: TextDirection.ltr,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: NexHue.teal.of(theme.brightness),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One month of the all-time view, with what it cost — so a year of records
/// reads as twelve months, not one endless list.
class ExpensesMonthHeader extends StatelessWidget {
  const ExpensesMonthHeader({
    super.key,
    required this.month,
    required this.totals,
    required this.unit,
    this.hidden = false,
    this.showTotal = true,
  });

  final NexModuleMonth? month;
  final ExpenseTotals totals;
  final ExpenseUnit unit;
  final bool hidden;

  /// False while a filter is narrowing the list; see [ExpensesDayHeader].
  final bool showTotal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final persian = NexModuleStrings.persian(context);
    final s = expenseStrings;
    final label = month?.title(context) ?? s(context, 'incompleteGroup');
    final amount = hidden
        ? s(context, 'hiddenAmount')
        : formatExpenseAmount(totals.expense.toInt(), unit, persian: persian);
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: NexSpacing.lg, bottom: 2),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: NexSpacing.sm,
        children: [
          Text(label, style: theme.textTheme.titleSmall),
          if (showTotal)
            Text(
              amount,
              textDirection: TextDirection.ltr,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// "Today", "Yesterday", or the shared date label — calendar-relative when
/// the words say it, the app's chosen calendar (Jalali included) through
/// `nexModuleDateLabel` when it is an absolute day.
String txDateLabel(BuildContext context, DateTime date, DateTime now) {
  final localDate = DateTime.utc(date.year, date.month, date.day);
  final localNow = DateTime.utc(now.year, now.month, now.day);
  if (localDate == localNow) return expenseStrings(context, 'today');
  if (localDate == localNow.subtract(const Duration(days: 1))) {
    return expenseStrings(context, 'yesterday');
  }
  return nexModuleDateLabel(context, date);
}
