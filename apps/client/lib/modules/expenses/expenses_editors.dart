import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'controller.dart';
import 'expenses_fields.dart';
import 'expenses_form.dart';
import 'expenses_undo.dart';
import 'models.dart';
import 'money.dart';
import 'strings.dart';
import 'editor_draft.dart';
import 'local_values.dart';

part 'expenses_tx_actions.dart';

/// The transaction editor: the one place a payment is written down.
///
/// One sheet, a few taps: type, amount (with the currency's own rules
/// and the rial/toman choice for IRR), date and time, category, and
/// the optional note, merchant and account label. The date is typed
/// civil text with the shared Jalali calendar button beside it, and
/// the note is the shared multiline editor. Saving is guarded against
/// double taps; leaving with unsaved work asks first, so the last edit
/// is never lost to a stray swipe; deleting a record offers Undo,
/// restoring exactly what was there.
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
  late ExpenseCurrency _currency = _initialCurrency();
  late IrrUnit _irrUnit = _initialIrrUnit();

  /// The day+time the record will take. The day follows the typed text
  /// (see `_dateChanged`); the time follows the time button. A new
  /// payment starts at now, as the old date button did.
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
        'currency': _currency.code,
        'irrUnit': _irrUnit.name,
        'date': _date.toIso8601String(),
        'dateConfirmed': _typedDay != null,
        'category': _categoryId,
      },
      applyExtra: (b) {
        if (b['type'] == 'expense' || b['type'] == 'income') {
          _type = b['type'] as String;
        }
        _currency =
            expenseCurrencyOf(
              b['currency'] is String ? b['currency'] as String : null,
            ) ??
            _currency;
        _irrUnit = b['irrUnit'] == 'toman' ? IrrUnit.toman : IrrUnit.rial;
        _categoryId = b['category'] is String ? b['category'] as String : null;
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

  ExpenseCurrency _initialCurrency() {
    final code =
        widget.existing?.currency ??
        widget.template?.currency ??
        widget.controller.preferredCurrencyCode;
    return expenseCurrencyOf(code) ?? expenseCurrencyOf('IRR')!;
  }

  IrrUnit _initialIrrUnit() {
    final stored = widget.existing == null && widget.template == null
        ? widget.controller.preferredIrrUnit
        : 'rial';
    return stored == 'toman' ? IrrUnit.toman : IrrUnit.rial;
  }

  String _initialAmountText() {
    final minor = widget.existing?.amount ?? widget.template?.amount;
    if (minor == null ||
        minor <= 0 ||
        (widget.existing != null && !widget.existing!.valid)) {
      return '';
    }
    if (_initialCurrency().code == 'IRR' &&
        _initialIrrUnit() == IrrUnit.toman) {
      return majorTextOfMinor(minor, 3);
    }
    return majorTextOfMinor(minor, _initialCurrency().exponent);
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
                      SegmentedButton<String>(
                        key: const ValueKey('expenses-type'),
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
                        currency: _currency,
                        showAllErrors: _showErrors,
                        unit: _irrUnit,
                        // Any keystroke is work worth guarding.
                        onValid: (_) => _markDirty(),
                        onUnitChanged: (unit) {
                          // Re-express the typed amount in the new unit
                          // so switching does not change the money.
                          final minor = _parsed.minor;
                          if (minor != null) {
                            _amount.text = _irrUnit == IrrUnit.rial
                                ? majorTextOfMinor(minor, 3)
                                : majorTextOfMinor(minor, _currency.exponent);
                          }
                          setState(() => _irrUnit = unit);
                          _markDirty();
                        },
                      ),
                      const SizedBox(height: NexSpacing.md),
                      ExpensesCurrencyRow(
                        currency: _currency,
                        onChanged: (currency) {
                          setState(() => _currency = currency);
                          _markDirty();
                        },
                      ),
                      const SizedBox(height: NexSpacing.md),
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
