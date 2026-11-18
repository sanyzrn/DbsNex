import 'package:nex_client/modules/module_api.dart';

import 'model.dart';

// Historical purchase and quote dates, and undated goals, do not fall due.
ModuleSummary? summarize(ModuleRecord record) {
  final goal = AssetGoal.read(record);
  if (goal != null) return ModuleSummary(title: goal.title, private: true);
  final holding = Holding.read(record);
  final quote = Quote.read(record);
  final market = holding?.market ?? quote?.market;
  if (market == null) return null;
  final label = market.custom ? market.name : market.code;
  return ModuleSummary(
    title: label.isEmpty ? market.type.name : label,
    private: true,
  );
}

List<ModuleDue> duesBetween(DateTime from, DateTime to) => const [];
