import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'parking_screen.dart';
import 'parking_strings.dart';

/// Where I parked — a stored module, one folder wide.
///
/// Everything about adding, removing, keeping or deleting its data is done
/// by [NexStoredModule]; this class is its id, its look and its screen.
class ParkingModule extends NexStoredModule {
  const ParkingModule();

  @override
  String get id => 'parking';

  @override
  IconData get icon => Icons.local_parking_outlined;

  @override
  NexHue get hue => NexHue.sky;

  @override
  NexModuleStrings get strings => parkingStrings;

  @override
  Widget screen(NexModuleStore store) => ParkingScreen(store: store);
}
