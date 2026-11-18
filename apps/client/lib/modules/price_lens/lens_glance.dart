import 'package:nex_client/modules/module_api.dart';

import 'options.dart';
import 'products.dart';
import 'strings.dart';

/// The pinned tile and quick view of Price Lens (2.8.5): what is left on
/// the shopping list on the tile; the products with remembered prices in
/// the quick view.
Future<ModuleGlance?> lensGlance(
  NexModuleStore store,
  AppLocalizations l10n,
  DateTime now,
) async {
  String t(String key, [Map<String, Object?> args = const {}]) =>
      priceLensStrings.text(l10n, key, args);
  final products = productHistory([
    for (final row in await store.list('memory'))
      ?PriceMemory.fromBody(row.id, row.body, recordedAt: row.updatedAt),
  ]);
  final shopping = await store.list('shopping');
  final bought = {
    for (final row in shopping)
      if (row.body['bought'] == true) row.body['productKey'],
  };
  final needed = products.where((p) => !bought.contains(p.key)).toList();
  if (products.isEmpty) return ModuleGlance(headline: t('glanceEmpty'));
  return ModuleGlance(
    headline: needed.isEmpty
        ? t('glanceAllBought')
        : t('glanceNeeded', {'n': needed.length}),
    detail: t('glanceProducts', {'n': products.length}),
    facts: [
      for (final product in needed.take(6))
        ModuleGlanceFact(product.label, t('glanceToBuy')),
    ],
  );
}
