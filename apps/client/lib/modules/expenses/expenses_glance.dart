import 'package:nex_client/modules/module_api.dart';

import 'expenses_summary.dart';
import 'logic.dart';
import 'models.dart';
import 'strings.dart';

/// The pinned tile and quick view of Expenses (2.8.5): the month's spending
/// on the tile — unless amounts are hidden in the module, when it says only
/// how many payments there were — and the month in figures in the quick
/// view, with the largest category and a recurring payment waiting today.
Future<ModuleGlance?> expensesGlance(
  NexModuleStore store,
  AppLocalizations l10n,
  DateTime now,
) async {
  String t(String key, [Map<String, Object?> args = const {}]) =>
      expenseStrings.text(l10n, key, args);
  final txs = [
    for (final row in await store.list('tx'))
      ExpenseTx.fromBody(row.id, row.body),
  ];
  final templates = [
    for (final row in await store.list('tpl'))
      ?ExpenseTemplate.fromBody(row.id, row.body),
  ];
  final custom = [
    for (final row in await store.list('cat'))
      ?ExpenseCategory.fromBody(row.id, row.body),
  ];
  final hidden = (await store.get('settings', 'main'))?['hideAmounts'] == true;
  final solar = store.solarCalendar;
  final month = NexModuleMonth.of(now, solar: solar);
  final inMonth = txsInMonth(txs, month, solar: solar).toList();
  final totals = expenseTotals(inMonth);
  final today = DateTime(now.year, now.month, now.day);
  final offered = ExpenseSchedule(
    templates: templates,
    txs: txs,
  ).duesBetween(today, today).where((d) => !d.done).toList();
  if (txs.isEmpty && templates.isEmpty) {
    return ModuleGlance(headline: t('glanceEmpty'));
  }
  String money(BigInt rial) => hidden ? '••••' : nexTomanText(rial, l10n);
  final slices = expenseCategoryBreakdown(txs, month: month, solar: solar);
  String category(String id) {
    for (final c in custom) {
      if (c.id == id) return c.label;
    }
    return defaultExpenseCategoryIds.contains(id) ? t(id) : t('cat-other');
  }

  return ModuleGlance(
    headline: hidden
        ? t('glanceCount', {'n': inMonth.length})
        : t('glanceSpent', {'amount': money(totals.expense)}),
    detail: offered.isNotEmpty
        ? t('glanceOffer', {'what': offered.first.title})
        : t('glanceCount', {'n': inMonth.length}),
    facts: [
      ModuleGlanceFact(
        t('glanceSpentLabel'),
        money(totals.expense),
        strong: true,
      ),
      if (totals.hasIncome) ...[
        ModuleGlanceFact(t('glanceIncome'), money(totals.income)),
        ModuleGlanceFact(t('glanceLeft'), money(totals.left)),
      ],
      if (slices.isNotEmpty)
        ModuleGlanceFact(
          t('glanceTop'),
          '${category(slices.first.categoryId)}: ${money(slices.first.total)}',
        ),
      for (final due in offered) ModuleGlanceFact(t('glanceToLog'), due.title),
    ],
  );
}
