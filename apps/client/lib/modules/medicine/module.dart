import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'medicine_reminders.dart';
import 'medicine_screen.dart';
import 'medicine_strings.dart';

/// Medicine cabinet — a stored module, one folder wide.
///
/// Everything about adding, removing, keeping or deleting its data is done
/// by [NexStoredModule]; this class is its id, its look and its screen.
class MedicineModule extends NexStoredModule {
  const MedicineModule();

  @override
  String get id => 'medicine';

  @override
  IconData get icon => Icons.medication_outlined;

  @override
  NexHue get hue => NexHue.rose;

  @override
  NexModuleStrings get strings => medicineStrings;

  @override
  Widget screen(NexModuleStore store) => MedicineScreen(store: store);

  /// Keeps the reminders ahead when Nex starts and comes back, whether or
  /// not the cabinet is opened (2.8.4).
  @override
  Future<void> keepUp(NexModuleStore store, AppLocalizations l10n) async =>
      MedicineReminders.plan(store, await store.list('medicine'), l10n);
}
