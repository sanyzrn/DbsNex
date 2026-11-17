part of 'words_review_page.dart';

/// The surfaces of the review: the flashcard's front, the typing card, the
/// choices, and the turned card with the answer on it.
extension _ReviewCards on _WordsReviewPageState {
  /// The deck's gradient, shared by every front so a typed card and a
  /// flashcard feel like the same object.
  Widget _gradientCard({required Widget child, Key? key}) => DecoratedBox(
    key: key,
    decoration: BoxDecoration(
      gradient: wordsDeckGradient,
      borderRadius: BorderRadius.circular(NexRadius.xl),
      boxShadow: [
        BoxShadow(
          color: wordsDeckFrom.withValues(alpha: 0.3),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: child,
  );

  Widget _pill(BuildContext context, String text) {
    const white = Colors.white;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(NexRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NexSpacing.sm + 2,
          vertical: NexSpacing.xs,
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: white),
        ),
      ),
    );
  }

  Widget _frontPills(BuildContext context, WordCard card) => Wrap(
    alignment: WrapAlignment.center,
    spacing: NexSpacing.xs,
    runSpacing: NexSpacing.xs,
    children: [
      if (card.language.isNotEmpty) _pill(context, card.language),
      if (card.tag.isNotEmpty) _pill(context, card.tag),
      if (card.isNew) _pill(context, wordsStrings(context, 'statusNew')),
    ],
  );

  /// Concealed: only the word, and the answer is not in the tree at all —
  /// not merely invisible — so nothing can read it early.
  ///
  /// The front of a flashcard (2.4.0): the deck's colours, the word large
  /// in the middle, its language and tag on small pills, and the hint at
  /// the foot.
  Widget _flashcardFront(BuildContext context, WordCard card) {
    final strings = wordsStrings;
    final theme = Theme.of(context);
    const white = Colors.white;
    final meaningFirst = _reverse && card.meaning.isNotEmpty;
    return Semantics(
      label: strings(context, 'tapToReveal'),
      button: true,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: wordsDeckGradient,
            borderRadius: BorderRadius.circular(NexRadius.xl),
            boxShadow: [
              BoxShadow(
                color: wordsDeckFrom.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: InkWell(
            key: const ValueKey('words-review-card'),
            onTap: _reveal,
            borderRadius: BorderRadius.circular(NexRadius.xl),
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.min(constraints.maxHeight, 420),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(NexSpacing.lg),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _frontPills(context, card),
                        const SizedBox(height: NexSpacing.xl),
                        if (meaningFirst)
                          // Meaning first: the word is the answer, so it is
                          // not in the tree until the card is revealed.
                          Center(
                            child: NexTextSurface(
                              card.meaning,
                              key: const ValueKey('words-review-meaning-first'),
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: white,
                              ),
                            ),
                          )
                        else
                          Center(
                            child: NexTextDirection(
                              text: card.headword,
                              child: Text(
                                card.headword,
                                key: const ValueKey('words-review-headword'),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.displaySmall?.copyWith(
                                  color: white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: NexSpacing.xl),
                        // Said once, by the card's own label.
                        ExcludeSemantics(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.touch_app_outlined,
                                size: 18,
                                color: white.withValues(alpha: 0.8),
                              ),
                              const SizedBox(width: NexSpacing.xs),
                              Flexible(
                                child: Text(
                                  strings(context, 'tapToReveal'),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: white.withValues(alpha: 0.8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The prompt, on the deck's colours, for a card that is typed or
  /// chosen: the word (or the meaning) and nothing of the answer.
  Widget _revealedCard(BuildContext context, WordCard card) {
    final theme = Theme.of(context);
    final strings = wordsStrings;
    final showVerdict =
        _exercise != WordsExercise.flashcard || _checked || _chosen != null;
    return Semantics(
      label: strings(context, 'revealedSemantics'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(NexRadius.xl),
          border: Border.all(
            color: wordsDeckTo.withValues(alpha: 0.45),
            width: 1.5,
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(NexSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showVerdict && card.meaning.isNotEmpty) ...[
                Text(
                  strings(context, _wasRight ? 'answerRight' : 'answerWrong'),
                  key: const ValueKey('words-answer-verdict'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: _wasRight
                        ? wordsGradeColor(WordsGrade.good)
                        : theme.colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (!_wasRight && _typed.text.trim().isNotEmpty)
                  Text(
                    strings(context, 'answerYouWrote', {
                      'text': _typed.text.trim(),
                    }),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: NexSpacing.sm),
              ],
              Center(
                child: NexTextDirection(
                  text: card.headword,
                  child: Text(
                    card.headword,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
              ),
              if (card.meaning.isEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: NexSpacing.md),
                  child: Column(
                    children: [
                      Text(
                        strings(context, 'meaningNeeded'),
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        key: const ValueKey('words-review-edit'),
                        onPressed: _answering ? null : _editMeaning,
                        child: Text(strings(context, 'editMeaning')),
                      ),
                    ],
                  ),
                ),
              if (card.meaning.isNotEmpty) ...[
                const SizedBox(height: NexSpacing.md),
                NexTextSurface(
                  card.meaning,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  selectable: true,
                ),
              ],
              if (card.example.isNotEmpty) ...[
                const SizedBox(height: NexSpacing.md),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: wordsDeckTo.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(NexRadius.md),
                    border: BorderDirectional(
                      start: BorderSide(color: wordsDeckTo, width: 3),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(NexSpacing.sm + 2),
                    child: NexTextSurface(
                      card.example,
                      key: const ValueKey('words-review-example'),
                      selectable: true,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ),
              ],
              if (card.note.isNotEmpty) ...[
                const SizedBox(height: NexSpacing.md),
                NexTextSurface(
                  card.note,
                  selectable: true,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: NexSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}

/// The answer's colour, deepened on a light page and lifted on a dark one
/// so its words stay readable on its own tint.
Color wordsGradeColor(WordsGrade grade) => switch (grade) {
  WordsGrade.again => const Color(0xFFEF4444),
  WordsGrade.hard => const Color(0xFFF59E0B),
  WordsGrade.good => const Color(0xFF10B981),
  WordsGrade.easy => const Color(0xFF3B82F6),
};

Color wordsGradeInk(BuildContext context, WordsGrade grade) {
  final base = wordsGradeColor(grade);
  final dark = Theme.of(context).brightness == Brightness.dark;
  return Color.lerp(base, dark ? Colors.white : Colors.black, 0.3)!;
}
