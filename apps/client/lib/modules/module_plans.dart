import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../widgets/nex_shelf.dart';
import 'nex_module.dart';

/// How far along a planned module is — the badge on its card.
enum NexModuleStage { soon, planned }

/// A feature awaiting rollout: a new plan or a temporarily paused module.
/// Compiled add-ons use [NexModulePlan.forModule] so pausing their availability
/// changes only the catalogue, without deleting source or saved data.
class NexModulePlan {
  const NexModulePlan(this.id, this.icon, this.hue, this.stage)
    : _module = null;

  NexModulePlan.forModule(NexModule module)
    : id = module.id,
      icon = module.icon,
      hue = module.hue,
      stage = NexModuleStage.soon,
      _module = module;

  final NexModule? _module;

  final String id;
  final IconData icon;
  final NexHue hue;
  final NexModuleStage stage;

  String title(AppLocalizations l10n) =>
      _module?.title(l10n) ??
      switch (id) {
        'occasions' => l10n.planOccasionsTitle,
        'security-tools' => l10n.planSecurityToolsTitle,
        'pause' => l10n.planPauseTitle,
        'persian-calendar' => l10n.planPersianCalendarTitle,
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

  String about(AppLocalizations l10n) =>
      _module?.about(l10n) ??
      switch (id) {
        'occasions' => l10n.planOccasionsAbout,
        'security-tools' => l10n.planSecurityToolsAbout,
        'pause' => l10n.planPauseAbout,
        'persian-calendar' => l10n.planPersianCalendarAbout,
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
  NexModulePlan(
    'occasions',
    Icons.cake_outlined,
    NexHue.rose,
    NexModuleStage.soon,
  ),
  NexModulePlan(
    'security-tools',
    Icons.security_outlined,
    NexHue.sky,
    NexModuleStage.soon,
  ),
  NexModulePlan(
    'persian-calendar',
    Icons.calendar_month_outlined,
    NexHue.sky,
    NexModuleStage.soon,
  ),
  NexModulePlan('pause', Icons.air_outlined, NexHue.sky, NexModuleStage.soon),
  NexModulePlan(
    'telegram',
    Icons.send_outlined,
    NexHue.sky,
    NexModuleStage.soon,
  ),
];
