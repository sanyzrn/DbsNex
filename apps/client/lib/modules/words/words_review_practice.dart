part of 'words_review_page.dart';

/// The practice fronts: the prompt on the deck'''s colours, the typing
/// field, and the choices drawn from the same deck.
extension _ReviewPractice on _WordsReviewPageState {
  Widget _promptHeader(BuildContext context, WordCard card) {
    final theme = Theme.of(context);
    const white = Colors.white;
    final prompt = wordsPromptOf(card, reverse: _reverse);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _frontPills(context, card),
        const SizedBox(height: NexSpacing.md),
        Center(
          child: NexTextSurface(
            prompt,
            key: const ValueKey('words-practice-prompt'),
            style: theme.textTheme.headlineSmall?.copyWith(
              color: white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: NexSpacing.xs),
        Text(
          wordsStrings(context, _reverse ? 'askForWord' : 'askForMeaning'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: white.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: NexSpacing.md),
      ],
    );
  }

  Widget _typingFront(BuildContext context, WordCard card) {
    final strings = wordsStrings;
    final theme = Theme.of(context);
    return _gradientCard(
      key: const ValueKey('words-typing-card'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(NexSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _promptHeader(context, card),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(NexRadius.md),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: NexSpacing.sm),
                child: NexAutoDirection(
                  controller: _typed,
                  builder: (context, direction) => TextField(
                    key: const ValueKey('words-typed-answer'),
                    controller: _typed,
                    focusNode: _typedFocus,
                    textDirection: direction,
                    autofocus: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _checkTyped(card),
                    decoration: InputDecoration(
                      labelText: strings(context, 'answerLabel'),
                      border: InputBorder.none,
                      counterText: '',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: NexSpacing.sm),
            FilledButton.icon(
              key: const ValueKey('words-typed-check'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: wordsDeckFrom,
              ),
              onPressed: _answering ? null : () => _checkTyped(card),
              icon: const Icon(Icons.check),
              label: Text(strings(context, 'checkAnswer')),
            ),
            const SizedBox(height: NexSpacing.xs),
            Text(
              strings(context, 'forgivingHint'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choiceFront(
    BuildContext context,
    WordCard card,
    List<String> choices,
  ) {
    final theme = Theme.of(context);
    return _gradientCard(
      key: const ValueKey('words-choice-card'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(NexSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _promptHeader(context, card),
            for (var i = 0; i < choices.length; i++) ...[
              if (i > 0) const SizedBox(height: NexSpacing.sm),
              Material(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(NexRadius.md),
                child: InkWell(
                  key: ValueKey('words-choice-$i'),
                  borderRadius: BorderRadius.circular(NexRadius.md),
                  onTap: _answering ? null : () => _choose(card, choices[i]),
                  child: Padding(
                    padding: const EdgeInsets.all(NexSpacing.sm + 4),
                    child: NexTextSurface(choices[i]),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The turned card: the word again, the answer under it, the example,
  /// the note — and, for a typed or chosen card, whether it matched.
}
