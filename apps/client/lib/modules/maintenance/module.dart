import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'maintenance_screen.dart';
import 'strings.dart';

/// **Maintenance** — a private log of upkeep for owned things.
///
/// Remembers what was serviced, when, what it cost and what needs
/// attention next, on the intervals the owner sets. Deliberately not
/// the Warranties module (coverage, not upkeep), not reminders, not a
/// car connection — see the README for the boundaries.
class MaintenanceModule extends NexStoredModule {
  const MaintenanceModule();

  @override
  String get id => 'maintenance';

  @override
  IconData get icon => Icons.handyman_outlined;

  @override
  NexHue get hue => NexHue.amber;

  @override
  NexModuleStrings get strings => maintenanceStrings;

  @override
  Widget screen(NexModuleStore store) => MaintenanceScreen(store: store);
}
