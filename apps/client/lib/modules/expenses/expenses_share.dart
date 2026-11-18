import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'logic.dart';
import 'models.dart';
import 'money.dart';
import 'strings.dart';

/// The month as words: the total, the categories, and what was left, for a
/// partner or a family group. Plain text, shared with the phone's own sheet
/// (`nexModuleShareText`); no picture, no link, no server.
///
/// The amounts are said in the unit the person chose, with Persian digits in
/// Persian, exactly as the screen says them — sharing never quietly changes
/// the number or the unit.
String expensesShareText(
  BuildContext context, {
  required NexModuleMonth month,
  required Iterable<ExpenseTx> txs,
  required ExpenseUnit unit,
  required String Function(String categoryId) categoryName,
}) {
  final s = expenseStrings;
  final persian = NexModuleStrings.persian(context);
  final totals = expenseTotals(txs);
  final slices = expenseCategoryBreakdown(
    txs,
    month: month,
    solar: month.solar,
  );
  String money(int rials) => formatExpenseAmount(rials, unit, persian: persian);
  final lines = <String>[
    s(context, 'shareTitle', {'month': month.title(context)}),
    '',
    for (final slice in slices)
      '${categoryName(slice.categoryId)}: ${money(slice.total.toInt())}',
    if (slices.isEmpty) s(context, 'nothingSpent'),
    '',
    s(context, 'shareTotal', {'amount': money(totals.expense.toInt())}),
    if (totals.hasIncome) ...[
      s(context, 'shareIncome', {'amount': money(totals.income.toInt())}),
      s(context, 'shareLeft', {'amount': money(totals.left.toInt())}),
    ],
    '',
    s(context, 'shareFooter'),
  ];
  return lines.join('\n');
}
