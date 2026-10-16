import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../widgets/nex_shelf.dart';

/// How far along a planned module is — the badge on its card.
enum NexModuleStage { soon, planned }

/// A module that is not built yet: a name, a line on what it will do and a
/// badge, listed under "On the way" on the Modules page. Nothing of it ships
/// but these words — when one is built it becomes a [NexModule] and leaves
/// this list.
class NexModulePlan {
  const NexModulePlan(this.id, this.icon, this.hue, this.stage);

  final String id;
  final IconData icon;
  final NexHue hue;
  final NexModuleStage stage;

  String title(AppLocalizations l10n) => switch (id) {
    'pause' => l10n.planPauseTitle,
    'smoke-free' => l10n.planSmokeFreeTitle,
    'gold' => l10n.planGoldTitle,
    'parking' => l10n.planParkingTitle,
    'telegram' => l10n.planTelegramTitle,
    'words' => l10n.planWordsTitle,
    'medicine' => l10n.planMedicineTitle,
    'warranty' => l10n.planWarrantyTitle,
    'lent' => l10n.planLentTitle,
    _ => l10n.planHabitsTitle,
  };

  String about(AppLocalizations l10n) => switch (id) {
    'pause' => l10n.planPauseAbout,
    'smoke-free' => l10n.planSmokeFreeAbout,
    'gold' => l10n.planGoldAbout,
    'parking' => l10n.planParkingAbout,
    'telegram' => l10n.planTelegramAbout,
    'words' => l10n.planWordsAbout,
    'medicine' => l10n.planMedicineAbout,
    'warranty' => l10n.planWarrantyAbout,
    'lent' => l10n.planLentAbout,
    _ => l10n.planHabitsAbout,
  };
}

/// What is coming, nearest first.
const List<NexModulePlan> nexModulePlans = [
  NexModulePlan('pause', Icons.air_outlined, NexHue.sky, NexModuleStage.soon),
  NexModulePlan(
    'telegram',
    Icons.send_outlined,
    NexHue.sky,
    NexModuleStage.planned,
  ),
];
