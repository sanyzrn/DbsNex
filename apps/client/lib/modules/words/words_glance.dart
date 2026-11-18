import 'package:nex_client/modules/module_api.dart';

import 'words_dates.dart';
import 'words_models.dart';
import 'words_practice.dart';
import 'words_scheduler.dart' as scheduler;
import 'words_strings.dart';

/// The pinned tile and quick view of Word by Word (2.8.5): what waits for
/// review today on the tile; the collection and today's goal in the quick
/// view.
Future<ModuleGlance?> wordsGlance(
  NexModuleStore store,
  AppLocalizations l10n,
  DateTime now,
) async {
  String t(String key, [Map<String, Object?> args = const {}]) =>
      wordsStrings.text(l10n, key, args);
  final cards = (await store.list('card'))
      .map((r) => WordCard.fromRecord(r.id, r.body))
      .toList();
  if (cards.isEmpty) return ModuleGlance(headline: l10n.pinWordsEmpty);
  final settings = WordsSettings.fromRecord(
    await store.get('settings', WordsSettings.recordId) ?? const {},
  );
  final today = wordsIsoDay(now);
  final session = scheduler.buildSession(
    cards: cards,
    todayIso: today,
    newPerDay: settings.newPerDay,
    sessionLimit: 0,
  );
  final progress = wordsProgressSummary(cards, todayIso: today, today: now);
  final answered = wordsReviewsOn(cards, today);
  final goal = settings.goalPerDay;
  String n(int value) =>
      nexDigits('$value', persian: l10n.localeName.startsWith('fa'));
  return ModuleGlance(
    headline: l10n.pinWordsDue(session.due.length),
    detail: l10n.pinWordsNew(session.fresh.length),
    progress: goal > 0 ? (answered / goal).clamp(0.0, 1.0) : null,
    facts: [
      if (goal > 0)
        ModuleGlanceFact(
          t('glanceGoal'),
          t('goalToday', {'done': answered, 'goal': goal}),
          strong: true,
        ),
      ModuleGlanceFact(t('glanceTotal'), n(progress.total)),
      ModuleGlanceFact(t('progressLearned'), n(progress.learned)),
      ModuleGlanceFact(t('glanceWeek'), n(progress.reviews)),
    ],
  );
}
