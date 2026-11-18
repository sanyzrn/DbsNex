import 'package:nex_client/modules/module_api.dart';

import 'options.dart';

ModuleSummary? summarize(ModuleRecord record) {
  if (record.module != 'price_lens') return null;
  if (record.kind == 'memory') {
    final m = PriceMemory.fromBody(record.id, record.body);
    return m == null
        ? null
        : ModuleSummary(
            title: m.productLabel,
            detail: m.shop.isEmpty ? null : m.shop,
            private: true,
          );
  }
  if (record.kind == 'comparison') {
    final comparison = SavedComparison.fromBody(record.id, record.body);
    if (comparison == null || comparison.options.any((o) => !optionSafe(o))) {
      return null;
    }
    return ModuleSummary(
      title: comparison.options.map((o) => o.label).join(' · '),
      private: true,
    );
  }
  return null;
}

/// A historical shopping date is not something falling due. This module
/// deliberately creates no calendar event or reminder for a past price.
List<ModuleDue> duesBetween(DateTime from, DateTime to) => const [];
