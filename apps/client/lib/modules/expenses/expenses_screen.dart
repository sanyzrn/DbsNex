import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'controller.dart';
import 'editor_draft.dart';
import 'expenses_app_bar.dart';
import 'expenses_budget.dart';
import 'expenses_editors.dart';
import 'expenses_menu.dart';
import 'expenses_fields.dart';
import 'expenses_filters.dart';
import 'expenses_home_helpers.dart';
import 'expenses_rows.dart';
import 'expenses_undo.dart';
import 'expenses_widgets.dart';
import 'logic.dart';
import 'models.dart';
import 'money.dart';
import 'strings.dart';

/// The Expenses home: one month at a time — or all time — with what it
/// cost, what is left of what came in, the categories with their change
/// against last month, budgets, the recurring payments that have come due,
/// filters and the records. Everything recomputes from the records on every
/// change; nothing is cached across opens except what the store keeps.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key, required this.store});

  final NexModuleStore store;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  late final ExpensesController controller = ExpensesController(widget.store);

  /// Null: the all-time view.
  bool _allTime = false;

  /// Months from the one containing today; negative is earlier.
  int _offset = 0;

  String? _categoryFilter;
  bool _searching = false;
  final _search = TextEditingController();
  final _min = NexMoneyController();
  final _max = NexMoneyController();

  /// Captured once per open: a month is computed from the day the module
  /// was opened, not against a ticking clock.
  late final DateTime _openedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    unawaited(controller.load());
    controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    controller.dispose();
    _search.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  String _categoryName(String id) =>
      categoryNameOf(context, id, controller.customCategories);

  NexModuleMonth _monthOf(bool solar) =>
      NexModuleMonth.of(_openedAt, solar: solar).shift(_offset);

  List<ExpenseTx> _scope(NexModuleMonth? month, bool solar) =>
      txsInMonth(controller.txs, month, solar: solar).toList();

  void _previousMonth() => setState(() => _offset--);

  void _nextMonth() => setState(() => _offset++);

  void _toCurrentMonth() => setState(() {
    _allTime = false;
    _offset = 0;
  });

  void _allTimeView() => setState(() => _allTime = true);

  /// Any month in the calendar the person reads, two taps away — the year's
  /// months in a grid rather than one step at a time.
  Future<void> _pickMonth(NexModuleMonth base) async {
    final picked = await showExpensesMonthPicker(
      context,
      selected: _monthOf(base.solar),
      current: base,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _allTime = false;
      _offset = (picked.year - base.year) * 12 + (picked.month - base.month);
    });
  }

  /// Carries last month's budgets into [month], one tap for the chore of
  /// retyping every limit when a month turns over.
  Future<void> _copyBudgets(NexModuleMonth month) async {
    final messenger = NexBannerHost.of(context);
    final s = expenseStrings;
    final undoLabel = s(context, 'undo');
    final undoFailure = s(context, 'undoFailed');
    try {
      final created = await controller.copyBudgetsFrom(
        from: monthStartIso(month.shift(-1)),
        to: monthStartIso(month),
      );
      if (!mounted) return;
      if (created == null) {
        messenger?.show(message: s(context, 'copiedNone'));
        return;
      }
      ExpensesUndo.offer(
        messenger,
        message: s(context, 'copiedBudgets', {'n': created.count}),
        undoLabel: undoLabel,
        failureMessage: undoFailure,
        restore: created.undo,
      );
    } catch (_) {
      if (mounted) expenseWriteFailure(context);
    }
  }

  Future<void> _add() => showExpensesTxEditor(context, controller: controller);

  Future<void> _edit(ExpenseTx tx) =>
      showExpensesTxEditor(context, controller: controller, existing: tx);

  /// Writes this month's occurrence down, once, and offers Undo for it.
  Future<void> _log(ExpensesDueOffer offer) async {
    final messenger = NexBannerHost.of(context);
    final message = expenseStrings(context, 'logDone', {
      'label': offer.template.label,
    });
    final undoLabel = expenseStrings(context, 'undo');
    final undoFailure = expenseStrings(context, 'undoFailed');
    try {
      final id = await controller.logTemplate(offer.template, dueDay: offer.at);
      if (id == null || !mounted) return;
      ExpensesUndo.offer(
        messenger,
        message: message,
        undoLabel: undoLabel,
        failureMessage: undoFailure,
        restore: () => controller.deleteTx(id),
      );
    } catch (_) {
      if (mounted) expenseWriteFailure(context);
    }
  }

  Widget _txRow(ExpenseTx tx, ExpenseUnit unit, bool hidden) => ExpensesTxRow(
    key: ValueKey('expenses-tx-${tx.id}'),
    tx: tx,
    categoryName: _categoryName,
    onTap: () => unawaited(_edit(tx)),
    now: _openedAt,
    unit: unit,
    hidden: hidden,
    label: templateLabelOf(controller.templates, tx),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = expenseStrings;
    final solar = NexModuleCalendar.solarOf(context);
    final month = _monthOf(solar);
    final unit = controller.unit;
    final hidden = controller.hideAmounts;
    final scope = _scope(_allTime ? null : month, solar);
    final totals = expenseTotals(scope);
    final visible = sortedByDate(
      filterTxs(
        scope,
        query: _search.text,
        categoryId: _categoryFilter,
        minRial: rialsOf(_min, unit),
        maxRial: rialsOf(_max, unit),
        categoryName: _categoryName,
      ),
    );
    final budgets = _allTime
        ? const <ExpenseBudgetStatus>[]
        : expenseBudgetStatuses(controller.budgets, month, controller.txs);
    final lastMonthStart = monthStartIso(month.shift(-1));
    final hasLastMonthBudgets =
        !_allTime && controller.budgetsForStart(lastMonthStart).isNotEmpty;
    final trend = _allTime
        ? const <ExpenseTrendPoint>[]
        : expenseTrend(controller.txs, month: month, solar: solar);
    // A header total is the day's (or month's) real spending only while
    // nothing is narrowing the list.
    final filtering =
        _search.text.trim().isNotEmpty ||
        _categoryFilter != null ||
        _min.text.trim().isNotEmpty ||
        _max.text.trim().isNotEmpty;
    final dayGroups = expenseDayGroups(visible);
    final monthSections = _allTime
        ? expenseMonthSections(visible, solar: solar)
        : const <ExpenseMonthSection>[];
    final change = _allTime
        ? null
        : expenseMonthChange(controller.txs, month: month, solar: solar);
    final offers = _allTime
        ? const <ExpensesDueOffer>[]
        : dueOffersFor(controller, month, now: _openedAt);
    final slices = _allTime
        ? const <ExpenseCategorySlice>[]
        : expenseCategoryBreakdown(scope, month: month, solar: solar);
    // A budget is setup a person did, even before the first payment: the
    // home must show it, not «nothing written down yet» above a month that
    // has limits but no records.
    final empty =
        controller.txs.isEmpty &&
        controller.customCategories.isEmpty &&
        controller.templates.isEmpty &&
        controller.budgets.isEmpty;
    // A label that cannot fit beside an icon at 2× text is not shown: the
    // button keeps its one action, and its words move into the tooltip.
    final roomForWords =
        MediaQuery.textScalerOf(context).scale(14) <= 20 &&
        MediaQuery.sizeOf(context).width >= 360;
    return Scaffold(
      appBar: ExpensesAppBar(
        title: s(context, 'title'),
        hiddenAmounts: hidden,
        searching: _searching,
        showShare: !_allTime,
        onToggleAmounts: () => unawaited(controller.setHideAmounts(!hidden)),
        onSearch: () => setState(() => _searching = !_searching),
        onMenu: (action) => unawaited(
          showExpensesMenu(
            context,
            controller: controller,
            action: action,
            month: month,
            scope: _scope(month, solar),
            categoryName: _categoryName,
          ),
        ),
      ),
      // One primary action per page: with nothing yet it is the button in
      // the empty state, not a second one floating beside it.
      floatingActionButton: controller.loading || controller.readFailed || empty
          ? null
          : roomForWords
          ? FloatingActionButton.extended(
              // No hero: a page's button never flies into another's (2.8.2).
              heroTag: null,
              key: const ValueKey('expenses-add'),
              onPressed: () => unawaited(_add()),
              icon: const Icon(Icons.add),
              label: Text(s(context, 'addFirst')),
            )
          : FloatingActionButton(
              heroTag: null,
              key: const ValueKey('expenses-add'),
              tooltip: s(context, 'addFirst'),
              onPressed: () => unawaited(_add()),
              child: const Icon(Icons.add),
            ),
      body: SafeArea(
        child: controller.loading
            ? const Center(child: CircularProgressIndicator())
            : controller.readFailed
            ? NexEmptyState(
                icon: Icons.cloud_off_outlined,
                message: s(context, 'loadFailed'),
                action: TextButton(
                  onPressed: () => unawaited(controller.load()),
                  // Material caps buttons at 40dp tall — a label a 2× text
                  // scale cannot fit into; let it grow with the words.
                  style: const ButtonStyle(
                    maximumSize: WidgetStatePropertyAll<Size?>(
                      Size(double.infinity, double.infinity),
                    ),
                  ),
                  child: Text(s(context, 'retry')),
                ),
              )
            : ListView(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  NexSpacing.md,
                  NexSpacing.sm,
                  NexSpacing.md,
                  NexSpacing.xl,
                ),
                children: [
                  if (_searching) ...[
                    NexSearchField(
                      fieldKey: const ValueKey('expenses-search'),
                      controller: _search,
                      hintText: s(context, 'searchHint'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    ExpensesRangeFilter(
                      min: _min,
                      max: _max,
                      unit: unit,
                      onChanged: () => setState(() {}),
                      onClear: () => setState(() {
                        _search.clear();
                        _min.clear();
                        _max.clear();
                        _categoryFilter = null;
                      }),
                    ),
                    const SizedBox(height: NexSpacing.md),
                  ],
                  _allTime
                      ? ExpensesAllTimeHeader(onBack: _toCurrentMonth)
                      : ExpensesMonthNav(
                          month: month,
                          offset: _offset,
                          onPrevious: _previousMonth,
                          onNext: _nextMonth,
                          onPickMonth: () => unawaited(
                            _pickMonth(
                              NexModuleMonth.of(_openedAt, solar: solar),
                            ),
                          ),
                          onAllTime: _allTimeView,
                          onCurrent: _toCurrentMonth,
                        ),
                  const SizedBox(height: NexSpacing.md),
                  if (controller.txs.any((tx) => !tx.valid))
                    TextButton(
                      key: const ValueKey('expenses-incomplete'),
                      onPressed: _allTimeView,
                      child: Text(s(context, 'incompleteRecord')),
                    ),
                  // The true empty state: nothing anywhere, ever. A month
                  // with no records is not this — it shows the overview with
                  // its quiet "nothing in this view".
                  if (empty)
                    NexEmptyState(
                      icon: Icons.account_balance_wallet_outlined,
                      message: s(context, 'noRecords'),
                      action: FilledButton(
                        key: const ValueKey('expenses-add'),
                        onPressed: () => unawaited(_add()),
                        child: Text(s(context, 'addFirst')),
                      ),
                    )
                  else ...[
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        bottom: NexSpacing.md,
                      ),
                      child: ExpensesTotalsPanel(
                        totals: totals,
                        unit: unit,
                        change: change,
                        hidden: hidden,
                      ),
                    ),
                    if (offers.isNotEmpty)
                      ExpensesDuePanel(
                        offers: offers,
                        unit: unit,
                        hidden: hidden,
                        onLog: (offer) => unawaited(_log(offer)),
                      ),
                    if (budgets.isNotEmpty || hasLastMonthBudgets) ...[
                      ExpensesBudgetsPanel(
                        statuses: budgets,
                        categoryName: _categoryName,
                        unit: unit,
                        hidden: hidden,
                        hasPrevious: hasLastMonthBudgets,
                        onAdd: () => unawaited(
                          showExpensesBudgetEditor(
                            context,
                            controller: controller,
                            month: month,
                          ),
                        ),
                        onCopyLastMonth: () => unawaited(_copyBudgets(month)),
                        onEdit: (status) => unawaited(
                          showExpensesBudgetEditor(
                            context,
                            controller: controller,
                            month: month,
                            existing: status.budget,
                          ),
                        ),
                      ),
                      const SizedBox(height: NexSpacing.md),
                    ],
                    if (slices.isNotEmpty) ...[
                      ExpensesBreakdownPanel(
                        slices: slices,
                        expenseTotal: totals.expense,
                        unit: unit,
                        hidden: hidden,
                        categoryName: _categoryName,
                        onCategory: (id) => setState(
                          () => _categoryFilter = id == _categoryFilter
                              ? null
                              : id,
                        ),
                      ),
                      const SizedBox(height: NexSpacing.md),
                    ],
                    if (trend.any((point) => point.spent > BigInt.zero)) ...[
                      ExpensesTrendPanel(
                        key: const ValueKey('expenses-trend'),
                        points: trend,
                        unit: unit,
                        hidden: hidden,
                      ),
                      const SizedBox(height: NexSpacing.md),
                    ],
                    ExpensesFilterChips(
                      categories: categoriesInScope(
                        scope,
                        selected: _categoryFilter,
                      ),
                      selected: _categoryFilter,
                      categoryName: _categoryName,
                      onSelect: (id) => setState(() => _categoryFilter = id),
                    ),
                    const SizedBox(height: NexSpacing.sm),
                    if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: NexSpacing.xl,
                        ),
                        child: Text(
                          // An empty month and an empty search are different
                          // facts, said differently.
                          scope.isEmpty
                              ? s(context, 'nothingSpent')
                              : s(context, 'noResults'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      )
                    else ...[
                      Text(
                        s(context, 'recordsTitle'),
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: NexSpacing.xs),
                      if (_allTime)
                        for (final section in monthSections) ...[
                          ExpensesMonthHeader(
                            key: ValueKey(
                              'expenses-month-section-'
                              '${section.month == null ? 'undated' : monthStartIso(section.month!)}',
                            ),
                            month: section.month,
                            totals: section.totals,
                            unit: unit,
                            hidden: hidden,
                            showTotal: !filtering,
                          ),
                          for (final group in section.days) ...[
                            ExpensesDayHeader(
                              key: ValueKey(
                                'expenses-day-'
                                '${group.day == null ? 'undated' : isoDay(group.day!)}',
                              ),
                              day: group.day,
                              totals: group.totals,
                              now: _openedAt,
                              unit: unit,
                              hidden: hidden,
                              showTotal: !filtering,
                            ),
                            for (final tx in group.txs)
                              _txRow(tx, unit, hidden),
                          ],
                        ]
                      else
                        for (final group in dayGroups) ...[
                          ExpensesDayHeader(
                            key: ValueKey(
                              'expenses-day-'
                              '${group.day == null ? 'undated' : isoDay(group.day!)}',
                            ),
                            day: group.day,
                            totals: group.totals,
                            now: _openedAt,
                            unit: unit,
                            hidden: hidden,
                            showTotal: !filtering,
                          ),
                          for (final tx in group.txs) _txRow(tx, unit, hidden),
                        ],
                    ],
                  ],
                ],
              ),
      ),
    );
  }
}
