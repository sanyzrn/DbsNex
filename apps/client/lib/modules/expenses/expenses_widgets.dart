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
    required this.onPickMonth,
    required this.onAllTime,
    required this.onCurrent,
  });

  final NexModuleMonth month;

  /// 0 for the month containing today, negative for earlier months.
  final int offset;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// Opens the month picker: a year of months, three taps away at most.
  final VoidCallback onPickMonth;
  final VoidCallback onAllTime;
  final VoidCallback onCurrent;

  @override
  Widget build(BuildContext context) {
    final s = expenseStrings;
    final theme = Theme.of(context);
    final label = month.title(context);
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
              child: InkWell(
                // The month itself is the way to another month: a picker
                // instead of the old hidden «tap to go back to now».
                onTap: onPickMonth,
                borderRadius: BorderRadius.circular(NexRadius.md),
                child: Semantics(
                  label: s(context, 'monthNavSemantics', {'month': label}),
                  hint: s(context, 'chooseMonth'),
                  button: true,
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: NexSpacing.xs,
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                label,
                                style: theme.textTheme.titleMedium,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: NexSpacing.xs),
                            Icon(
                              Icons.expand_more,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
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
        Wrap(
          alignment: WrapAlignment.end,
          spacing: NexSpacing.xs,
          children: [
            // The way back to now sits beside «all time», and only when it
            // is needed — never a hidden tap on the date.
            if (offset != 0)
              ExpensesPill(
                key: const ValueKey('expenses-this-month'),
                label: s(context, 'thisMonth'),
                selected: false,
                onPressed: onCurrent,
              ),
            ExpensesPill(
              label: s(context, 'allTime'),
              selected: false,
              onPressed: onAllTime,
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

/// A month picker: the year, then its twelve months in the calendar the
/// person reads. Twelve steps back used to mean twelve taps; this is two.
Future<NexModuleMonth?> showExpensesMonthPicker(
  BuildContext context, {
  required NexModuleMonth selected,
  required NexModuleMonth current,
}) => nexShowSheet<NexModuleMonth>(
  context: context,
  builder: (sheetContext) =>
      _MonthPickerSheet(selected: selected, current: current),
);

class _MonthPickerSheet extends StatefulWidget {
  const _MonthPickerSheet({required this.selected, required this.current});

  final NexModuleMonth selected;
  final NexModuleMonth current;

  @override
  State<_MonthPickerSheet> createState() => _MonthPickerSheetState();
}

class _MonthPickerSheetState extends State<_MonthPickerSheet> {
  late NexModuleMonth _shown = widget.selected;

  /// Five years back and one forward is more than a household book needs;
  /// anything further is reached with the arrows, never by accident.
  bool get _canGoBack => _shown.year > widget.current.year - 5;
  bool get _canGoForward => _shown.year < widget.current.year + 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = expenseStrings;
    final persian = NexModuleStrings.persian(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(
          NexSpacing.md,
          NexSpacing.sm,
          NexSpacing.md,
          NexSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s(context, 'chooseMonth'), style: theme.textTheme.titleLarge),
            const SizedBox(height: NexSpacing.sm),
            Row(
              children: [
                IconButton(
                  tooltip: s(context, 'previousYear'),
                  onPressed: _canGoBack
                      ? () => setState(
                          () => _shown = NexModuleMonth(
                            _shown.solar,
                            _shown.year - 1,
                            _shown.month,
                          ),
                        )
                      : null,
                  icon: Icon(DirectionalChevron.start(context)),
                ),
                Expanded(
                  child: Text(
                    nexDigits('${_shown.year}', persian: persian),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: s(context, 'nextYear'),
                  onPressed: _canGoForward
                      ? () => setState(
                          () => _shown = NexModuleMonth(
                            _shown.solar,
                            _shown.year + 1,
                            _shown.month,
                          ),
                        )
                      : null,
                  icon: Icon(DirectionalChevron.end(context)),
                ),
              ],
            ),
            const SizedBox(height: NexSpacing.xs),
            for (var row = 0; row < 4; row++)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  bottom: NexSpacing.xs,
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var column = 0; column < 3; column++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(
                              end: NexSpacing.xs,
                            ),
                            child: _MonthCell(
                              key: ValueKey(
                                'expenses-month-${_shown.year}-'
                                '${row * 3 + column + 1}',
                              ),
                              label: nexModuleMonthName(
                                context,
                                solar: _shown.solar,
                                month: row * 3 + column + 1,
                              ),
                              selected:
                                  _shown.year == widget.selected.year &&
                                  row * 3 + column + 1 == widget.selected.month,
                              current:
                                  _shown.year == widget.current.year &&
                                  row * 3 + column + 1 == widget.current.month,
                              onTap: () => Navigator.pop(
                                context,
                                NexModuleMonth(
                                  _shown.solar,
                                  _shown.year,
                                  row * 3 + column + 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: NexSpacing.xs),
            Text(
              s(context, 'monthPickerHint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    super.key,
    required this.label,
    required this.selected,
    required this.current,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      excludeSemantics: true,
      child: Material(
        color: selected ? scheme.primary : scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexRadius.sm),
          side: BorderSide(
            color: current && !selected ? scheme.primary : Colors.transparent,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(NexRadius.sm),
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(
              horizontal: NexSpacing.xs,
              vertical: NexSpacing.xs,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected ? scheme.onPrimary : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The last six months as one calm row of bars: the year's shape without a
/// single figure on screen. The tallest month is named under it, because
/// «which month cost the most» is the question this answers.
class ExpensesTrendPanel extends StatelessWidget {
  const ExpensesTrendPanel({
    super.key,
    required this.points,
    required this.unit,
    this.hidden = false,
  });

  final List<ExpenseTrendPoint> points;
  final ExpenseUnit unit;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = expenseStrings;
    final persian = NexModuleStrings.persian(context);
    final accent = NexHue.teal.of(theme.brightness);
    var largest = BigInt.zero;
    var largestAt = 0;
    for (var i = 0; i < points.length; i++) {
      if (points[i].spent > largest) {
        largest = points[i].spent;
        largestAt = i;
      }
    }
    String money(BigInt rials) => hidden
        ? s(context, 'hiddenAmount')
        : formatExpenseAmount(rials.toInt(), unit, persian: persian);
    final tallest = points[largestAt];
    return NexPanel(
      title: s(context, 'trendTitle'),
      icon: Icons.insights_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 72,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < points.length; i++)
                  Expanded(
                    child: Semantics(
                      label: s(context, 'trendSemantics', {
                        'month': points[i].month.title(context),
                        'amount': money(points[i].spent),
                      }),
                      excludeSemantics: true,
                      child: Tooltip(
                        message: s(context, 'trendSemantics', {
                          'month': points[i].month.title(context),
                          'amount': money(points[i].spent),
                        }),
                        child: Padding(
                          padding: const EdgeInsetsDirectional.symmetric(
                            horizontal: 2,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Flexible(
                                child: FractionallySizedBox(
                                  heightFactor:
                                      (expenseProgress(
                                            points[i].spent,
                                            largest,
                                          ) *
                                          0.92) +
                                      0.08,
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      minHeight: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: i == largestAt
                                          ? accent
                                          : scheme.onSurface.withValues(
                                              alpha: 0.16,
                                            ),
                                      borderRadius: BorderRadius.circular(
                                        NexRadius.xs,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: NexSpacing.xs),
          Row(
            children: [
              for (var i = 0; i < points.length; i++)
                Expanded(
                  child: Text(
                    _shortMonth(context, points[i].month),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: i == points.length - 1
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          if (largest > BigInt.zero) ...[
            const SizedBox(height: NexSpacing.xs),
            Text(
              s(context, 'trendMost', {
                'month': tallest.month.title(context),
                'amount': money(largest),
              }),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// «مهر» and «Nov» alike: six months have to fit one row, so an English
/// Gregorian month is shortened while a Persian name already is short.
String _shortMonth(BuildContext context, NexModuleMonth month) {
  final name = nexModuleMonthName(
    context,
    solar: month.solar,
    month: month.month,
  );
  if (month.solar || NexModuleStrings.persian(context)) return name;
  return name.length <= 3 ? name : name.substring(0, 3);
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
