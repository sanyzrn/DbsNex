import 'package:nex_client/modules/module_api.dart';

import 'module.dart';
import 'money_format.dart';
import 'quit_habits.dart';
import 'quit_model.dart';
import 'smoke_math.dart';

/// The pinned tile and quick view of Quit Habits (2.8.5): the longest
/// running count on the tile; each habit's days and what was kept in the
/// quick view.
Future<ModuleGlance?> quitGlance(
  NexModuleStore store,
  AppLocalizations l10n,
  DateTime now,
) async {
  String t(String key, [Map<String, Object?> args = const {}]) =>
      smokeFreeStrings.text(l10n, key, args);
  final attempts = (await store.list('quit')).map(QuitAttempt.fromRecord);
  final running =
      quitHabitsOf(attempts.toList())
          .where((a) => a.isActive && !a.startedAt.isAfter(now))
          .toList()
        ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  if (running.isEmpty) return ModuleGlance(headline: t('glanceEmpty'));
  String label(QuitAttempt a) => a.habit == 'custom' && a.name.isNotEmpty
      ? a.name
      : t('habit_${quitPresetOf(a.habit).key}');
  final first = running.first;
  final progress = SmokeMath.progress(first, now);
  final persian = l10n.localeName.startsWith('fa');
  return ModuleGlance(
    headline: t('glanceDays', {'n': progress.days}),
    detail: label(first),
    facts: [
      for (final a in running)
        ModuleGlanceFact(
          label(a),
          t('glanceDays', {'n': SmokeMath.progress(a, now).days}),
          strong: identical(a, first),
        ),
      // The amount is in this attempt's own currency, in its own minor
      // units — never a rial amount reinterpreted as another currency. It is
      // the same formatter the dashboard uses, so the quick view and the
      // page cannot disagree.
      if (first.pricePerPackMinor > 0 && progress.moneySavedMinor > BigInt.zero)
        ModuleGlanceFact(
          t('glanceSaved'),
          formatExactMoney(
            progress.moneySavedMinor,
            first.currency,
            first.digits,
            persian,
          ),
        ),
    ],
  );
}
