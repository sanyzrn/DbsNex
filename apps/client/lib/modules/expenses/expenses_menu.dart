import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'controller.dart';
import 'expenses_budget.dart';
import 'expenses_editors.dart';
import 'expenses_share.dart';
import 'expenses_sheets.dart';
import 'expenses_templates.dart';
import 'models.dart';

/// What the home's menu does: the month's budget, the categories, the
/// templates, and sharing the month as text. A sheet or the phone's share
/// sheet; never a page of its own.
Future<void> showExpensesMenu(
  BuildContext context, {
  required ExpensesController controller,
  required String action,
  required NexModuleMonth month,
  required List<ExpenseTx> scope,
  required String Function(String categoryId) categoryName,
}) async {
  switch (action) {
    case 'budgets':
      await showExpensesBudgetEditor(
        context,
        controller: controller,
        month: month,
        existing: controller.budgetFor(monthStartIso(month), null),
      );
    case 'categories':
      await showExpensesCategories(context, controller: controller);
    case 'templates':
      await showExpensesTemplates(
        context,
        controller: controller,
        onUse: (template) => unawaited(
          showExpensesTxEditor(
            context,
            controller: controller,
            template: template,
          ),
        ),
      );
    case 'share':
      final text = expensesShareText(
        context,
        month: month,
        txs: scope,
        unit: controller.unit,
        categoryName: categoryName,
      );
      try {
        await nexModuleShareText(text);
      } catch (_) {
        // A share sheet that cannot open leaves the book untouched.
      }
  }
}
