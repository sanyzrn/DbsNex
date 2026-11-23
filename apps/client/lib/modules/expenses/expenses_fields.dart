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

  /// Set while this field writes a formatted value into its own controller.
  /// The listener cannot tell such a write from a keystroke; without this
  /// flag, simply opening a saved payment (whose amount is regrouped on the
  /// first frame) counted as an edit, so Back asked «discard your work?»
  /// about a form nobody had touched.
  bool _writing = false;

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
    if (oldWidget.unit != widget.unit ||
        oldWidget.allowZero != widget.allowZero) {
      // The number is the same money; only the way it is said (and so the
      // grouping and the allowed decimals) changed.
      _group();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    // Our own regrouping or unit conversion, not a person's keystroke: no
    // validation round-trip and, above all, no «dirty» form.
    if (_writing) return;
    _writing = true;
    _group();
    _writing = false;
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
    final wasWriting = _writing;
    _writing = true;
    widget.controller.value = TextEditingValue(
      text: grouped.text,
      selection: TextSelection.collapsed(offset: grouped.caret),
    );
    _writing = wasWriting;
  }

  /// Says the same money in [next] — the switch re-words an amount, it never
  /// changes it. The conversion belongs here, with the text it rewrites: a
  /// parent that converted the controller itself was read by this field's
  /// listener in the *old* unit, which regrouped «125000.5 tomans» into
  /// «125,000» and turned 1,250,005 rials into 1,250,000 behind the person's
  /// back.
  void _switchUnit(ExpenseUnit next) {
    if (next == widget.unit) return;
    final amount = parseExpenseAmount(
      widget.controller.text,
      widget.unit,
      allowZero: true,
    );
    // An amount that does not read in the old unit is left as typed and the
    // unit still changes (2.8.19): returning early froze the switch, though
    // the new unit was often exactly what made «1500.5» valid.
    final rials = amount.error == null ? amount.rials : null;
    if (rials != null) {
      final text = expenseAmountInput(rials, next);
      final wasWriting = _writing;
      _writing = true;
      widget.controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      _writing = wasWriting;
    }
    widget.onUnitChanged(next);
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
            if (set.isNotEmpty) _switchUnit(set.first);
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
    final theme = Theme.of(context);
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
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(NexRadius.sm),
        ),
        child: Row(
          children: [
            Icon(
              expenseCategoryIcon(selectedId),
              size: 22,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: NexSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    expenseStrings(context, 'categoryLabel'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(name, style: theme.textTheme.bodyLarge),
                      ),
                      Icon(DirectionalChevron.end(context), size: 20),
                    ],
                  ),
                ],
              ),
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

/// The mark a category carries: a shape a person learns faster than a word,
/// and the same one in the overview, the picker and a record. A category the
/// person added keeps a plain tag — the app does not guess what it is.
IconData expenseCategoryIcon(String? id) => switch (id) {
  'cat-groceries' => Icons.local_grocery_store_outlined,
  'cat-food' => Icons.restaurant_outlined,
  'cat-rent' => Icons.home_work_outlined,
  'cat-home' => Icons.chair_outlined,
  'cat-bills' => Icons.receipt_long_outlined,
  'cat-transport' => Icons.directions_bus_outlined,
  'cat-health' => Icons.medical_services_outlined,
  'cat-children' => Icons.child_care_outlined,
  'cat-education' => Icons.school_outlined,
  'cat-clothes' => Icons.checkroom_outlined,
  'cat-gifts' => Icons.card_giftcard_outlined,
  'cat-fun' => Icons.celebration_outlined,
  'cat-salary' => Icons.payments_outlined,
  'cat-other' => Icons.more_horiz,
  _ => Icons.sell_outlined,
};

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
            leading: Icon(
              expenseCategoryIcon(id),
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
