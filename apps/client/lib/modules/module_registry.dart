import '../platform/nex_preferences.dart';
import 'cycle_module.dart';
import 'nex_module.dart';

export 'nex_module.dart';

/// Every module Nex ships, in the order the Modules page lists them. Adding
/// one here is what puts its card on that page — see `docs/17-modules.md`.
const List<NexModule> nexModules = [CycleModule()];

/// The modules that are part of the app right now.
List<NexModule> nexModulesOn(NexPreferences preferences) => [
  for (final module in nexModules)
    if (module.isOn(preferences)) module,
];
