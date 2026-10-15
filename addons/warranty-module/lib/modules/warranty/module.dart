import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'warranty_screen.dart';
import 'warranty_strings.dart';

/// Warranties — a stored module, one folder wide.
///
/// Everything about adding, removing, keeping or deleting its data is done
/// by [NexStoredModule]; this class is its id, its look and its screen.
class WarrantyModule extends NexStoredModule {
  const WarrantyModule();

  @override
  String get id => 'warranty';

  @override
  IconData get icon => Icons.verified_outlined;

  @override
  NexHue get hue => NexHue.amber;

  @override
  NexModuleStrings get strings => warrantyStrings;

  @override
  Widget screen(NexModuleStore store) => WarrantyScreen(store: store);
}
