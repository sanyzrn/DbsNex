import '../platform/nex_preferences.dart';
import 'assets/module.dart';
import 'converter/module.dart';
import 'cheques/module.dart';
import 'cycle_module.dart';
import 'expenses/module.dart';
import 'family_fund/module.dart';
import 'gold/module.dart';
import 'habits/module.dart';
import 'lent_borrowed/module.dart';
import 'maintenance/module.dart';
import 'medicine/module.dart';
import 'nex_module.dart';
import 'occasions/module.dart';
import 'parking/module.dart';
import 'pause_module.dart';
import 'price_lens/module.dart';
import 'prompt_studio/module.dart';
import 'smoke_free/module.dart';
import 'security_tools/module.dart';
import 'warranty/module.dart';
import 'words/module.dart';

export 'nex_module.dart';

/// Every module Nex ships, in the order the Modules page lists them. Adding
/// one here is what puts its card on that page — see `docs/17-modules.md`.
const List<NexModule> nexModules = [
  CycleModule(),
  PauseModule(),
  HabitsModule(),
  PriceLensModule(),
  LentBorrowedModule(),
  FamilyFundModule(),
  ExpensesModule(),
  GoldModule(),
  AssetsModule(),
  WordsModule(),
  ParkingModule(),
  MedicineModule(),
  WarrantyModule(),
  MaintenanceModule(),
  SmokeFreeModule(),
  OccasionsModule(),
  ConverterModule(),
  PromptStudioModule(),
  SecurityToolsModule(),
  ChequeManagerModule(),
];

/// The modules that are part of the app right now.
/// [modules] in the order this person arranged them (2.8.3); one they have
/// not placed keeps the app's own order, after the ones they have.
List<NexModule> nexModulesInOrder(
  Iterable<NexModule> modules,
  NexPreferences preferences,
) {
  final order = preferences.moduleOrder;
  final list = modules.toList();
  int place(NexModule m) {
    final at = order.indexOf(m.id);
    return at < 0 ? order.length + nexModules.indexOf(m) : at;
  }

  return list..sort((a, b) => place(a).compareTo(place(b)));
}

List<NexModule> nexModulesOn(NexPreferences preferences) => [
  for (final module in nexModules)
    if (module.available && module.isOn(preferences)) module,
];

/// The same modules by id — one lookup where a walk of the whole list used
/// to run on every module write, in the reminder gate.
final Map<String, NexModule> nexModulesById = {
  for (final module in nexModules) module.id: module,
};

/// Whether [id] names a module that is part of the app right now: available
/// in this release and added by the person. The one gate every reach of a
/// module asks — Tools tiles, reminder scheduling, pinned summaries, the
/// brief — so "available and on" is spelled once instead of re-derived in
/// each of them.
bool nexModuleActive(String id, NexPreferences preferences) {
  final module = nexModulesById[id];
  return module != null && module.available && module.isOn(preferences);
}
