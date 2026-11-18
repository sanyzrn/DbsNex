import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'logic.dart';
import 'money.dart';
import 'strings.dart';

/// The overview the Expenses screen is: month navigation, the month's total
/// with what is left, the category breakdown with its calm bars and its
/// change against last month, filters and the record rows. Purely
/// presentational — every number arrives computed, from `logic.dart`.

/// The month bar: back and forward a month, the month's name in the calendar
/// the person reads (a Jalali month in Persian), and the all-time toggle.
class ExpensesMonthNav extends StatelessWidget {
  const ExpensesMonthNav({
    super.key,
    required this.month,
    required this.offset,
    required this.onPrevious,
    required this.onNext,
    required this.onAllTime,
    required this.onCurrent,
  });

  final NexModuleMonth month;

  /// 0 for the month containing today, negative for earlier months.
  final int offset;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onAllTime;
  final VoidCallback onCurrent;

  @override
  Widget build(BuildContext context) {
    final s = expenseStrings;
    final theme = Theme.of(context);
    final label = month.title(context);
    final isCurrent = offset == 0;
    final relative = switch (offset) {
      0 => s(context, 'thisMonth'),
      -1 => s(context, 'lastMonth'),
      < 0 => s(context, 'monthsAgo', {'n': -offset}),
      _ => s(context, 'monthsAhead', {'n': offset}),
    };
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: s(context, 'previousMonth'),
              onPressed: onPrevious,
              icon: Icon(DirectionalChevron.start(context)),
            ),
            Expanded(
              child: Tooltip(
                message: isCurrent ? '' : s(context, 'goCurrent'),
                child: InkWell(
                  onTap: isCurrent ? null : onCurrent,
                  borderRadius: BorderRadius.circular(NexRadius.md),
                  child: Semantics(
                    label: s(context, 'monthNavSemantics', {'month': label}),
                    excludeSemantics: true,
                    child: Column(
                      children: [
                        Text(
                          label,
                          style: theme.textTheme.titleMedium,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // The relative name stays visible; tapping the month
                        // itself is the way back to now.
                        Text(
                          relative,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: s(context, 'nextMonth'),
              onPressed: onNext,
              icon: Icon(DirectionalChevron.end(context)),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Flexible so a 2× text scale can never push the pill past the
            // screen: it shortens rather than overflowing.
            Flexible(
              child: ExpensesPill(
                label: s(context, 'allTime'),
                selected: false,
                onPressed: onAllTime,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A chevron that points the way the reading direction goes.
class DirectionalChevron {
  static IconData start(BuildContext context) =>
      Directionality.of(context) == TextDirection.rtl
      ? Icons.chevron_right
      : Icons.chevron_left;

  static IconData end(BuildContext context) =>
      Directionality.of(context) == TextDirection.rtl
      ? Icons.chevron_left
      : Icons.chevron_right;
}

/// A calm pill that always meets the 48dp floor.
class ExpensesPill extends StatelessWidget {
  const ExpensesPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: NexSpacing.xs),
      child: Material(
        color: selected ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(NexRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(NexRadius.pill),
          onTap: onPressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: NexSpacing.md,
            ),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected ? scheme.onPrimary : scheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the month cost — the one large number — with what came in, what is
/// left, and how it compares with the month before. Nothing here is an
/// alarm: a month spent past its income is arithmetic, said plainly.
class ExpensesTotalsPanel extends StatelessWidget {
  const ExpensesTotalsPanel({
    super.key,
    required this.totals,
    required this.unit,
    this.change,
    this.hidden = false,
  });

  final ExpenseTotals totals;
  final ExpenseUnit unit;

  /// How this month's spending compares with last month's; null in the
  /// all-time view or when there is nothing to compare with.
  final ExpenseMonthChange? change;

  /// Privacy: amounts are replaced by dots, not removed.
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = NexModuleStrings.persian(context);
    final s = expenseStrings;
    String money(int rials) => hidden
        ? s(context, 'hiddenAmount')
        : formatExpenseAmount(rials, unit, persian: persian);
    final spent = totals.expense.toInt();
    final negative = totals.left.isNegative;
    return NexModuleHero(
      key: const ValueKey('expenses-hero'),
      moduleId: 'expenses',
      icon: Icons.account_balance_wallet_outlined,
      eyebrow: s(context, 'expensesLabel'),
      headline: money(spent),
      semanticsLabel: s(context, 'netSemantics', {
        'amount': money(spent),
        'left': money(totals.left.toInt()),
      }),
      caption: totals.hasIncome && negative ? s(context, 'netNegative') : null,
      child: Column(
        children: [
          if (totals.hasIncome) ...[
            _TotalsRow(
              label: s(context, 'incomeLabel'),
              value: money(totals.income.toInt()),
            ),
            const SizedBox(height: NexSpacing.sm),
            _TotalsRow(
              label: s(context, 'leftLabel'),
              value: money(totals.left.toInt()),
            ),
          ],
          if (change != null) ...[
            const SizedBox(height: NexSpacing.sm),
            Text(
              s(
                context,
                change!.direction == 0
                    ? 'changeSame'
                    : change!.direction > 0
                    ? 'changeMore'
                    : 'changeLess',
                {
                  'amount': money(change!.previous.toInt()),
                  'pct': change!.percent ?? 0,
                },
              ),
              key: const ValueKey('expenses-month-change'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: NexSpacing.sm),
          Text(
            s(context, 'basedOnEntered'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: NexSpacing.sm),
        // Expanded, not Flexible: the amount keeps the reading end of the
        // row even when it is short, and can wrap when it truly is long.
        Expanded(
          flex: 2,
          child: Text(
            value,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.end,
            style: theme.textTheme.titleMedium,
          ),
        ),
      ],
    );
  }
}

/// Spending by category: a row per category with its share as an integer
/// percent, its change against last month, and a calm bar relative to the
/// largest category. A tap filters the list to it.
class ExpensesBreakdownPanel extends StatelessWidget {
  const ExpensesBreakdownPanel({
    super.key,
    required this.slices,
    required this.expenseTotal,
    required this.unit,
    required this.categoryName,
    required this.onCategory,
    this.hidden = false,
  });
  final List<ExpenseCategorySlice> slices;
  final BigInt expenseTotal;
  final ExpenseUnit unit;
  final String Function(String) categoryName;
  final ValueChanged<String> onCategory;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), s = expenseStrings;
    final persian = NexModuleStrings.persian(context);
    final largest = slices.isEmpty ? BigInt.zero : slices.first.total;
    String money(BigInt rials) => hidden
        ? s(context, 'hiddenAmount')
        : formatExpenseAmount(rials.toInt(), unit, persian: persian);
    return NexPanel(
      title: s(context, 'spendingByCategory'),
      icon: Icons.donut_small_outlined,
      child: Column(
        children: [
          for (final slice in slices)
            Semantics(
              label: s(context, 'barSemantics', {
                'category': categoryName(slice.categoryId),
                'amount': money(slice.total),
                'percent': expensePercentOf(slice.total, expenseTotal),
              }),
              button: true,
              excludeSemantics: true,
              onTap: () => onCategory(slice.categoryId),
              child: InkWell(
                onTap: () => onCategory(slice.categoryId),
                borderRadius: BorderRadius.circular(NexRadius.sm),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        categoryName(slice.categoryId),
                        style: theme.textTheme.bodyLarge,
                      ),
                      Wrap(
                        spacing: NexSpacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            money(slice.total),
                            textDirection: TextDirection.ltr,
                          ),
                          Text(
                            s(context, 'percentSuffix', {
                              'p': expensePercentOf(slice.total, expenseTotal),
                            }),
                            style: theme.textTheme.bodySmall,
                          ),
                          if (slice.percent != null)
                            Text(
                              s(
                                context,
                                slice.direction == 0
                                    ? 'categorySame'
                                    : slice.direction > 0
                                    ? 'categoryMore'
                                    : 'categoryLess',
                                {'pct': slice.percent ?? 0},
                              ),
                              key: ValueKey(
                                'expenses-change-${slice.categoryId}',
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: NexSpacing.xs),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(NexRadius.xs),
                        child: LinearProgressIndicator(
                          value: expenseProgress(slice.total, largest),
                          minHeight: 6,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(
                            NexHue.teal.of(theme.brightness),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
