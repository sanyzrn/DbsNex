import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'expenses_rows.dart';
import 'models.dart';
import 'money.dart';

import 'package:nex_client/modules/module_api.dart' show NexModuleMonth;

/// The home's small pieces of arithmetic and lookup, kept out of the screen
/// so the screen stays a layout: which recurring payments to offer, which
/// chips a view has, which template a payment came from, and what an amount
/// field means.

/// Recurring payments that have come due in [month] and are not written down
/// yet. Nothing is offered before its day, and nothing is logged by itself.
List<ExpensesDueOffer> dueOffersFor(
  ExpensesController controller,
  NexModuleMonth month, {
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final todayDate = DateTime(today.year, today.month, today.day);
  final next = month.shift(1).first;
  final last = DateTime(
    next.year,
    next.month,
    next.day,
  ).subtract(const Duration(days: 1));
  final offers = <ExpensesDueOffer>[];
  for (final due in controller.duesBetween(month.first, last)) {
    if (due.done || due.at.isAfter(todayDate)) continue;
    for (final template in controller.templates) {
      if (template.id == due.recordId) {
        offers.add(ExpensesDueOffer(template: template, at: due.at));
        break;
      }
    }
  }
  return offers;
}

/// The category ids a view has a chip for, in the order they first appear,
/// plus the chosen one even when the view has none of it — without that chip
/// there would be no visible way to lift the filter.
List<String> categoriesInScope(Iterable<ExpenseTx> scope, {String? selected}) {
  final ids = <String>[];
  for (final tx in scope) {
    if (!tx.valid || tx.isIncome) continue;
    final id = tx.categoryId ?? 'cat-other';
    if (!ids.contains(id)) ids.add(id);
  }
  if (selected != null && !ids.contains(selected)) ids.add(selected);
  return ids;
}

/// The recurring template's name for a payment that came from one, or null.
String? templateLabelOf(List<ExpenseTemplate> templates, ExpenseTx tx) {
  final id = tx.templateId;
  if (id == null) return null;
  for (final template in templates) {
    if (template.id == id) return template.label;
  }
  return null;
}

/// What an amount field means, in whole rials — null while it is empty or
/// still not a number, which is exactly when a range must not filter.
int? rialsOf(TextEditingController field, ExpenseUnit unit) {
  if (field.text.trim().isEmpty) return null;
  return parseExpenseAmount(field.text, unit, allowZero: true).rials;
}
