import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'controller.dart';
import 'editor_draft.dart';
import 'expenses_fields.dart';
import 'expenses_undo.dart';
import 'models.dart';
import 'money.dart';
import 'strings.dart';

part 'expenses_budget_choices.dart';

/// Sets (or clears) one month's budget for a category — or the overall
/// monthly limit. The arithmetic it produces is on the overview: spent,
/// left, over by. A budget belongs to the month a person is reading, so it
/// is keyed by that month's first day, whatever calendar that month is in.
Future<void> showExpensesBudgetEditor(
  BuildContext context, {
  required ExpensesController controller,
  required NexModuleMonth month,
  ExpenseBudget? existing,
}) => nexShowSheet(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (_) =>
      _BudgetSheet(controller: controller, month: month, existing: existing),
);

class _BudgetSheet extends StatefulWidget {
  const _BudgetSheet({
    required this.controller,
    required this.month,
    this.existing,
  });

  final ExpensesController controller;
  final NexModuleMonth month;
  final ExpenseBudget? existing;

  @override
  State<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<_BudgetSheet> {
  late String? _categoryId = widget.existing?.categoryId;
  late ExpenseUnit _unit = widget.controller.unit;
  late final TextEditingController _amount = TextEditingController(
    text: widget.existing == null
        ? ''
        : expenseAmountInput(widget.existing!.amountRial, _unit),
  );
  late final ExpenseEditorDraft _draft;
  bool _dirty = false;
  @override
  void initState() {
    super.initState();
    _draft = ExpenseEditorDraft(
      store: widget.controller.store,
      kind: 'budget',
      existingId: widget.existing?.id,
      base: widget.existing?.toBody() ?? {'start': monthStartIso(widget.month)},
      scope: widget.existing == null
          ? 'budget:${monthStartIso(widget.month)}:new'
          : null,
      fields: {'amount': _amount},
      extra: () => {'unit': _unit.key, 'category': _categoryId},
      applyExtra: (b) {
        _unit = ExpenseUnit.fromKey(b['unit']);
        _categoryId = b['category'] is String ? b['category'] as String : null;
        _dirty = true;
      },
      repaint: () {
        if (mounted) setState(() {});
      },
    );
    unawaited(_draft.load());
  }

  void _changed() {
    setState(() => _dirty = true);
    _draft.changed();
  }

  bool _saving = false;
  bool _showErrors = false;

  @override
  void dispose() {
    _draft.dispose();
    _amount.dispose();
    super.dispose();
  }

  ExpenseAmountResult get _parsed =>
      parseExpenseAmount(_amount.text, _unit, allowZero: true);

  Future<void> _save() async {
    final parsed = _parsed;
    if (parsed.error != null || parsed.rials == null) {
      setState(() => _showErrors = true);
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (!await _draft.finish()) throw StateError('Draft flush failed');
      await widget.controller.saveBudget(
        ExpenseBudget(
          start: monthStartIso(widget.month),
          categoryId: _categoryId,
          amountRial: parsed.rials!,
        ),
        existing: widget.existing,
        draftId: _draft.draftId,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      _draft.resume();
      _draft.writeFailed = true;
      if (mounted) expenseWriteFailure(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    if (widget.existing == null || _saving) return;
    setState(() => _saving = true);
    final messenger = NexBannerHost.of(context);
    final message = expenseStrings(context, 'deletedTx'),
        undoLabel = expenseStrings(context, 'undo');
    final undoFailure = expenseStrings(context, 'undoFailed');
    try {
      if (!await _draft.finish()) throw StateError('Draft flush failed');
      await widget.controller.clearBudget(
        widget.existing!.start,
        widget.existing!.categoryId,
      );
      ExpensesUndo.offer(
        messenger,
        message: message,
        undoLabel: undoLabel,
        failureMessage: undoFailure,
        restore: () => widget.controller.restore('budget', widget.existing!.id),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      _draft.resume();
      _draft.writeFailed = true;
      if (mounted) expenseWriteFailure(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = expenseStrings;
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) {
          unawaited(
            confirmExpensesDiscard(
              context,
              discard: _draft.draft.clear,
              keepDraft: _draft.finish,
            ),
          );
        }
      },
      child: ExpensesDraftFrame(
        session: _draft,
        busy: _saving,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            NexSpacing.md,
            0,
            NexSpacing.md,
            NexSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s(
                  context,
                  widget.existing == null ? 'setBudget' : 'editBudget',
                ),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: NexSpacing.xs),
              Text(
                s(context, 'budgetFor', {'month': widget.month.title(context)}),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: NexSpacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _OverallOrCategory(
                        categoryId: _categoryId,
                        customCategories: widget.controller.customCategories,
                        onChanged: (id) {
                          _categoryId = id;
                          _changed();
                        },
                      ),
                      const SizedBox(height: NexSpacing.md),
                      ExpensesAmountField(
                        controller: _amount,
                        unit: _unit,
                        showAllErrors: _showErrors,
                        allowZero: true,
                        onValid: (_) => _changed(),
                        // The field re-expresses its own value; only the
                        // choice is remembered here.
                        onUnitChanged: (unit) {
                          _unit = unit;
                          _changed();
                        },
                      ),
                      const SizedBox(height: NexSpacing.sm),
                      Text(
                        s(context, 'budgetNote'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: NexSpacing.sm),
              FilledButton(
                key: const ValueKey('expenses-budget-save'),
                onPressed: _saving ? null : () => unawaited(_save()),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(s(context, 'save')),
              ),
              if (widget.existing != null) ...[
                const SizedBox(height: NexSpacing.sm),
                TextButton(
                  key: const ValueKey('expenses-budget-clear'),
                  onPressed: _saving ? null : () => unawaited(_clear()),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(s(context, 'clearBudget')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
