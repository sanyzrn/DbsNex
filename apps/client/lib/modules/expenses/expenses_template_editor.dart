part of 'expenses_templates.dart';

/// Creates a template: name, type, amount, category, and — for rent, the
/// internet or a subscription — the day of the month it falls due. The
/// calendar the day is counted in is the one the person is reading when
/// they save it, so «the 5th» keeps meaning the 5th of that calendar.
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
  ExpenseUnit _unit = ExpenseUnit.toman;
  String? _categoryId;
  bool _solar = false;
  bool _calendarRead = false;
  late final ExpenseEditorDraft _draft;
  bool _showErrors = false;

  late final TextEditingController _label = TextEditingController();
  late final TextEditingController _amount = TextEditingController();
  late final TextEditingController _day = TextEditingController();
  late final TextEditingController _note = TextEditingController();
  late final TextEditingController _merchant = TextEditingController();

  @override
  void initState() {
    super.initState();
    _unit = widget.controller.unit;
    _draft = ExpenseEditorDraft(
      store: widget.controller.store,
      kind: 'tpl',
      fields: {
        'label': _label,
        'amount': _amount,
        'day': _day,
        'note': _note,
        'merchant': _merchant,
      },
      extra: () => {
        'type': _type,
        'unit': _unit.key,
        'category': _categoryId,
        'calendar': _solar ? 'jalali' : 'gregorian',
      },
      applyExtra: (b) {
        if (b['type'] == 'income' || b['type'] == 'expense') {
          _type = b['type'] as String;
        }
        _unit = ExpenseUnit.fromKey(b['unit']);
        _categoryId = b['category'] is String ? b['category'] as String : null;
        if (b['calendar'] is String) _solar = b['calendar'] == 'jalali';
        _dirty = true;
      },
      repaint: () {
        if (mounted) setState(() {});
      },
    );
    unawaited(_draft.load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The calendar a new template keeps is the one being read; a resumed
    // draft keeps the one it was written in.
    if (!_calendarRead) {
      _calendarRead = true;
      _solar = NexModuleCalendar.solarOf(context);
    }
  }

  void _changed() {
    setState(() => _dirty = true);
    _draft.changed();
  }

  bool _saving = false;
  bool _dirty = false;

  @override
  void dispose() {
    _draft.dispose();
    _label.dispose();
    _amount.dispose();
    _day.dispose();
    _note.dispose();
    _merchant.dispose();
    super.dispose();
  }

  ExpenseAmountResult get _parsed => parseExpenseAmount(_amount.text, _unit);

  /// The typed day, or null when the field is empty (a plain template).
  /// Throws nothing: an impossible day is refused by [dayError].
  int? get _dayValue {
    final text = _day.text.trim();
    if (text.isEmpty) return null;
    final latin = text.replaceAllMapped(RegExp(r'[۰-۹٠-٩]'), (match) {
      final code = match[0]!.codeUnitAt(0);
      return '${code >= 0x6f0 ? code - 0x6f0 : code - 0x660}';
    });
    final value = int.tryParse(latin);
    return value != null && value >= 1 && value <= 31 ? value : -1;
  }

  String? _dayError(BuildContext context) =>
      _dayValue == -1 ? expenseStrings(context, 'templateDayInvalid') : null;

  Future<void> _save() async {
    if (_label.text.trim().isEmpty || _dayValue == -1) {
      setState(() => _showErrors = true);
      return;
    }
    final result = _parsed;
    if (result.error != null || result.rials == null) {
      setState(() => _showErrors = true);
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    final day = _dayValue;
    final template = ExpenseTemplate(
      id: _draft.recordId,
      label: _label.text.trim(),
      type: _type,
      amountRial: result.rials!,
      categoryId: _categoryId,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      merchant: _merchant.text.trim().isEmpty ? null : _merchant.text.trim(),
      day: day == null || day < 0 ? null : day,
      calendar: day == null || day < 0
          ? null
          : (_solar ? 'jalali' : 'gregorian'),
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
                      NexAdaptiveSegments<String>(
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
                        onSelectionChanged: (set) {
                          setState(() => _type = set.first);
                          _changed();
                        },
                      ),
                      const SizedBox(height: NexSpacing.md),
                      ExpensesAmountField(
                        controller: _amount,
                        unit: _unit,
                        showAllErrors: _showErrors,
                        onValid: (_) => _changed(),
                        onUnitChanged: (unit) {
                          final rials = _parsed.rials;
                          if (rials != null) {
                            _amount.text = expenseAmountInput(rials, unit);
                          }
                          setState(() => _unit = unit);
                          _changed();
                        },
                      ),
                      const SizedBox(height: NexSpacing.md),
                      ExpensesCategoryRow(
                        customCategories: widget.controller.customCategories,
                        selectedId: _categoryId,
                        forIncome: _type == 'income',
                        onChanged: (id) {
                          setState(() => _categoryId = id);
                          _changed();
                        },
                      ),
                      const SizedBox(height: NexSpacing.md),
                      TextField(
                        key: const ValueKey('expenses-template-day'),
                        controller: _day,
                        // A day number is read left to right in either
                        // language (ADR-037).
                        textDirection: TextDirection.ltr,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: s(context, 'templateDayLabel'),
                          hintText: s(context, 'templateDayHint'),
                          errorText: _dayError(context),
                        ),
                        onChanged: (_) => _changed(),
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
