part of 'words_review_page.dart';

class _ReviewBody extends StatelessWidget {
  const _ReviewBody({
    required this.card,
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
  final bool revealed;
  final bool answering;
  final int index;
  final int total;
  final VoidCallback onReveal;
  final void Function(WordsGrade grade) onAnswer;
  final VoidCallback onEdit;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final strings = wordsStrings;
    final theme = Theme.of(context);
    return Column(
      children: [
        LinearProgressIndicator(
          key: const ValueKey('words-review-progress-bar'),
          value: total == 0 ? 0 : (index + (revealed ? 0.5 : 0)) / total,
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
            child: revealed ? _revealedCard(context) : _concealedCard(context),
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
  Widget _concealedCard(BuildContext context) {
    final strings = wordsStrings;
    final theme = Theme.of(context);
    return Semantics(
      label: strings(context, 'tapToReveal'),
      button: true,
      child: InkWell(
        key: const ValueKey('words-review-card'),
        onTap: onReveal,
        borderRadius: BorderRadius.circular(NexRadius.lg),
        child: SingleChildScrollView(
          child: NexPanel(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: NexSpacing.xl),
                Center(
                  child: NexTextDirection(
                    text: card.headword,
                    child: Text(
                      card.headword,
                      key: const ValueKey('words-review-headword'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall,
                    ),
                  ),
                ),
                const SizedBox(height: NexSpacing.md),
                Center(
                  child: Text(
                    [
                      if (card.language.isNotEmpty) card.language,
                      if (card.tag.isNotEmpty) card.tag,
                      if (card.isNew) strings(context, 'statusNew'),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: NexSpacing.xl),
                Center(
                  child: Icon(
                    Icons.touch_app_outlined,
                    size: 24,
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: NexSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _revealedCard(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: wordsStrings(context, 'revealedSemantics'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: NexSpacing.md),
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
              NexTextSurface(card.example, selectable: true),
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
            const SizedBox(height: NexSpacing.xl),
          ],
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
}
