import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'logic.dart';
import 'money.dart';
import 'strings.dart';

/// The overview the Expenses screen is: month navigation, per-currency
/// totals, the category breakdown with its calm bars, budget rows with
/// the arithmetic on show, filter chips and the record rows. Purely
/// presentational — every number arrives computed, from `logic.dart`.

/// The month bar: back and forward a month, the month's name with its
/// calendar-relative tag, and the all-time toggle.
class ExpensesMonthNav extends StatelessWidget {
  const ExpensesMonthNav({
    super.key,
    required this.month,
    required this.now,
    required this.onPrevious,
    required this.onNext,
    required this.onAllTime,
    required this.onCurrent,
  });

  final String month;
  final DateTime now;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onAllTime;
  final VoidCallback onCurrent;

  @override
  Widget build(BuildContext context) {
    final s = expenseStrings;
    final label = monthLabel(context, month, withYear: true);
    final distance = monthDistance(month, now);
    final isCurrent = distance.distance == ExpenseMonthDistance.current;
    final relative = switch (distance.distance) {
      ExpenseMonthDistance.current => s(context, 'thisMonth'),
      ExpenseMonthDistance.previous => s(context, 'lastMonth'),
      ExpenseMonthDistance.earlier => s(context, 'monthsAgo', {
        'n': distance.months,
      }),
      ExpenseMonthDistance.later => s(context, 'monthsAhead', {
        'n': distance.months,
      }),
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
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // The relative name stays visible; tapping the month
                        // itself is the way back to now.
                        Text(
                          relative,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
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
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: _PillButton(
            label: s(context, 'allTime'),
            selected: false,
            onPressed: onAllTime,
          ),
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

/// The label of a month key — name from the module's strings, digits
/// in the locale's form, year included on request (all-time views).
String monthLabel(BuildContext context, String month, {bool withYear = true}) {
  final persian = NexModuleStrings.persian(context);
  final number = monthNumberOf(month);
  final name = expenseStrings(context, 'month${number.clamp(1, 12)}');
  final year = persian ? persianDigits(yearOf(month)) : yearOf(month);
  return withYear ? '$name $year' : name;
}

/// A calm pill that always meets the 48dp floor.
class _PillButton extends StatelessWidget {
  const _PillButton({
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
            alignment: Alignment.center,
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected ? scheme.onPrimary : scheme.onSurface,
              ),
              maxLines: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Expenses, income and net for one currency — the net stated plainly,
/// a quiet line under it when it is negative, never an alarm.
class ExpensesTotalsPanel extends StatelessWidget {
  const ExpensesTotalsPanel({super.key, required this.totals});

  final ExpenseCurrencyTotals totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = NexModuleStrings.persian(context);
    final currency = expenseCurrencyOf(totals.currency);
    final exponent =
        currency?.exponent ?? expenseExponentOf(totals.currency, null);
    String money(BigInt minor) =>
        formatExpenseNumber(minor, exponent, persian: persian);
    final negative = totals.net.isNegative;
    return NexPanel(
      padding: const EdgeInsets.all(NexSpacing.md),
      child: Column(
        children: [
          _TotalsRow(
            label: expenseStrings(context, 'expensesLabel'),
            value: '${money(totals.expense)} ${totals.currency}',
          ),
          const SizedBox(height: NexSpacing.sm),
          _TotalsRow(
            label: expenseStrings(context, 'incomeLabel'),
            value: '${money(totals.income)} ${totals.currency}',
          ),
          const Divider(height: NexSpacing.lg),
          _TotalsRow(
            label: expenseStrings(context, 'netLabel'),
            value: '${money(totals.net)} ${totals.currency}',
            emphasized: true,
            semantics: expenseStrings(context, 'netSemantics', {
              'amount': '${money(totals.net)} ${totals.currency}',
            }),
          ),
          if (negative) ...[
            const SizedBox(height: NexSpacing.xs),
            Text(
              expenseStrings(context, 'netNegative'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: NexSpacing.sm),
          Text(
            expenseStrings(context, 'basedOnEntered'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({
    required this.label,
    required this.value,
    this.emphasized = false,
    this.semantics,
  });
  final String label, value;
  final bool emphasized;
  final String? semantics;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: NexSpacing.xs),
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: emphasized
              ? theme.textTheme.headlineSmall
              : theme.textTheme.titleLarge,
        ),
      ],
    );
    return semantics == null
        ? row
        : Semantics(label: semantics, excludeSemantics: true, child: row);
  }
}

/// Spending by category: a row per category with its share as an
/// integer percent and a bar relative to the largest category.
class ExpensesBreakdownPanel extends StatelessWidget {
  const ExpensesBreakdownPanel({
    super.key,
    required this.slices,
    required this.currency,
    required this.expenseTotal,
    required this.categoryName,
    required this.onCategory,
  });
  final List<ExpenseCategorySlice> slices;
  final String currency;
  final BigInt expenseTotal;
  final String Function(String) categoryName;
  final ValueChanged<String> onCategory;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), s = expenseStrings;
    final persian = NexModuleStrings.persian(context);
    final exponent = expenseExponentOf(currency, null);
    final largest = slices.isEmpty ? BigInt.zero : slices.first.total;
    return NexPanel(
      title: s(context, 'spendingByCategory'),
      icon: Icons.donut_small_outlined,
      child: Column(
        children: [
          for (final slice in slices)
            Semantics(
              label: s(context, 'barSemantics', {
                'category': categoryName(slice.categoryId),
                'amount':
                    '${formatExpenseNumber(slice.total, exponent, persian: persian)} $currency',
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
                        children: [
                          Text(
                            '${formatExpenseNumber(slice.total, exponent, persian: persian)} $currency',
                            textDirection: TextDirection.ltr,
                          ),
                          Text(
                            s(context, 'percentSuffix', {
                              'p': expensePercentOf(slice.total, expenseTotal),
                            }),
                            style: theme.textTheme.bodySmall,
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
