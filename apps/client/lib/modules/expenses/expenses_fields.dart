import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'expenses_widgets.dart';
import 'models.dart';
import 'money.dart';
import 'strings.dart';

/// The form pieces the transaction editor, the template editor and the
/// budget editor share: the amount field with its per-currency rules,
/// the currency and category pickers, the rial/toman choice, and the
/// date and time rows. Everything is 48dp at the tap floor, LTR where
/// numbers are, and worded from the module's strings.

/// Which unit an IRR amount is entered in.
enum IrrUnit { rial, toman }

extension IrrUnitName on IrrUnit {
  String label(BuildContext context) => switch (this) {
    IrrUnit.rial => expenseStrings(context, 'rialUnit'),
    IrrUnit.toman => expenseStrings(context, 'tomanUnit'),
  };
}

/// The amount field: digits only, one decimal separator at most, and
/// the rules of the chosen currency enforced live — [onChanged] hears
/// the parsed minor units whenever they are valid, and the error text
/// appears as soon as the input stops being money.
class ExpensesAmountField extends StatefulWidget {
  const ExpensesAmountField({
    super.key,
    required this.controller,
    required this.currency,
    required this.unit,
    required this.onUnitChanged,
    this.showAllErrors = false,
    this.onValid,
    this.initialMinor,
    this.allowZero = false,
  });

  final TextEditingController controller;
  final ExpenseCurrency currency;

  /// Only meaningful for IRR; other currencies ignore it.
  final IrrUnit unit;
  final ValueChanged<IrrUnit> onUnitChanged;

  /// Set after a failed Save: "zero" is quiet while typing (a person
  /// may simply not have started) but must be said when it blocks.
  final bool showAllErrors;

  /// Called with the valid minor units, or null.
  final ValueChanged<int?>? onValid;

  /// Prefills from an existing record.
  final int? initialMinor;
  final bool allowZero;

  @override
  State<ExpensesAmountField> createState() => _ExpensesAmountFieldState();
}

class _ExpensesAmountFieldState extends State<ExpensesAmountField> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _errorOf(context);
    final suffix = widget.currency.code == 'IRR'
        ? widget.unit.label(context)
        : widget.currency.code;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.end,
          style: theme.textTheme.headlineSmall,
          decoration: InputDecoration(
            suffixText: suffix,
            errorText: error,
            hintText: expenseStrings(context, 'amountHint'),
          ),
          // Rebuilds the field so the error text follows the typing,
          // and tells the sheet whenever the amount becomes valid.
          onChanged: (text) {
            setState(() {});
            widget.onValid?.call(_minorOrNull());
          },
        ),
        if (widget.currency.code == 'IRR') ...[
          const SizedBox(height: NexSpacing.sm),
          _IrrUnitToggle(unit: widget.unit, onChanged: widget.onUnitChanged),
          Text(
            expenseStrings(context, 'tomanHint'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  String? _errorOf(BuildContext context) {
    final result = _parse();
    return switch (result.error) {
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

  ExpenseAmountResult _parse() =>
      widget.currency.code == 'IRR' && widget.unit == IrrUnit.toman
      ? parseTomanAmount(widget.controller.text, allowZero: widget.allowZero)
      : parseExpenseAmount(
          widget.controller.text,
          widget.currency,
          allowZero: widget.allowZero,
        );

  int? _minorOrNull() => _parse().minor;
}

class _IrrUnitToggle extends StatelessWidget {
  const _IrrUnitToggle({required this.unit, required this.onChanged});

  final IrrUnit unit;
  final ValueChanged<IrrUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String labelOf(IrrUnit u) => u.label(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: NexSpacing.xs),
      child: SegmentedButton<IrrUnit>(
        segments: [
          for (final u in IrrUnit.values)
            ButtonSegment(value: u, label: Text(labelOf(u))),
        ],
        selected: {unit},
        onSelectionChanged: (set) => onChanged(set.first),
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.standard,
          textStyle: WidgetStatePropertyAll(theme.textTheme.labelLarge),
        ),
      ),
    );
  }
}

/// A row that opens the currency picker sheet.
class ExpensesCurrencyRow extends StatelessWidget {
  const ExpensesCurrencyRow({
    super.key,
    required this.currency,
    required this.onChanged,
  });

  final ExpenseCurrency currency;
  final ValueChanged<ExpenseCurrency> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const ValueKey('expenses-currency'),
      onTap: () => unawaited(
        _pickCurrency(context).then((picked) {
          if (picked != null) onChanged(picked);
        }),
      ),
      borderRadius: BorderRadius.circular(NexRadius.md),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: expenseStrings(context, 'currencyLabel'),
          contentPadding: const EdgeInsetsDirectional.symmetric(
            horizontal: NexSpacing.md,
            vertical: NexSpacing.md,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${currency.code} · ${expenseStrings(context, 'currency-${currency.code}')}',
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.start,
              ),
            ),
            Icon(DirectionalChevron.end(context), size: 20),
          ],
        ),
      ),
    );
  }

  Future<ExpenseCurrency?> _pickCurrency(BuildContext context) =>
      nexShowSheet<ExpenseCurrency>(
        context: context,
        builder: (sheetContext) => _CurrencyPickerSheet(selected: currency),
      );
}

class _CurrencyPickerSheet extends StatelessWidget {
  const _CurrencyPickerSheet({required this.selected});

  final ExpenseCurrency selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          expenseStrings(context, 'currencyLabel'),
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: NexSpacing.sm),
        for (final currency in expenseCurrencies)
          ListTile(
            title: Text(
              currency.code,
              textDirection: TextDirection.ltr,
              style: theme.textTheme.titleMedium,
            ),
            subtitle: Text(
              expenseStrings(context, 'currency-${currency.code}'),
            ),
            trailing: currency.code == selected.code
                ? const Icon(Icons.check)
                : null,
            onTap: () => Navigator.pop(context, currency),
          ),
      ],
    );
  }
}

/// A row that opens the category picker sheet: defaults plus the
/// person's own, income ones first for income.
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
        : _nameOf(context, selectedId!);
    return InkWell(
      key: const ValueKey('expenses-category'),
      onTap: () => unawaited(
        _pickCategory(context).then((picked) {
          if (picked != null) onChanged(picked);
        }),
      ),
      borderRadius: BorderRadius.circular(NexRadius.md),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: expenseStrings(context, 'categoryLabel'),
          contentPadding: const EdgeInsetsDirectional.symmetric(
            horizontal: NexSpacing.md,
            vertical: NexSpacing.md,
          ),
        ),
        child: Row(
          children: [
            Expanded(child: Text(name)),
            Icon(DirectionalChevron.end(context), size: 20),
          ],
        ),
      ),
    );
  }

  String _nameOf(BuildContext context, String id) {
    for (final custom in customCategories) {
      if (custom.id == id) return custom.label;
    }
    return defaultExpenseCategoryIds.contains(id)
        ? expenseStrings(context, id)
        : expenseStrings(context, 'cat-other');
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
    String nameOf(String id) {
      for (final custom in customCategories) {
        if (custom.id == id) return custom.label;
      }
      return expenseStrings(context, id);
    }

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
            title: Text(nameOf(id)),
            trailing: id == selectedId ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, id),
          ),
      ],
    );
  }
}
