import '../platform/nex_preferences.dart';
import 'cycle_module.dart';
import 'expenses/module.dart';
import 'gold/module.dart';
import 'habits/module.dart';
import 'lent_borrowed/module.dart';
import 'maintenance/module.dart';
import 'medicine/module.dart';
import 'nex_module.dart';
import 'occasions/module.dart';
import 'parking/module.dart';
import 'price_lens/module.dart';
import 'smoke_free/module.dart';
import 'warranty/module.dart';
import 'words/module.dart';

export 'nex_module.dart';

/// Every module Nex ships, in the order the Modules page lists them. Adding
/// one here is what puts its card on that page — see `docs/17-modules.md`.
const List<NexModule> nexModules = [
  CycleModule(),
  HabitsModule(),
  PriceLensModule(),
  LentBorrowedModule(),
  ExpensesModule(),
  GoldModule(),
  WordsModule(),
  ParkingModule(),
  MedicineModule(),
  WarrantyModule(),
  MaintenanceModule(),
  SmokeFreeModule(),
  OccasionsModule(),
];

/// The modules that are part of the app right now.
List<NexModule> nexModulesOn(NexPreferences preferences) => [
  for (final module in nexModules)
    if (module.available && module.isOn(preferences)) module,
];
