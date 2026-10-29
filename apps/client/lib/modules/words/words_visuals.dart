/// The look of Word by Word (2.4.0): the deck card at the top of the home
/// page with its ladder of how well the words are known, the strength
/// meter on each row, and the language badge.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'words_models.dart';
import 'words_scheduler.dart';
import 'words_strings.dart';

/// The deck's colours: ink to violet.
const wordsDeckFrom = Color(0xFF4338CA);
const wordsDeckTo = Color(0xFF8B5CF6);

const wordsDeckGradient = LinearGradient(
  begin: AlignmentDirectional.topStart,
  end: AlignmentDirectional.bottomEnd,
  colors: [wordsDeckFrom, wordsDeckTo],
);

/// Where a word stands, in four plain steps: not yet seen, being learned
/// (the first three rungs of the ladder), holding (the next two), learned.
enum WordsStage { fresh, learning, holding, learned }

WordsStage wordsStageOf(WordCard card) => card.isNew
    ? WordsStage.fresh
    : card.step >= 5
    ? WordsStage.learned
    : card.step >= 3
    ? WordsStage.holding
    : WordsStage.learning;

Color wordsStageColor(WordsStage stage) => switch (stage) {
  WordsStage.fresh => const Color(0xFFC4B5FD),
  WordsStage.learning => const Color(0xFFFBBF24),
  WordsStage.holding => const Color(0xFF34D399),
  WordsStage.learned => const Color(0xFF22D3EE),
};

