import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'controller.dart';
import 'expenses_budget.dart';
import 'expenses_editors.dart';
import 'expenses_rows.dart';
import 'expenses_sheets.dart';
import 'expenses_templates.dart';
import 'expenses_widgets.dart';
import 'logic.dart';
import 'models.dart';
import 'strings.dart';

/// The Expenses home: one month at a time — or all time — with its
/// totals per currency, budgets, category breakdown and records, and
/// the one primary action, adding a payment. Everything recomputes
/// from the records on every change; nothing is cached across opens
/// except what the store itself keeps.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key, required this.store});

  final NexModuleStore store;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  late final ExpensesController controller = ExpensesController(widget.store);

  /// Null: the all-time view.
  String? _month;

  String? _categoryFilter;
  bool _searching = false;
  final _search = TextEditingController();

  /// Captured once per open: the "home" grouping the brief asks for is
  /// computed when the module is opened, not live against a ticking
  /// clock.
  late final DateTime _openedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _month = monthKeyOf(_openedAt);
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
    super.dispose();
  }

  String _categoryName(String id) {
    for (final custom in controller.customCategories) {
      if (custom.id == id) return custom.label;
    }
    return defaultExpenseCategoryIds.contains(id)
        ? expenseStrings(context, id)
        : expenseStrings(context, 'cat-other');
  }

  List<ExpenseTx> get _scope => txsInMonth(controller.txs, _month).toList();

  List<ExpenseTx> get _visible {
    var visible = searchTxs(_scope, _search.text, _categoryName);
    if (_categoryFilter != null) {
      visible = visible.where(
        (tx) => (tx.categoryId ?? 'cat-other') == _categoryFilter,
      );
    }
    return sortedByDate(visible);
  }

  void _previousMonth() => setState(() {
    final previous = previousMonthKey(_month ?? monthKeyOf(_openedAt));
    if (previous != null) _month = previous;
  });

  void _nextMonth() => setState(() {
    final next = nextMonthKey(_month ?? monthKeyOf(_openedAt));
    if (next != null) _month = next;
  });

  void _toCurrentMonth() => setState(() => _month = monthKeyOf(DateTime.now()));

  void _allTime() => setState(() => _month = null);

  Future<void> _add() => showExpensesTxEditor(context, controller: controller);

  Future<void> _edit(ExpenseTx tx) =>
      showExpensesTxEditor(context, controller: controller, existing: tx);

  Future<void> _useTemplate(ExpenseTemplate template) =>
      showExpensesTxEditor(context, controller: controller, template: template);

  Future<void> _menu(String action) async {
    switch (action) {
      case 'categories':
        await showExpensesCategories(context, controller: controller);
      case 'templates':
        await showExpensesTemplates(
          context,
          controller: controller,
          onUse: (template) => unawaited(_useTemplate(template)),
        );
      case 'budgets':
        await showExpensesBudgetEditor(
          context,
          controller: controller,
          month: _month ?? monthKeyOf(DateTime.now()),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = expenseStrings;
    final visible = _visible;
    final totals = expenseTotals(controller.txs.where((tx) => _inScope(tx)));
    final budgetStatuses = _month == null
        ? const <ExpenseBudgetStatus>[]
        : expenseBudgetStatuses(controller.budgets, _month!, _scope);
    return Scaffold(
      appBar: NexAppBar(
        title: Text(s(context, 'title')),
        actions: [
          IconButton(
            tooltip: s(context, 'searchLabel'),
            onPressed: () => setState(() => _searching = !_searching),
            icon: const Icon(Icons.search),
          ),
          NexPopupMenuButton<String>(
            tooltip: s(context, 'title'),
            onSelected: (action) => unawaited(_menu(action)),
            itemBuilder: (menuContext) => [
              nexMenuItem(
                value: 'budgets',
                icon: Icons.savings_outlined,
                label: s(menuContext, 'budgetsTitle'),
              ),
              nexMenuItem(
                value: 'categories',
                icon: Icons.category_outlined,
                label: s(menuContext, 'categoriesTitle'),
              ),
              nexMenuItem(
                value: 'templates',
                icon: Icons.bookmarks_outlined,
                label: s(menuContext, 'templatesTitle'),
              ),
            ],
          ),
        ],
      ),
      // One primary action per page: with nothing yet it is the button in
      // the empty state, not a second one floating beside it.
      floatingActionButton:
          controller.loading ||
              controller.readFailed ||
              (controller.txs.isEmpty && controller.customCategories.isEmpty)
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('expenses-add'),
              onPressed: () => unawaited(_add()),
              icon: const Icon(Icons.add),
              label: Text(s(context, 'addFirst')),
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
                    NexAutoDirection(
                      controller: _search,
                      builder: (context, direction) => TextField(
                        key: const ValueKey('expenses-search'),
                        controller: _search,
                        textDirection: direction,
                        decoration: InputDecoration(
                          hintText: s(context, 'searchHint'),
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: s(context, 'clearFilters'),
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    _search.clear();
                                    setState(() {});
                                  },
                                ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: NexSpacing.md),
                  ],
                  _month == null
                      ? _AllTimeHeader(onBack: _toCurrentMonth)
                      : ExpensesMonthNav(
                          month: _month!,
                          now: _openedAt,
                          onPrevious: _previousMonth,
                          onNext: _nextMonth,
                          onAllTime: _allTime,
                          onCurrent: _toCurrentMonth,
                        ),
                  const SizedBox(height: NexSpacing.md),
                  if (controller.txs.any((tx) => !tx.valid))
                    TextButton(
                      onPressed: _allTime,
                      child: Text(s(context, 'incompleteRecord')),
                    ),
                  // The true empty state: nothing anywhere, ever. A
                  // month with no records is not this — it shows the
                  // overview with its quiet "nothing in this view".
                  if (controller.txs.isEmpty &&
                      controller.customCategories.isEmpty)
                    NexEmptyState(
                      icon: Icons.account_balance_wallet_outlined,
                      message: s(context, 'noRecords'),
                      action: FilledButton.icon(
                        key: const ValueKey('expenses-add'),
                        onPressed: () => unawaited(_add()),
                        icon: const Icon(Icons.add),
                        label: Text(s(context, 'addFirst')),
                      ),
                    )
                  else ...[
                    for (final total in totals)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          bottom: NexSpacing.md,
                        ),
                        child: ExpensesTotalsPanel(
                          totals: total,
                          change: _month == null
                              ? null
                              : expenseMonthChange(
                                  controller.txs,
                                  _month!,
                                  currency: total.currency,
                                ),
                        ),
                      ),
                    if (totals.length > 1)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          bottom: NexSpacing.md,
                        ),
                        child: Text(
                          s(context, 'perCurrency'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (budgetStatuses.isNotEmpty) ...[
                      ExpensesBudgetsPanel(
                        statuses: budgetStatuses,
                        categoryName: _categoryName,
                        onEdit: (status) => unawaited(
                          showExpensesBudgetEditor(
                            context,
                            controller: controller,
                            month: status.budget.month,
                            existing: status.budget,
                          ),
                        ),
                      ),
                      const SizedBox(height: NexSpacing.md),
                    ],
                    ..._breakdownPanels(),
                    const SizedBox(height: NexSpacing.sm),
                    ExpensesFilterChips(
                      categories: _categoriesInScope(),
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
                          // An empty month and an empty search are
                          // different facts, said differently.
                          _scope.isEmpty
                              ? s(context, 'nothingSpent')
                              : s(context, 'noResults'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      )
                    else ...[
                      Text(
                        s(context, 'recentTitle'),
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: NexSpacing.xs),
                      for (final tx in visible)
                        ExpensesTxRow(
                          key: ValueKey('expenses-tx-${tx.id}'),
                          tx: tx,
                          categoryName: _categoryName,
                          onTap: () => unawaited(_edit(tx)),
                          now: _openedAt,
                        ),
                    ],
                  ],
                ],
              ),
      ),
    );
  }

  bool _inScope(ExpenseTx tx) =>
      _month == null || monthKeyOf(tx.date) == _month;

  List<Widget> _breakdownPanels() {
    final panels = <Widget>[];
    for (final total in expenseTotals(_scope)) {
      if (total.expense <= BigInt.zero) continue;
      final slices = expenseCategoryBreakdown(_scope, currency: total.currency);
      if (slices.isEmpty) continue;
      panels.add(
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: NexSpacing.md),
          child: ExpensesBreakdownPanel(
            slices: slices,
            currency: total.currency,
            expenseTotal: total.expense,
            categoryName: _categoryName,
            onCategory: (id) => setState(
              () => _categoryFilter = id == _categoryFilter ? null : id,
            ),
          ),
        ),
      );
    }
    return panels;
  }

  List<String> _categoriesInScope() {
    final ids = <String>[];
    for (final tx in _scope) {
      if (!tx.valid || tx.isIncome) continue;
      final id = tx.categoryId ?? 'cat-other';
      if (!ids.contains(id)) ids.add(id);
    }
    return ids;
  }
}

/// The all-time header: what it is, and the way back to this month.
class _AllTimeHeader extends StatelessWidget {
  const _AllTimeHeader({required this.onBack});

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
        TextButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text(expenseStrings(context, 'thisMonth')),
        ),
      ],
    );
  }
}
