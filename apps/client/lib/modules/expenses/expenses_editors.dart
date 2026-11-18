import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'controller.dart';
import 'editor_draft.dart';
import 'expenses_fields.dart';
import 'expenses_form.dart';
import 'expenses_undo.dart';
import 'local_values.dart';
import 'models.dart';
import 'money.dart';
import 'strings.dart';

part 'expenses_tx_actions.dart';

/// The transaction editor: the one place a payment is written down.
///
/// The brief's "seconds" are the first three questions — expense or income,
/// the amount, the category — and today is already the answer to "when".
/// Everything else (the day, the clock, a note, the merchant, the account
/// label) sits behind one optional card, so the form a person meets is three
/// fields tall. The date is typed civil text with the shared calendar button
/// beside it; the note is the shared multiline editor. Saving is guarded
/// against double taps; leaving with unsaved work asks first; deleting offers
/// Undo that restores exactly what was there.
Future<void> showExpensesTxEditor(
  BuildContext context, {
  required ExpensesController controller,
  ExpenseTx? existing,
  ExpenseTemplate? template,
}) => nexShowSheet(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (sheetContext) => ExpensesTxEditorSheet(
    controller: controller,
    existing: existing,
    template: template,
  ),
);

class ExpensesTxEditorSheet extends StatefulWidget {
  const ExpensesTxEditorSheet({
    super.key,
    required this.controller,
    this.existing,
    this.template,
  });

  final ExpensesController controller;
  final ExpenseTx? existing;
  final ExpenseTemplate? template;

  @override
  State<ExpensesTxEditorSheet> createState() => _ExpensesTxEditorSheetState();
}

class _ExpensesTxEditorSheetState extends State<ExpensesTxEditorSheet> {
  late String _type =
      widget.existing?.type ?? widget.template?.type ?? 'expense';
  late ExpenseUnit _unit = widget.controller.unit;

  /// The day+time the record will take. A new payment starts now, so the day
  /// is today unless the person says otherwise; the day follows the typed
  /// text (see `_dateChanged`), the clock the time button.
  late DateTime _date = widget.existing?.date ?? DateTime.now();
  late final TextEditingController _dateText = TextEditingController(
    text: _initialDateText(),
  );
  late String? _categoryId =
      widget.existing?.categoryId ?? widget.template?.categoryId;

  late final TextEditingController _amount = TextEditingController(
    text: _initialAmountText(),
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.existing?.note ?? widget.template?.note ?? '',
  );
  late final TextEditingController _merchant = TextEditingController(
    text: widget.existing?.merchant ?? widget.template?.merchant ?? '',
  );
  late final TextEditingController _account = TextEditingController(
    text: widget.existing?.account ?? '',
  );

  /// The optional half of the form: open when correcting something that is
  /// already written, or when a template brought notes with it.
  late bool _more = widget.existing != null || _hasDetails;

  bool get _hasDetails =>
      (widget.template?.note?.isNotEmpty ?? false) ||
      (widget.template?.merchant?.isNotEmpty ?? false);

  late final ExpenseEditorDraft _draft;
  @override
  void initState() {
    super.initState();
    _dateText.addListener(_dateChanged);
    _draft = ExpenseEditorDraft(
      store: widget.controller.store,
      kind: 'tx',
      fields: {
        'amount': _amount,
        'dateText': _dateText,
        'note': _note,
        'merchant': _merchant,
        'account': _account,
      },
      existingId: widget.existing?.id,
      base: widget.existing?.source ?? widget.existing?.toBody(),
      target: widget.existing?.id ?? widget.controller.newTxId(),
      scope: widget.template == null
          ? null
          : 'tx:template:${widget.template!.id}:new',
      extra: () => {
        'type': _type,
        'unit': _unit.key,
        'date': _date.toIso8601String(),
        'dateConfirmed': _typedDay != null,
        'category': _categoryId,
        'more': _more,
      },
      applyExtra: (b) {
        if (b['type'] == 'expense' || b['type'] == 'income') {
          _type = b['type'] as String;
        }
        _unit = ExpenseUnit.fromKey(b['unit']);
        _categoryId = b['category'] is String ? b['category'] as String : null;
        if (b['more'] is bool) _more = b['more'] as bool;
        _resumeDate(b);
        _dirty = true;
      },
      repaint: () {
        if (mounted) setState(() {});
      },
    );
    unawaited(_draft.load());
  }

  void _paint(VoidCallback fn) => setState(fn);
  bool _saving = false;
  bool _dirty = false;
  bool _showErrors = false;

  String _initialAmountText() {
    final existing = widget.existing;
    if (existing == null || !existing.valid || existing.amountRial <= 0) {
      return widget.template == null
          ? ''
          : expenseAmountInput(widget.template!.amountRial, _unit);
    }
    return expenseAmountInput(existing.amountRial, _unit);
  }

