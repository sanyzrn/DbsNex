import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

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
  });

  final List<ExpenseBudgetStatus> statuses;
  final ValueChanged<ExpenseBudgetStatus> onEdit;
  final String Function(String) categoryName;
  final ExpenseUnit unit;
  final bool hidden;

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
