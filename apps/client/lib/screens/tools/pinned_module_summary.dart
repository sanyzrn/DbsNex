import 'package:nex_core/nex_core.dart';

import '../../l10n/app_localizations.dart';
import '../../modules/module_registry.dart';
import '../../modules/nex_module_store.dart';
import '../../modules/habits/habit_math.dart';
import '../../modules/habits/habit_model.dart';
import '../../modules/habits/week_settings.dart';
import '../../modules/occasions/occasion_math.dart' as occasions;
import '../../modules/occasions/occasion_model.dart';
import '../../modules/words/words_dates.dart';
import '../../modules/words/words_models.dart';
import '../../modules/words/words_scheduler.dart' as words;
import '../../platform/nex_preferences.dart';
import '../../platform/nex_services.dart';
import '../pause/pause_patterns.dart';

/// Two local facts for a pinned module, independent of AI and its consent.
class NexPinnedSummary {
  const NexPinnedSummary(this.primary, [this.secondary]);
  final String primary;
  final String? secondary;
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
  switch (id) {
    case 'habits':
      final habits = (await store.list(
        'habit',
      )).map(Habit.fromRecord).where((h) => !h.archived).toList();
      if (habits.isEmpty) return NexPinnedSummary(l10n.pinHabitsEmpty);
      final checks = (await store.list(
        'check',
      )).map(HabitCheck.fromRecord).toList();
      final firstDay = readFirstDay(await store.get('settings', 'week'));
      var done = 0, left = 0;
      for (final habit in habits) {
        final s = HabitMath.fromChecks(
          habit,
          checks.where((check) => check.habitId == habit.id),
          at,
          firstDay: firstDay,
        );
        if (s.todayDone) {
          done++;
        } else if (s.dueToday &&
            !(habit.weekly && s.weekCount >= habit.target)) {
          left++;
        }
      }
      if (done + left == 0) return NexPinnedSummary(l10n.pinHabitsRest);
      return NexPinnedSummary(
        l10n.pinHabitsProgress(done, done + left),
        left == 0 ? l10n.pinHabitsRest : l10n.pinHabitsLeft(left),
      );
    case 'words':
      final cards = (await store.list(
        'card',
      )).map((r) => WordCard.fromRecord(r.id, r.body)).toList();
      if (cards.isEmpty) return NexPinnedSummary(l10n.pinWordsEmpty);
      final settings = WordsSettings.fromRecord(
        await store.get('settings', WordsSettings.recordId) ?? const {},
      );
      final session = words.buildSession(
        cards: cards,
        todayIso: wordsIsoDay(at),
        newPerDay: settings.newPerDay,
        sessionLimit: 0,
      );
      return NexPinnedSummary(
        l10n.pinWordsDue(session.due.length),
        l10n.pinWordsNew(session.fresh.length),
      );
    case 'occasions':
      final upcoming = <({Occasion item, DateTime date})>[];
      for (final record in await store.list('occasion')) {
        final item = Occasion.fromRecord(record);
        if (item.archived || item.title.isEmpty) continue;
        final next = occasions.nextOccasionDay(item, at);
        if (next != null) upcoming.add((item: item, date: next.date));
      }
      upcoming.sort((a, b) {
        final date = a.date.compareTo(b.date);
        return date != 0 ? date : a.item.id.compareTo(b.item.id);
      });
      if (upcoming.isEmpty) return NexPinnedSummary(l10n.pinOccasionsEmpty);
      final next = upcoming.first;
      final days = occasions.daysUntil(at, next.date);
      return NexPinnedSummary(
        next.item.title,
        days == 0 ? l10n.cycleDayToday : l10n.pinOccasionInDays(days),
      );
    case 'pause':
      final mode = PauseMode.fromId(preferences.pauseMode);
      final seconds = mode.sessionDuration.inSeconds;
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
      return NexPinnedSummary(
        prediction.inPeriod
            ? l10n.cycleDayOfPeriod(digits(prediction.cycleDay))
            : l10n.cycleDayOfCycle(digits(prediction.cycleDay)),
        prediction.daysUntilNext < 0
            ? l10n.cycleLate(-prediction.daysUntilNext)
            : l10n.cycleDaysUntil(prediction.daysUntilNext),
      );
    default:
      return NexPinnedSummary(l10n.pinModuleUnavailable);
  }
}
