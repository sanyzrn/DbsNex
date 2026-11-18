/// The lines a module owes the rest of the app: everything that falls due,
/// in one shape, and one line about each record.
///
/// `ModuleDue` and `ModuleSummary` are copied here with the fields
/// `docs/18-module-kit.md` names (rules 1 and 4), until the kit provides
/// them — the same shape `words_summary.dart` uses, so one move can replace
/// every copy later. Nothing reads these yet; the module's own screens do,
/// and its tests hold them.
library;

import 'package:nex_client/modules/module_api.dart'
    show ModuleRecord, NexModuleMonth;

import 'models.dart';
import 'money.dart';

/// One thing this module has falling due, for the shared life calendar.
class ModuleDue {
  const ModuleDue({
    required this.id,
    required this.recordKind,
    required this.recordId,
    required this.at,
    required this.title,
    required this.kind,
    this.amountRial,
    this.done = false,
    this.private = false,
  });

  /// Stable: the same rent for the same month is the same item next time.
  final String id;
  final String recordKind;
  final String recordId;

  /// When it falls due — local, at midnight for a date-only item.
  final DateTime at;
  final String title;
  final String kind;

  /// Positive in, negative out.
  final int? amountRial;

  /// Already written down for that month.
  final bool done;

  /// Money detail: shown only discreetly.
  final bool private;
}

/// One line about a record, for the consent-gated search and brief later.
class ModuleSummary {
  const ModuleSummary({required this.title, this.detail, this.private = false});

  final String title;
  final String? detail;
  final bool private;
}

/// The recurring templates, read as dates: «rent, the 5th of every month».
///
/// The calendar each template was set in is kept with it, so the same
/// template keeps meaning the same day when the app's calendar changes.
class ExpenseSchedule {
  ExpenseSchedule({
    required Iterable<ExpenseTemplate> templates,
    required Iterable<ExpenseTx> txs,
  }) : templates = List.unmodifiable(templates),
       txs = List.unmodifiable(txs);

  final List<ExpenseTemplate> templates;
  final List<ExpenseTx> txs;

  /// Everything this module has falling due between [from] and [to].
  List<ModuleDue> duesBetween(DateTime from, DateTime to) {
    final firstDay = DateTime(from.year, from.month, from.day);
    final lastDay = DateTime(to.year, to.month, to.day);
    final dues = <ModuleDue>[];
    for (final template in templates) {
      final day = template.day;
      if (day == null) continue;
      var month = NexModuleMonth.of(from, solar: template.solar);
      // Walk forward from the month `from` falls in; a due day that has
      // already passed simply falls outside the range.
      while (!month.first.isAfter(lastDay)) {
        final at = month.dayAt(day.clamp(1, month.days));
        if (!at.isBefore(firstDay) && !at.isAfter(lastDay)) {
          dues.add(
            ModuleDue(
              id: 'tpl-${template.id}-${monthStartIso(month)}',
              recordKind: 'tpl',
              recordId: template.id,
              at: at,
              title: template.label,
              kind: 'expense-recurring',
              amountRial: template.type == 'income'
                  ? template.amountRial
                  : -template.amountRial,
              done: loggedFor(template, month),
              private: true,
            ),
          );
        }
        month = month.shift(1);
      }
    }
    dues.sort((a, b) {
      final byDate = a.at.compareTo(b.at);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    return dues;
  }

  /// Whether this template's [month] is already written down.
  bool loggedFor(ExpenseTemplate template, NexModuleMonth month) {
    final period = monthStartIso(month);
    return txs.any((tx) => tx.templateId == template.id && tx.period == period);
  }
}

/// The built-in categories' English names, for the language-less summary
/// line. A person's own category keeps the name they typed.
const _categoryNames = <String, String>{
  'cat-groceries': 'Groceries',
  'cat-food': 'Food',
  'cat-rent': 'Rent',
  'cat-home': 'Home',
  'cat-bills': 'Bills',
  'cat-transport': 'Transport',
  'cat-health': 'Health',
  'cat-children': 'Children',
  'cat-education': 'Education',
  'cat-clothes': 'Clothes',
  'cat-gifts': 'Gifts',
  'cat-fun': 'Fun',
  'cat-salary': 'Salary',
  'cat-other': 'Other',
};

/// One line about [record], in the person's own words; null to keep it out.
///
/// The module API passes a record, not a language, so the line uses the
/// words the person typed and plain Latin figures; the shared contract will
/// gain a language when the search does. Money is private here.
ModuleSummary? summarize(ModuleRecord record) {
  final body = record.body;
  // A record written before the rial upgrade keeps `amount` in minor units;
  // it still gets its line, with the same money.
  final amount = body['amountRial'] is int
      ? body['amountRial']
      : legacyAmountRial(body);
  if (record.kind == 'tx') {
    if (amount is! int) return null;
    final note = _text(body['note']);
    final merchant = _text(body['merchant']);
    final category = _text(body['category']);
    final income = body['type'] == 'income';
    final title =
        note ??
        merchant ??
        (category == null ? null : _categoryNames[category]) ??
        (income ? 'Income' : 'Expense');
    final date = _text(body['date'])?.split('T').first;
    return ModuleSummary(
      title: title,
      detail: [
        income ? 'Income' : 'Expense',
        formatExpenseAmount(amount, ExpenseUnit.toman, persian: false),
        ?date,
      ].join(' · '),
      private: true,
    );
  }
  final label = _text(body['label']);
  if (label != null && body['type'] is String) {
    return ModuleSummary(
      title: label,
      detail: [
        body['type'] == 'income' ? 'Recurring income' : 'Recurring payment',
        if (body['day'] is int) 'day ${body['day']}',
        if (amount is int)
          formatExpenseAmount(amount, ExpenseUnit.toman, persian: false),
      ].join(' · '),
      private: true,
    );
  }
  if (amount is int && body['start'] is String) {
    final category = _text(body['category']);
    return ModuleSummary(
      title: category == null
          ? 'Monthly limit'
          : (_categoryNames[category] ?? 'Budget'),
      detail: formatExpenseAmount(amount, ExpenseUnit.toman, persian: false),
      private: true,
    );
  }
  if (label != null) {
    return ModuleSummary(title: label, private: false);
  }
  return null;
}

String? _text(Object? raw) =>
    raw is String && raw.trim().isNotEmpty ? raw.trim() : null;
