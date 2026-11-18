import 'package:nex_client/modules/module_api.dart';

import 'model.dart';

class ModuleSummary {
  const ModuleSummary(this.title, this.detail, {required this.private});
  final String title;
  final String? detail;
  final bool private;
}

// Historical purchase and quote dates, and undated goals, do not fall due.
ModuleSummary? summarize(ModuleRecord record) {
  final goal = AssetGoal.read(record);
  if (goal != null) return ModuleSummary(goal.title, null, private: true);
  final holding = Holding.read(record);
  final quote = Quote.read(record);
  final market = holding?.market ?? quote?.market;
  if (market == null) return null;
  final label = market.custom ? market.name : market.code;
  return ModuleSummary(
    label.isEmpty ? market.type.name : label,
    null,
    private: true,
  );
}

class ModuleDue {
  const ModuleDue({
    required this.id,
    required this.recordKind,
    required this.recordId,
    required this.at,
    required this.title,
    required this.kind,
    this.amountRial,
    required this.done,
    required this.private,
  });
  final String id, recordKind, recordId, title, kind;
  final DateTime at;
  final int? amountRial;
  final bool done, private;
}

List<ModuleDue> duesBetween(DateTime from, DateTime to) => const [];
