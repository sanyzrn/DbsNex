import 'package:nex_client/modules/module_api.dart';

import 'warranty_logic.dart';
import 'warranty_models.dart';
import 'warranty_strings.dart';

/// Warranties' dates and lines in the shared shape (2.8.5), and its glance.
///
/// What falls due is a coverage ending; an archived purchase has nothing
/// left to fall due.
class WarrantyShared {
  const WarrantyShared(this.warranties);

  /// The module's `warranty` records.
  final List<ModuleRecord> warranties;

  /// Everything this module has falling due between [from] and [to].
  List<ModuleDue> duesBetween(DateTime from, DateTime to) => [
    for (final record in warranties)
      if (!WarrantyModels.readArchived(record.body))
        if (WarrantyModels.readDate(record.body, 'coverageEnd') case final end?)
          // The line the calendar shows needs a name to carry. A record
          // without a product (an old or external write) falls back to its
          // brand, and one with neither is left off the shared calendar
          // rather than arriving as a blank line; it stays in the module's
          // own list under "date unavailable".
          if (_dueTitle(record).isNotEmpty)
            if (!DateTime(end.year, end.month, end.day).isBefore(from) &&
                !DateTime(end.year, end.month, end.day).isAfter(to))
              ModuleDue(
                id: 'coverage-end:${record.id}',
                recordKind: WarrantyModels.warranty,
                recordId: record.id,
                at: DateTime(end.year, end.month, end.day),
                title: _dueTitle(record),
                kind: 'coverage-end',
                passes: true,
              ),
  ]..sort((a, b) => a.at.compareTo(b.at));

  /// What a coverage ending is called on the shared calendar: the product,
  /// or the brand when a record was saved without one.
  static String _dueTitle(ModuleRecord record) {
    final product = WarrantyModels.readString(record.body, 'product').trim();
    if (product.isNotEmpty) return product;
    return WarrantyModels.readString(record.body, 'brand').trim();
  }

  /// One line about [record], in the person's own words; null to keep it out.
  static ModuleSummary? summarize(ModuleRecord record) {
    if (record.kind != WarrantyModels.warranty) return null;
    final product = WarrantyModels.readString(record.body, 'product').trim();
    if (product.isEmpty) return null;
    final detail = [
      WarrantyModels.readString(record.body, 'brand').trim(),
      WarrantyModels.readString(record.body, 'merchant').trim(),
    ].where((s) => s.isNotEmpty).join(' · ');
    return ModuleSummary(
      title: product,
      detail: detail.isEmpty ? null : detail,
    );
  }
}

/// The pinned tile and quick view of Warranties (2.8.5): the next coverage
/// to end on the tile; those ending in the coming months in the quick view.
Future<ModuleGlance?> warrantyGlance(
  NexModuleStore store,
  AppLocalizations l10n,
  DateTime now,
) async {
  String t(String key, [Map<String, Object?> args = const {}]) =>
      warrantyStrings.text(l10n, key, args);
  final records = await store.list(WarrantyModels.warranty);
  final live = records
      .where((r) => !WarrantyModels.readArchived(r.body))
      .toList();
  if (live.isEmpty) return ModuleGlance(headline: t('glanceEmpty'));
  final today = DateTime(now.year, now.month, now.day);
  final ending = WarrantyShared(live)
      .duesBetween(today, today.add(const Duration(days: 365)));
  final covered = live.where((r) {
    final end = WarrantyModels.readDate(r.body, 'coverageEnd');
    return end != null && !WarrantyLogic.statusOf(end, now).expired;
  }).length;
  final soon = ending
      .where(
        (d) =>
            d.at.difference(today).inDays <= WarrantyModels.expiringWindowDays,
      )
      .length;
  final next = ending.firstOrNull;
  return ModuleGlance(
    headline: next == null
        ? t('glanceCovered', {'n': covered})
        : t('glanceNextEnds', {'what': next.title}),
    detail: next == null
        ? null
        : soon > 1
        ? t('glanceSoon', {'n': soon})
        : nexDueWhen(l10n, next.at, today),
    facts: [
      for (final due in ending.take(5))
        ModuleGlanceFact(
          due.title,
          nexDueWhen(l10n, due.at, today),
          strong: identical(due, next),
        ),
      ModuleGlanceFact(
        t('glanceCoveredLabel'),
        nexDigits('$covered', persian: l10n.localeName.startsWith('fa')),
      ),
    ],
  );
}