  @override
  void dispose() {
    _dateText.removeListener(_dateChanged);
    _draft.dispose();
    _amount.dispose();
    _dateText.dispose();
    _note.dispose();
    _merchant.dispose();
    _account.dispose();
    super.dispose();
  }

  void _markDirty() {
    setState(() => _dirty = true);
    _draft.changed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNew = widget.existing == null;
    final title = isNew
        ? expenseStrings(
            context,
            _type == 'income' ? 'newIncomeTitle' : 'newExpenseTitle',
          )
        : expenseStrings(
            context,
            _type == 'income' ? 'editIncomeTitle' : 'editExpenseTitle',
          );
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) unawaited(_confirmDiscard());
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
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(title, style: theme.textTheme.titleLarge),
              ),
              const SizedBox(height: NexSpacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      NexAdaptiveSegments<String>(
                        segments: [
                          ButtonSegment(
                            value: 'expense',
                            label: Text(expenseStrings(context, 'typeExpense')),
                            icon: const Icon(Icons.south_west),
                          ),
                          ButtonSegment(
                            value: 'income',
                            label: Text(expenseStrings(context, 'typeIncome')),
                            icon: const Icon(Icons.north_east),
                          ),
                        ],
                        selected: {_type},
                        onSelectionChanged: (set) {
                          setState(() => _type = set.first);
                          _markDirty();
                        },
                      ),
                      const SizedBox(height: NexSpacing.md),
                      ExpensesAmountField(
                        controller: _amount,
                        unit: _unit,
                        showAllErrors: _showErrors,
                        // Any keystroke is work worth guarding.
                        onValid: (_) => _markDirty(),
                        onUnitChanged: (unit) {
                          // Re-express the typed amount in the new unit so
                          // switching does not change the money.
                          final rials = _parsed.rials;
                          if (rials != null) {
                            _amount.text = expenseAmountInput(rials, unit);
                          }
                          setState(() => _unit = unit);
                          _markDirty();
                        },
                      ),
                      const SizedBox(height: NexSpacing.md),
                      ExpensesCategoryRow(
                        customCategories: widget.controller.customCategories,
                        selectedId: _categoryId,
                        forIncome: _type == 'income',
                        onChanged: (id) {
                          setState(() => _categoryId = id);
                          _markDirty();
                        },
                      ),
                      const SizedBox(height: NexSpacing.md),
                      NexMoreDetails(
                        open: _more,
                        toggleKey: const ValueKey('expenses-more'),
                        title: expenseStrings(context, 'detailsTitle'),
                        hint: expenseStrings(context, 'detailsHint'),
                        onChanged: (open) {
                          setState(() => _more = open);
                          _markDirty();
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: ExpensesDateField(
                                    controller: _dateText,
                                    errorText: _dateError(context),
                                  ),
                                ),
                                const SizedBox(width: NexSpacing.sm),
                                Expanded(
                                  child: ExpensesTimeButton(
                                    date: _date,
                                    onTap: _pickTime,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: NexSpacing.md),
                            NexTextField(
                              key: const ValueKey('expenses-note'),
                              controller: _note,
                              minLines: 2,
                              maxLines: 4,
                              onChanged: (_) => _markDirty(),
                              decoration: InputDecoration(
                                labelText: expenseStrings(context, 'noteLabel'),
                                hintText: expenseStrings(context, 'noteHint'),
                              ),
                            ),
                            const SizedBox(height: NexSpacing.md),
                            ExpensesOptionalField(
                              key: const ValueKey('expenses-merchant'),
                              controller: _merchant,
                              label: expenseStrings(context, 'merchantLabel'),
                              hint: expenseStrings(context, 'merchantHint'),
                              onChanged: _markDirty,
                            ),
                            const SizedBox(height: NexSpacing.md),
                            ExpensesOptionalField(
                              key: const ValueKey('expenses-account'),
                              controller: _account,
                              label: expenseStrings(context, 'accountLabel'),
                              hint: expenseStrings(context, 'accountHint'),
                              onChanged: _markDirty,
                            ),
                            const SizedBox(height: NexSpacing.md),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: NexSpacing.sm),
              FilledButton(
                key: const ValueKey('expenses-save'),
                onPressed: _saving ? null : () => unawaited(_save()),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(expenseStrings(context, 'save')),
              ),
              if (!isNew) ...[
                const SizedBox(height: NexSpacing.sm),
                TextButton(
                  key: const ValueKey('expenses-delete'),
                  onPressed: _saving ? null : () => unawaited(_delete()),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(expenseStrings(context, 'delete')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
