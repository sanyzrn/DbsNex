part of 'words_review_page.dart';

class _ReviewBody extends StatelessWidget {
  const _ReviewBody({
    required this.card,
    required this.reverse,
    required this.revealed,
    required this.answering,
    required this.index,
    required this.total,
    required this.onReveal,
    required this.onAnswer,
    required this.onEdit,
    required this.onSkip,
  });

  final WordCard card;
  final bool reverse;
  final bool revealed;
  final bool answering;
  final int index;
  final int total;
  final VoidCallback onReveal;
  final void Function(WordsGrade grade) onAnswer;
  final VoidCallback onEdit;
  final VoidCallback onSkip;

  /// Which side of which card is up, for the turn between them.
  String get _side => '${card.id}:$revealed';

  @override
  Widget build(BuildContext context) {
    final strings = wordsStrings;
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NexSpacing.md,
            NexSpacing.sm,
            NexSpacing.md,
            0,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(NexRadius.pill),
            child: LinearProgressIndicator(
              key: const ValueKey('words-review-progress-bar'),
              minHeight: 6,
              value: total == 0 ? 0 : (index + (revealed ? 0.5 : 0)) / total,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(NexSpacing.sm),
          child: Text(
            strings(context, 'progressOf', {'n': index + 1, 'total': total}),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
            // The card turns over (2.4.0): a quarter turn out, a quarter
            // turn in, with the other side coming up. Reduced motion swaps
            // the sides at once.
            child: AnimatedSwitcher(
              duration: NexMotion.of(context, NexMotion.standard),
              transitionBuilder: (child, animation) {
                final incoming = child.key == ValueKey(_side);
                return AnimatedBuilder(
                  animation: animation,
                  child: child,
                  builder: (context, child) {
                    final t = animation.value;
                    // Each side shows only for its half of the turn.
                    if (t < 0.5) return const SizedBox.shrink();
                    final angle = (1 - t) * math.pi;
                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0012)
                        ..rotateY(incoming ? -angle : angle),
                      child: child,
                    );
                  },
                );
              },
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.center,
                children: [...previous, ?current],
              ),
              child: KeyedSubtree(
                key: ValueKey(_side),
                child: revealed
                    ? _revealedCard(context)
                    : _concealedCard(context),
              ),
            ),
          ),
        ),
        if (revealed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
            child: _answerRow(context),
          ),
        TextButton(
          key: const ValueKey('words-review-skip'),
          onPressed: answering ? null : onSkip,
          child: Text(strings(context, 'skipForNow')),
        ),
        const SizedBox(height: NexSpacing.md),
      ],
    );
  }

  /// Concealed: only the headword, and the answer is not in the tree at
  /// all — not merely invisible — so nothing can read it early.
  ///
  /// The front of a flashcard (2.4.0): the deck's colours, the word large
  /// in the middle, its language and tag on small pills, and the hint at
  /// the foot.
  Widget _concealedCard(BuildContext context) {
    final strings = wordsStrings;
    final theme = Theme.of(context);
    const white = Colors.white;
    Widget pill(String text) => DecoratedBox(
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
          style: theme.textTheme.labelMedium?.copyWith(color: white),
        ),
      ),
    );
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
            onTap: onReveal,
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
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: NexSpacing.xs,
                          runSpacing: NexSpacing.xs,
                          children: [
                            if (card.language.isNotEmpty) pill(card.language),
                            if (card.tag.isNotEmpty) pill(card.tag),
                            if (card.isNew) pill(strings(context, 'statusNew')),
                          ],
                        ),
                        const SizedBox(height: NexSpacing.xl),
                        if (reverse && card.meaning.isNotEmpty)
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

  Widget _revealedCard(BuildContext context) {
    final theme = Theme.of(context);
    // The back of the card: the word again, smaller, and the answer under
    // it on the page's own surface.
    return Semantics(
      label: wordsStrings(context, 'revealedSemantics'),
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
                        wordsStrings(context, 'meaningNeeded'),
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        key: const ValueKey('words-review-edit'),
                        onPressed: answering ? null : onEdit,
                        child: Text(wordsStrings(context, 'editMeaning')),
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

  Widget _answerRow(BuildContext context) {
    final strings = wordsStrings;
    String when(int days) => days <= 1
        ? strings(context, 'dueTomorrow')
        : strings(context, 'dueInDays', {'count': days});
    final answers = [
      (WordsGrade.again, 'again', const ValueKey('words-answer-again')),
      (WordsGrade.hard, 'hard', const ValueKey('words-answer-hard')),
      (WordsGrade.good, 'good', const ValueKey('words-answer-good')),
      (WordsGrade.easy, 'easy', const ValueKey('words-answer-easy')),
    ];
    Widget button((WordsGrade, String, ValueKey<String>) entry) {
      final label = strings(context, entry.$2);
      final interval = when(previewIntervalDays(card, entry.$1));
      return Expanded(
        child: Semantics(
          label: '$label · $interval',
          button: true,
          child: FilledButton.tonal(
            key: entry.$3,
            // Each answer its colour (2.4.0): again red, hard amber, good
            // green, easy blue — read at a glance, as on paper cards.
            style: FilledButton.styleFrom(
              backgroundColor: _gradeColor(entry.$1).withValues(alpha: 0.16),
              foregroundColor: _gradeInk(context, entry.$1),
              padding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
            ),
            onPressed: answering || card.meaning.isEmpty
                ? null
                : () => onAnswer(entry.$1),
            child: ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, textAlign: TextAlign.center),
                  Builder(
                    builder: (buttonContext) => Text(
                      interval,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: DefaultTextStyle.of(buttonContext).style.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            button(answers[0]),
            const SizedBox(width: NexSpacing.sm),
            button(answers[1]),
          ],
        ),
        const SizedBox(height: NexSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            button(answers[2]),
            const SizedBox(width: NexSpacing.sm),
            button(answers[3]),
          ],
        ),
      ],
    );
  }

  static Color _gradeColor(WordsGrade grade) => switch (grade) {
    WordsGrade.again => const Color(0xFFEF4444),
    WordsGrade.hard => const Color(0xFFF59E0B),
    WordsGrade.good => const Color(0xFF10B981),
    WordsGrade.easy => const Color(0xFF3B82F6),
  };

  /// The answer's colour, deepened on a light page and lifted on a dark one
  /// so its words stay readable on its own tint.
  static Color _gradeInk(BuildContext context, WordsGrade grade) {
    final base = _gradeColor(grade);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Color.lerp(base, dark ? Colors.white : Colors.black, 0.3)!;
  }
}
