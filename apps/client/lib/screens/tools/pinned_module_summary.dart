import 'package:nex_core/nex_core.dart';

import '../../l10n/app_localizations.dart';
import '../../modules/module_registry.dart';
import '../../modules/nex_module_store.dart';
import '../../modules/nex_stored_module.dart';
import '../../platform/nex_preferences.dart';
import '../../platform/nex_services.dart';
import '../pause/pause_patterns.dart';

/// Two local facts for a pinned module, independent of AI and its consent.
class NexPinnedSummary {
  const NexPinnedSummary(this.primary, [this.secondary, this.progress]);
  final String primary;
  final String? secondary;

  /// How far along today is, from 0 to 1, when the module counts toward
  /// something — habits done out of those due, the day of a cycle. Drawn as
  /// a ring round the module's mark on the home screen; null draws none.
  /// Always a real count from the person's own data, never decoration.
  final double? progress;
}

Future<NexPinnedSummary?> nexPinnedModuleSummary({
  required String id,
  required NexServices services,
  required NexPreferences preferences,
  required AppLocalizations l10n,
  DateTime? now,
}) async {
  if (!nexModulesOn(preferences).any((module) => module.id == id)) return null;
  final at = now ?? DateTime.now();
  final store = NexModuleStore(services, id);
  // The module's own words first (2.8.5); the cases below are for the ones
  // that have not said them yet, and for Pause and Cycle, which are not
  // folder modules.
  if (nexModulesById[id] case final NexStoredModule module) {
    if (await module.glance(store, l10n, at) case final glance?) {
      return NexPinnedSummary(glance.headline, glance.detail, glance.progress);
    }
  }
  switch (id) {
    case 'pause':
      final mode = PauseMode.fromId(preferences.pauseMode);
      final length = PauseLength.fromId(preferences.pauseLength);
      final seconds = length.durationOf(mode).inSeconds;
      final time = nexDigits(
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
        persian: l10n.localeName == 'fa',
      );
      return NexPinnedSummary(l10n.pinPauseDuration(time), switch (mode) {
        PauseMode.calm => l10n.pauseModeCalm,
        PauseMode.focus => l10n.pauseModeFocus,
        PauseMode.relax => l10n.pauseModeRelax,
      });
    case 'cycle':
      if (!preferences.cycleSetUp) return NexPinnedSummary(l10n.pinCycleSetup);
      final periods = await services.cyclePeriods();
      String digits(int n) => nexDigits('$n', persian: l10n.localeName == 'fa');
      final mode = preferences.cycleMode;
      if (mode == CycleMode.pregnant) {
        final start =
            preferences.cyclePregnancyStart ?? periods.lastOrNull?.start;
        if (start == null) return NexPinnedSummary(l10n.pinCycleLog);
        final pregnancy = CyclePregnancy(
          lastPeriod: start,
          today: CycleDate.of(at),
        );
        return NexPinnedSummary(
          l10n.cyclePregnancyWeek(
            digits(pregnancy.weeks),
            digits(pregnancy.days),
          ),
          l10n.cycleModePregnant,
        );
      }
      if (!mode.predicts) {
        return NexPinnedSummary(l10n.pinCycleLog, switch (mode) {
          CycleMode.breastfeeding => l10n.cycleModeBreastfeeding,
          _ => l10n.cycleModeMenopause,
        });
      }
      final prediction = CyclePredictor.predict(
        periods: periods,
        today: CycleDate.of(at),
        typicalCycle: preferences.cycleTypicalLength,
        typicalPeriod: preferences.cycleTypicalPeriod,
      );
      if (prediction == null) return NexPinnedSummary(l10n.pinCycleLog);
      // The day of the cycle out of the days this cycle is expected to run:
      // the days behind plus the days still ahead.
      final length = prediction.cycleDay + prediction.daysUntilNext;
      return NexPinnedSummary(
        prediction.inPeriod
            ? l10n.cycleDayOfPeriod(digits(prediction.cycleDay))
            : l10n.cycleDayOfCycle(digits(prediction.cycleDay)),
        prediction.daysUntilNext < 0
            ? l10n.cycleLate(-prediction.daysUntilNext)
            : l10n.cycleDaysUntil(prediction.daysUntilNext),
        length > 0 ? (prediction.cycleDay / length).clamp(0.0, 1.0) : 1.0,
      );
    default:
      return NexPinnedSummary(l10n.pinModuleUnavailable);
  }
}
