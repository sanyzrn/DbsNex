/// The progress sheet: how many words are learned, how many wait, and how
/// the week went. It counts what the module already stores — the review
/// log — and says nothing about levels, fluency or a streak.
library;

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'words_dates.dart';
import 'words_models.dart';
import 'words_practice.dart';
import 'words_strings.dart';
import 'words_visuals.dart';

Future<void> showWordsProgressSheet(
  BuildContext context, {
  required List<WordCard> cards,
  required WordsSettings settings,
}) => nexShowSheet<void>(
  context: context,
  builder: (_) => _ProgressSheet(cards: cards, settings: settings),
);

class _ProgressSheet extends StatelessWidget {
  const _ProgressSheet({required this.cards, required this.settings});

  final List<WordCard> cards;
  final WordsSettings settings;

  @override
  Widget build(BuildContext context) {
    final strings = wordsStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = DateTime.now();
    final summary = wordsProgressSummary(
      cards,
      todayIso: wordsIsoDay(today),
      today: today,
    );
    final week = wordsWeek(cards, today);
    final persian = NexModuleStrings.persian(context);
    String count(int value) => nexDigits('$value', persian: persian);

    Widget stat(String key, int value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            count(value),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            strings(context, key),
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    return SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(NexSpacing.md),
        children: [
          Text(
            strings(context, 'progressTitle'),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: NexSpacing.md),
          // The goal, said as a fact and not as a debt.
          Text(
            settings.goalPerDay > 0
                ? strings(context, 'goalLine', {
                    'goal': settings.goalPerDay,
                    'done': wordsReviewsOn(cards, wordsIsoDay(today)),
                  })
                : strings(context, 'goalOff'),
            key: const ValueKey('words-progress-goal'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: NexSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              stat('progressLearned', summary.learned),
              stat('progressDue', summary.due),
              stat('progressPaused', summary.paused),
            ],
          ),
          const SizedBox(height: NexSpacing.sm),
          Text(
            strings(context, 'progressTotalLine', {'count': summary.total}),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Divider(height: NexSpacing.xl),
          Text(
            strings(context, 'progressWeek'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: NexSpacing.xs),
          Text(
            summary.reviews == 0
                ? strings(context, 'progressWeekEmpty')
                : strings(context, 'progressWeekLine', {
                    'reviews': summary.reviews,
                    'again': summary.again,
                  }),
            key: const ValueKey('words-progress-week-line'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: NexSpacing.md),
          WordsWeekBars(week: week),
        ],
      ),
    );
  }
}

/// Seven bars, oldest first: how many answers each day holds, with the
/// «again» ones in red at the foot of their bar.
class WordsWeekBars extends StatelessWidget {
  const WordsWeekBars({super.key, required this.week});

  final List<({String iso, int reviews, int again})> week;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = NexModuleStrings.persian(context);
    final tallest = week.fold(
      1,
      (max, day) => day.reviews > max ? day.reviews : max,
    );
    return SizedBox(
      height: 120,
      child: Row(
        key: const ValueKey('words-week-bars'),
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in week) ...[
            Expanded(
              child: Semantics(
                label: wordsStrings(context, 'weekDayTip', {
                  'day': nexModuleDateLabel(context, DateTime.parse(day.iso)),
                  'count': day.reviews,
                }),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: day.reviews == 0
                              ? 0.04
                              : day.reviews / tallest,
                          child: Container(
                            decoration: BoxDecoration(
                              color: day.reviews == 0
                                  ? scheme.surfaceContainerHighest
                                  : wordsStageColor(WordsStage.holding),
                              borderRadius: BorderRadius.circular(NexRadius.xs),
                            ),
                            child: day.again == 0
                                ? null
                                : Align(
                                    alignment: Alignment.bottomCenter,
                                    child: FractionallySizedBox(
                                      heightFactor: day.again / day.reviews,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: scheme.error,
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                bottom: Radius.circular(
                                                  NexRadius.xs,
                                                ),
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: NexSpacing.xs),
                    Text(
                      nexDigits(
                        day.iso.length >= 10 ? day.iso.substring(8) : day.iso,
                        persian: persian,
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (day != week.last) const SizedBox(width: NexSpacing.xs),
          ],
        ],
      ),
    );
  }
}
