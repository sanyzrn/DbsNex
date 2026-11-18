/// The look of Word by Word (2.4.0): the deck card at the top of the home
/// page with its ladder of how well the words are known, the strength
/// meter on each row, and the language badge.
library;

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'words_models.dart';
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

/// The card at the top of the home page: how many words wait, the ladder
/// of how well they are known, today's small goal, and the way in.
///
/// There is no streak here on purpose: a missed day costs nothing, and a
/// row of days would say otherwise (2.8.4).
class WordsDeckCard extends StatelessWidget {
  const WordsDeckCard({
    super.key,
    required this.cards,
    required this.headline,
    required this.caption,
    required this.action,
    required this.settings,
    this.goal = 0,
    this.reviewedToday = 0,
  });

  final List<WordCard> cards;
  final String headline;
  final String caption;

  /// The daily goal in answers, and how many were already given today.
  /// Zero means the person chose no goal, and nothing is shown.
  final int goal;
  final int reviewedToday;

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
    final goalMet = goal > 0 && reviewedToday >= goal;
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
                      if (goal > 0) ...[
                        const SizedBox(width: NexSpacing.sm),
                        Flexible(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(
                                NexRadius.pill,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: NexSpacing.sm,
                                vertical: 2,
                              ),
                              child: Text(
                                // Said as a fact, never as a debt: what is
                                // done today, and what was asked for.
                                strings(
                                  context,
                                  goalMet ? 'goalMet' : 'goalToday',
                                  {'done': reviewedToday, 'goal': goal},
                                ),
                                key: const ValueKey('words-goal'),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: white,
                                  fontWeight: FontWeight.w600,
                                ),
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