/// Days in a row, ending today or yesterday, with at least one answer.
int wordsStreak(Iterable<WordCard> cards, DateTime today) {
  final days = <String>{
    for (final card in cards)
      for (final entry in card.log)
        if (entry.at.length >= 10) entry.at.substring(0, 10),
  };
  String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  var day = DateTime(today.year, today.month, today.day);
  if (!days.contains(iso(day))) {
    day = DateTime(day.year, day.month, day.day - 1);
    if (!days.contains(iso(day))) return 0;
  }
  var streak = 0;
  while (days.contains(iso(day))) {
    streak++;
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return streak;
}

/// The card at the top of the home page: how many words wait, the ladder
/// of how well they are known, the streak, and the way in.
class WordsDeckCard extends StatelessWidget {
  const WordsDeckCard({
    super.key,
    required this.cards,
    required this.headline,
    required this.caption,
    required this.action,
    required this.settings,
  });

  final List<WordCard> cards;
  final String headline;
  final String caption;

  /// Start review, or the line saying there is nothing to review.
  final Widget action;

  /// The review settings toggle.
  final Widget settings;

  @override
  Widget build(BuildContext context) {
    final strings = wordsStrings;
    final theme = Theme.of(context);
    const white = Colors.white;
    final active = cards.where((c) => !c.paused).toList();
    final counts = {
      for (final stage in WordsStage.values)
        stage: active.where((c) => wordsStageOf(c) == stage).length,
    };
    final streak = wordsStreak(cards, DateTime.now());
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: wordsDeckGradient,
        borderRadius: BorderRadius.circular(NexRadius.xl),
        boxShadow: [
          BoxShadow(
            color: wordsDeckFrom.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NexRadius.xl),
        child: Stack(
          children: [
            const PositionedDirectional(end: -12, top: -8, child: _CardStack()),
            Padding(
              padding: const EdgeInsets.all(NexSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        strings(context, 'collection'),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: white.withValues(alpha: 0.9),
                        ),
                      ),
                      if (streak >= 2) ...[
                        const SizedBox(width: NexSpacing.sm),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(NexRadius.pill),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: NexSpacing.sm,
                              vertical: 2,
                            ),
                            child: Text(
                              strings(context, 'streak', {'count': streak}),
                              key: const ValueKey('words-streak'),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: NexSpacing.xs),
                  Text(
                    headline,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    caption,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: white.withValues(alpha: 0.88),
                    ),
                  ),
                  const SizedBox(height: NexSpacing.md),
                  _Ladder(counts: counts),
                  const SizedBox(height: NexSpacing.md),
                  action,
                  settings,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How the words are spread over the four steps: one bar, in proportion,
/// with the counts under it.
class _Ladder extends StatelessWidget {
  const _Ladder({required this.counts});

  final Map<WordsStage, int> counts;

  @override
  Widget build(BuildContext context) {
    final strings = wordsStrings;
    final theme = Theme.of(context);
    final total = counts.values.fold(0, (a, b) => a + b);
    String label(WordsStage stage) => strings(
      context,
      switch (stage) {
        WordsStage.fresh => 'stageNew',
        WordsStage.learning => 'stageLearning',
        WordsStage.holding => 'stageHolding',
        WordsStage.learned => 'stageLearned',
      },
      {'count': counts[stage] ?? 0},
    );
    return Column(
      key: const ValueKey('words-ladder'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(NexRadius.pill),
          child: SizedBox(
            height: 8,
            child: total == 0
                ? ColoredBox(color: Colors.white.withValues(alpha: 0.2))
                : Row(
                    children: [
                      for (final stage in WordsStage.values)
                        if ((counts[stage] ?? 0) > 0)
                          Expanded(
                            flex: counts[stage]!,
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(end: 2),
                              child: ColoredBox(color: wordsStageColor(stage)),
                            ),
                          ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: NexSpacing.sm),
        Wrap(
          spacing: NexSpacing.md,
          runSpacing: NexSpacing.xs,
          children: [
            for (final stage in WordsStage.values)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: wordsStageColor(stage),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: NexSpacing.xs),
                  Text(
                    label(stage),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// Three flashcards fanned out in the corner of the deck card.
class _CardStack extends StatelessWidget {
  const _CardStack();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: SizedBox(
      width: 120,
      height: 110,
      child: Stack(
        children: [
          for (final (angle, dx, alpha) in [
            (-0.32, 0.0, 0.10),
            (-0.14, 18.0, 0.14),
            (0.06, 36.0, 0.20),
          ])
            Positioned(
              left: dx,
              top: 18,
              child: Transform.rotate(
                angle: angle,
                child: Container(
                  width: 62,
                  height: 82,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: alpha),
                    borderRadius: BorderRadius.circular(NexRadius.md),
                  ),
                  alignment: Alignment.center,
                  // Letters on the front card only; on all three they read
                  // as a smudge.
                  child: alpha < 0.2
                      ? null
                      : Text(
                          'Aa',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Five short bars, filled to how far up the ladder a word is; an outline
/// for a new one.
class WordsStrength extends StatelessWidget {
  const WordsStrength({super.key, required this.card});

  final WordCard card;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stage = wordsStageOf(card);
    final filled = card.isNew ? 0 : math.min(5, card.step + 1);
    final color = card.paused
        ? scheme.outline
        : stage == WordsStage.fresh
        ? scheme.primary
        : wordsStageColor(stage);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 5; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Container(
            width: 4,
            height: 6.0 + i * 2.5,
            decoration: BoxDecoration(
              color: i < filled ? color : null,
              border: i < filled
                  ? null
                  : Border.all(color: scheme.outline.withValues(alpha: 0.6)),
              borderRadius: BorderRadius.circular(NexRadius.xs),
            ),
          ),
        ],
      ],
    );
  }
}

/// Two letters for a language — «EN», «FR», «فا» — on a colour of its own,
/// the same colour for the same language everywhere.
class WordsLanguageBadge extends StatelessWidget {
  const WordsLanguageBadge({super.key, required this.language});

  final String language;

  static const _hues = [
    Color(0xFF6366F1),
    Color(0xFF0EA5E9),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
  ];

  @override
  Widget build(BuildContext context) {
    final trimmed = language.trim();
    final letters = trimmed.isEmpty
        ? '·'
        : trimmed.characters.take(2).toString().toUpperCase();
    final hue = trimmed.isEmpty
        ? Theme.of(context).colorScheme.outline
        : _hues[trimmed.toLowerCase().codeUnits.fold(0, (a, b) => a + b) %
              _hues.length];
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hue.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(NexRadius.md),
      ),
      child: Text(
        letters,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: hue,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The ladder a word climbs — 1, 3, 7, 14, 30 and 60 days — with the rung it
/// stands on lit and the ones below it filled.
class WordsRungs extends StatelessWidget {
  const WordsRungs({super.key, required this.card});

  final WordCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = NexModuleStrings.persian(context);
    final at = card.isNew ? -1 : card.step.clamp(0, wordsLadder.length - 1);
    final color = wordsStageColor(wordsStageOf(card));
    return Row(
      key: const ValueKey('words-card-rungs'),
      children: [
        for (var i = 0; i < wordsLadder.length; i++) ...[
          if (i > 0) const SizedBox(width: NexSpacing.xs),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: i <= at ? color : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(NexRadius.pill),
                    border: i == at
                        ? Border.all(color: scheme.onSurface, width: 1.2)
                        : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  nexDigits('${wordsLadder[i]}', persian: persian),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: i == at ? scheme.onSurface : scheme.onSurfaceVariant,
                    fontWeight: i == at ? FontWeight.w700 : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
