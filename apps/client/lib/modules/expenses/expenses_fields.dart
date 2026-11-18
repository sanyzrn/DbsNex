import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'models.dart';
import 'money.dart';
import 'money_input.dart';
import 'strings.dart';

/// The form pieces the transaction editor, the template editor and the
/// budget editor share: the amount field (grouped as it is typed, in Persian
/// digits on the Persian side, with the rial/toman choice) and the category
/// picker. Everything is 48dp at the tap floor, LTR where numbers are, and
/// worded from the module's strings.

/// The amount field: digits in either script, grouping as the person types,
/// and at most the unit's own decimals — [onValid] hears the whole rials
/// whenever the text is money, and the error text appears as soon as it is
/// not.
class ExpensesAmountField extends StatefulWidget {
  const ExpensesAmountField({
    super.key,
    required this.controller,
    required this.unit,
    required this.onUnitChanged,
    this.showAllErrors = false,
    this.onValid,
    this.allowZero = false,
  });

  final TextEditingController controller;
  final ExpenseUnit unit;
  final ValueChanged<ExpenseUnit> onUnitChanged;

  /// Set after a failed Save: "zero" is quiet while typing (a person may
  /// simply not have started) but must be said when it blocks.
  final bool showAllErrors;

  /// Called with the whole rials, or null.
  final ValueChanged<int?>? onValid;
  final bool allowZero;

  @override
  State<ExpensesAmountField> createState() => _ExpensesAmountFieldState();
}

