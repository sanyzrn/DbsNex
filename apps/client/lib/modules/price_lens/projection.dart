import 'package:nex_client/modules/module_api.dart';

import 'options.dart';

class ModuleSummary {
  const ModuleSummary({
    required this.title,
    this.detail,
    required this.private,
  });
  final String title;
  final String? detail;
  final bool private;
}

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

class ModuleDue {
  const ModuleDue({
    required this.id,
    required this.recordKind,
    required this.recordId,
    required this.at,
    required this.title,
    required this.kind,
    required this.amountRial,
    required this.done,
    required this.private,
  });
  final String id, recordKind, recordId, title, kind;
  final DateTime at;
  final int? amountRial;
  final bool done, private;
}

/// A historical shopping date is not something falling due. This module
/// deliberately creates no calendar event or reminder for a past price.
List<ModuleDue> duesBetween(DateTime from, DateTime to) => const [];
