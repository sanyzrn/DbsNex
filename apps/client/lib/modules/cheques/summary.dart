import 'package:nex_client/modules/module_api.dart';

import 'model.dart';
import 'plan_model.dart';
import 'values.dart';

/// Temporary local copy of docs/18, rule 4. No caller is connected to search/AI.
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
  if (record.module != 'cheques') return null;
  if (record.kind == 'cheque') {
    final c = Cheque(record.id, record.body);
    if (!c.valid) return null;
    return ModuleSummary(
      title: c.party,
      detail: c.actionDay == null ? null : chequeDayKey(c.actionDay!),
      private: true,
    );
  }
  if (record.kind == 'plan') {
    final p = InstalmentPlan(record.id, record.body);
    if (!p.valid) return null;
    return ModuleSummary(
      title: p.title,
      detail: chequeDayKey(p.first!),
      private: true,
    );
  }
  return null;
}
