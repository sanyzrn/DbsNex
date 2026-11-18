import 'package:nex_client/modules/module_api.dart';

import 'gold_models.dart';
import 'gold_strings.dart';

/// The pinned tile and quick view of Gold Check (2.8.5): how many estimates
/// are saved and the latest's day on the tile; the latest few with their
/// totals in the quick view.
Future<ModuleGlance?> goldGlance(
  NexModuleStore store,
  AppLocalizations l10n,
  DateTime now,
) async {
  String t(String key, [Map<String, Object?> args = const {}]) =>
      goldStrings.text(l10n, key, args);
  final quotes = [
    for (final record in await store.list('quote'))
      GoldQuote.fromRecord(record.id, record.body),
  ]..sort((a, b) => b.savedAtIso.compareTo(a.savedAtIso));
  if (quotes.isEmpty) return ModuleGlance(headline: t('glanceEmpty'));
  final latest = DateTime.tryParse(quotes.first.savedAtIso);
  final today = DateTime(now.year, now.month, now.day);
  return ModuleGlance(
    headline: t('glanceSaved', {'n': quotes.length}),
    detail: latest == null
        ? null
        : t('glanceLatest', {
            'when': nexDueWhen(l10n, latest.toLocal(), today),
          }),
    facts: [
      for (final q in quotes.take(5))
        ModuleGlanceFact(
          q.title.isEmpty
              ? (q.shop.isEmpty ? t('glanceUntitled') : q.shop)
              : q.title,
          nexTomanText(BigInt.from(q.estimatedTotalRial), l10n),
          strong: identical(q, quotes.first),
        ),
    ],
  );
}