class _ExpensesAmountFieldState extends State<ExpensesAmountField> {
  bool _persian = false;
  bool _grouping = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _persian = NexModuleStrings.persian(context);
    // Not only what is typed: a draft, an edited record and the unit switch
    // all put a number in this controller, and every one of them has to read
    // in the script of the page.
    _group();
  }

  @override
  void didUpdateWidget(ExpensesAmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (_grouping) return;
    _grouping = true;
    _group();
    _grouping = false;
    if (mounted) setState(() {});
    widget.onValid?.call(
      parseExpenseAmount(
        widget.controller.text,
        widget.unit,
        allowZero: widget.allowZero,
      ).rials,
    );
  }

  /// Groups as the person types and puts the caret back where it was.
  void _group() {
    final value = widget.controller.value;
    final grouped = groupAmountEdit(
      value.text,
      value.selection.baseOffset < 0
          ? value.text.length
          : value.selection.baseOffset,
      widget.unit.decimals,
      persian: _persian,
    );
    if (grouped.text == value.text) return;
    widget.controller.value = TextEditingValue(
      text: grouped.text,
      selection: TextSelection.collapsed(offset: grouped.caret),
    );
  }

  ExpenseAmountResult get _parsed => parseExpenseAmount(
    widget.controller.text,
    widget.unit,
    allowZero: widget.allowZero,
  );

  String? _errorOf(BuildContext context) {
    return switch (_parsed.error) {
      null => null,
      // Quiet until there is something to say: empty is just "not
      // started", and zero/negative only matter when Save is refused.
      ExpenseAmountError.empty =>
        widget.showAllErrors ? expenseStrings(context, 'errEmpty') : null,
      ExpenseAmountError.zero =>
        widget.showAllErrors ? expenseStrings(context, 'errZero') : null,
      ExpenseAmountError.negative =>
        widget.showAllErrors ? expenseStrings(context, 'errNegative') : null,
      ExpenseAmountError.notANumber => expenseStrings(context, 'errNotNumber'),
      ExpenseAmountError.tooPrecise => expenseStrings(context, 'errTooPrecise'),
      ExpenseAmountError.tooLarge => expenseStrings(context, 'errTooLarge'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final persian = NexModuleStrings.persian(context);
    final unitWord = expenseUnitWord(widget.unit, persian: persian);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          expenseStrings(context, 'amountLabel'),
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: NexSpacing.xs),
        TextField(
          key: const ValueKey('expenses-amount'),
          controller: widget.controller,
          autofocus: widget.controller.text.isEmpty,
          keyboardType: TextInputType.numberWithOptions(
            decimal: widget.unit.decimals > 0,
          ),
          // Digits run left to right in both languages; in Persian the
          // field starts at the right, beside the unit word.
          textDirection: persian ? TextDirection.rtl : TextDirection.ltr,
          textAlign: TextAlign.start,
          style: theme.textTheme.headlineSmall,
          decoration: InputDecoration(
            suffixText: unitWord,
            hintText: expenseStrings(context, 'amountHint'),
            errorText: _errorOf(context),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: NexSpacing.sm),
        NexAdaptiveSegments<ExpenseUnit>(
          segments: [
            for (final unit in ExpenseUnit.values)
              ButtonSegment(
                value: unit,
                label: Text(
                  expenseStrings(
                    context,
                    unit == ExpenseUnit.rial ? 'rialUnit' : 'tomanUnit',
                  ),
                ),
              ),
          ],
          selected: {widget.unit},
          onSelectionChanged: (set) {
            if (set.isNotEmpty) widget.onUnitChanged(set.first);
          },
        ),
        const SizedBox(height: NexSpacing.xs),
        Text(
          expenseStrings(context, 'tomanHint'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// A row that opens the category picker sheet: defaults plus the person's
/// own, income ones first for income.
class ExpensesCategoryRow extends StatelessWidget {
  const ExpensesCategoryRow({
    super.key,
    required this.customCategories,
    required this.selectedId,
    required this.onChanged,
    required this.forIncome,
  });

  final List<ExpenseCategory> customCategories;
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  final bool forIncome;

  @override
  Widget build(BuildContext context) {
    final name = selectedId == null
        ? expenseStrings(context, 'categoryNone')
        : categoryNameOf(context, selectedId!, customCategories);
    return InkWell(
      key: const ValueKey('expenses-category'),
      onTap: () => unawaited(
        _pickCategory(context).then((picked) {
          if (picked != null) onChanged(picked);
        }),
      ),
      borderRadius: BorderRadius.circular(NexRadius.md),
      // A plain bordered row rather than an InputDecorator: the floating
      // label of a decorated field is clipped by the row's own border at
      // large text sizes, and this one has to read as a field, not a caption.
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: NexSpacing.md,
          vertical: NexSpacing.sm,
        ),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(NexRadius.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              expenseStrings(context, 'categoryLabel'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                Icon(DirectionalChevron.end(context), size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickCategory(BuildContext context) => nexShowSheet<String>(
    context: context,
    builder: (sheetContext) => _CategoryPickerSheet(
      customCategories: customCategories,
      selectedId: selectedId,
      forIncome: forIncome,
    ),
  );
}

/// The name of a category — the person's own words, or the built-in word in
/// the language of the page.
String categoryNameOf(
  BuildContext context,
  String id,
  List<ExpenseCategory> customCategories,
) {
  for (final custom in customCategories) {
    if (custom.id == id) return custom.label;
  }
  return defaultExpenseCategoryIds.contains(id)
      ? expenseStrings(context, id)
      : expenseStrings(context, 'cat-other');
}

class _CategoryPickerSheet extends StatelessWidget {
  const _CategoryPickerSheet({
    required this.customCategories,
    required this.selectedId,
    required this.forIncome,
  });

  final List<ExpenseCategory> customCategories;
  final String? selectedId;
  final bool forIncome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ids = [
      // Salary leads when income is being entered; it is a default too.
      if (forIncome) 'cat-salary',
      for (final id in defaultExpenseCategoryIds)
        if (id != 'cat-salary' || !forIncome) id,
      ...customCategories.map((c) => c.id),
    ];
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsetsDirectional.fromSTEB(
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.md,
      ),
      children: [
        Text(
          expenseStrings(context, 'chooseCategory'),
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: NexSpacing.sm),
        for (final id in ids)
          ListTile(
            title: Text(categoryNameOf(context, id, customCategories)),
            trailing: id == selectedId ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, id),
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
