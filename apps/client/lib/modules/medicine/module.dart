import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

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
}
