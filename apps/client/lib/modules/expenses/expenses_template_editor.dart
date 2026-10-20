part of 'expenses_templates.dart';

/// Creates a template: name, type, amount, currency, category, note
/// and merchant — the same fields the transaction editor will be
/// prefilled from, minus the date and account, which are per-use.
Future<void> showExpensesTemplateEditor(
  BuildContext context, {
  required ExpensesController controller,
}) => nexShowSheet(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (_) => _TemplateEditorSheet(controller: controller),
);

class _TemplateEditorSheet extends StatefulWidget {
  const _TemplateEditorSheet({required this.controller});

  final ExpensesController controller;

  @override
  State<_TemplateEditorSheet> createState() => _TemplateEditorSheetState();
}

class _TemplateEditorSheetState extends State<_TemplateEditorSheet> {
  String _type = 'expense';
  ExpenseCurrency _currency =
      expenseCurrencyOf('IRR') ?? expenseCurrencies.first;
  IrrUnit _irrUnit = IrrUnit.rial;
  String? _categoryId;
  late final ExpenseEditorDraft _draft;
  bool _showErrors = false;
  @override
  void initState() {
    super.initState();
    _currency = expenseCurrencyOf(widget.controller.preferredCurrencyCode)!;
    _draft = ExpenseEditorDraft(
      store: widget.controller.store,
      kind: 'tpl',
      fields: {
        'label': _label,
        'amount': _amount,
        'note': _note,
        'merchant': _merchant,
      },
      extra: () => {
        'type': _type,
        'currency': _currency.code,
        'irrUnit': _irrUnit.name,
        'category': _categoryId,
      },
      applyExtra: (b) {
        if (b['type'] == 'income' || b['type'] == 'expense') {
          _type = b['type'] as String;
        }
        _currency =
            expenseCurrencyOf(
              b['currency'] is String ? b['currency'] as String : null,
            ) ??
            _currency;
        _irrUnit = b['irrUnit'] == 'toman' ? IrrUnit.toman : IrrUnit.rial;
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
  bool _dirty = false;

  late final TextEditingController _label = TextEditingController();
  late final TextEditingController _amount = TextEditingController();
  late final TextEditingController _note = TextEditingController();
  late final TextEditingController _merchant = TextEditingController();

  @override
  void dispose() {
    _draft.dispose();
    _label.dispose();
    _amount.dispose();
    _note.dispose();
    _merchant.dispose();
    super.dispose();
  }

  ExpenseAmountResult get _parsed =>
      _currency.code == 'IRR' && _irrUnit == IrrUnit.toman
      ? parseTomanAmount(_amount.text)
      : parseExpenseAmount(_amount.text, _currency);

  Future<void> _save() async {
    if (_label.text.trim().isEmpty) {
      setState(() => _showErrors = true);
      return;
    }
    final result = _parsed;
    if (result.error != null || result.minor == null) {
      setState(() => _showErrors = true);
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    final template = ExpenseTemplate(
      id: _draft.recordId,
      label: _label.text.trim(),
      type: _type,
      amount: result.minor!,
      currency: _currency.code,
      categoryId: _categoryId,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      merchant: _merchant.text.trim().isEmpty ? null : _merchant.text.trim(),
    );
    try {
      if (!await _draft.finish()) throw StateError('Draft flush failed');
      await widget.controller.saveTemplate(template, draftId: _draft.draftId);
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
        // Same guard as the transaction editor: work is never lost to
        // a stray back gesture.
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
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  s(context, 'newTemplate'),
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: NexSpacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      NexAutoDirection(
                        controller: _label,
                        builder: (context, direction) => TextField(
                          key: const ValueKey('expenses-template-name'),
                          controller: _label,
                          textDirection: direction,
                          decoration: InputDecoration(
                            labelText: s(context, 'templateNameLabel'),
                            errorText: _label.text.trim().isEmpty && _showErrors
                                ? s(context, 'templateNameEmpty')
                                : null,
                          ),
                          onChanged: (_) => _changed(),
                        ),
                      ),
                      const SizedBox(height: NexSpacing.md),
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(
                            value: 'expense',
                            label: Text(s(context, 'typeExpense')),
                          ),
                          ButtonSegment(
                            value: 'income',
                            label: Text(s(context, 'typeIncome')),
                          ),
                        ],
                        selected: {_type},
                        onSelectionChanged: (set) => setState(() {
                          _type = set.first;
                          _dirty = true;
                          _draft.changed();
                        }),
                      ),
                      const SizedBox(height: NexSpacing.md),
                      ExpensesAmountField(
                        controller: _amount,
                        currency: _currency,
                        showAllErrors: _showErrors,
                        onValid: (_) => _changed(),
                        unit: _irrUnit,
                        onUnitChanged: (unit) {
                          final minor = _parsed.minor;
                          if (minor != null) {
                            _amount.text = _irrUnit == IrrUnit.rial
                                ? majorTextOfMinor(minor, 3)
                                : majorTextOfMinor(minor, _currency.exponent);
                          }
                          setState(() => _irrUnit = unit);
                          _changed();
                        },
                      ),
                      const SizedBox(height: NexSpacing.md),
                      ExpensesCurrencyRow(
                        currency: _currency,
                        onChanged: (currency) => setState(() {
                          _currency = currency;
                          _dirty = true;
                          _draft.changed();
                        }),
                      ),
                      const SizedBox(height: NexSpacing.md),
                      ExpensesCategoryRow(
                        customCategories: widget.controller.customCategories,
                        selectedId: _categoryId,
                        forIncome: _type == 'income',
                        onChanged: (id) => setState(() {
                          _categoryId = id;
                          _dirty = true;
                          _draft.changed();
                        }),
                      ),
                      const SizedBox(height: NexSpacing.md),
                      NexTextField(
                        key: const ValueKey('expenses-template-note'),
                        controller: _note,
                        minLines: 2,
                        maxLines: 4,
                        onChanged: (_) => _changed(),
                        decoration: InputDecoration(
                          labelText: s(context, 'noteLabel'),
                          hintText: s(context, 'noteHint'),
                        ),
                      ),
                      const SizedBox(height: NexSpacing.md),
                      NexAutoDirection(
                        controller: _merchant,
                        builder: (context, direction) => TextField(
                          controller: _merchant,
                          textDirection: direction,
                          decoration: InputDecoration(
                            labelText: s(context, 'merchantLabel'),
                            hintText: s(context, 'merchantHint'),
                          ),
                          onChanged: (_) => _changed(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: NexSpacing.sm),
              FilledButton(
                key: const ValueKey('expenses-template-save'),
                onPressed: _saving ? null : () => unawaited(_save()),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(s(context, 'save')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
