import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'quit_home_screen.dart';
import 'smoke_strings.dart';
import 'quit_glance.dart';
export 'smoke_strings.dart';

/// Quit Habits — a private, compassionate companion for quitting smoking,
/// vaping, alcohol or anything of the person's own, several at once.
/// Progress, honest estimates, help for the moment of a craving and the
/// patterns behind cravings; never a diagnosis, a recovery timetable, or a
/// promise about anyone's body.
///
/// The module id stays `smoke_free`: it was Smoke-free first, and the records
/// of those who used it are exactly what they were.
class SmokeFreeModule extends NexStoredModule {
  const SmokeFreeModule();

  @override
  String get id => 'smoke_free';

  @override
  IconData get icon => Icons.self_improvement_outlined;

  @override
  NexHue get hue => NexHue.teal;

  @override
  NexModuleStrings get strings => smokeFreeStrings;

  @override
  Widget screen(NexModuleStore store) => QuitHomeScreen(store: store);

  @override
  Future<ModuleGlance?> glance(
    NexModuleStore store,
    AppLocalizations l10n,
    DateTime now,
  ) => quitGlance(store, l10n, now);
}
