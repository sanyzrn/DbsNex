part of 'words_review_page.dart';

/// The session on screen: what is left, how the card is asked, the card
/// itself, and — once it is turned — the four answers.
extension _ReviewLayout on _WordsReviewPageState {
  Widget _reviewBody(BuildContext context) {
    final card = _current!;
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
              value: _total == 0
                  ? 0
                  : (_index + (_revealed ? 0.5 : 0)) / _total,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: NexSpacing.md,
            end: NexSpacing.xs,
          ),
          // One row, always: how far into the session, and how the cards
          // are being asked. A row of segments grew into three rows at
          // twice the text size on a small phone, which pushed the four
          // answers off the screen.
          child: Row(
            children: [
              Flexible(
                child: Text(
                  strings(context, 'progressOf', {
                    'n': _index + 1,
                    'total': _total,
                  }),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: NexSpacing.sm),
              // Flexible, with the word ellipsised: at twice the text size
              // a long mode name would otherwise push the row past the page.
              Flexible(
                child: TextButton.icon(
                  key: const ValueKey('words-exercise'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: NexSpacing.sm,
                    ),
                  ),
                  onPressed: _answering
                      ? null
                      : () => unawaited(_pickExercise()),
                  icon: Icon(_exerciseIcon(_exercise), size: 18),
                  label: Text(
                    strings(context, _exerciseLabelKey(_exercise)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
            // The card turns over while it is a flashcard; a typed or
            // chosen card fades, because a flip after typing reads as a
            // page being taken away. Reduced motion swaps at once.
            child: AnimatedSwitcher(
              duration: NexMotion.of(context, NexMotion.standard),
              transitionBuilder: (child, animation) =>
                  _exercise == WordsExercise.flashcard &&
                      !MediaQuery.disableAnimationsOf(context)
                  ? _turn(child, animation)
                  : FadeTransition(opacity: animation, child: child),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.center,
                children: [...previous, ?current],
              ),
              child: KeyedSubtree(
                key: ValueKey(_faceKey(card)),
                child: _cardFace(card),
              ),
            ),
          ),
        ),
        if (_revealed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
            child: _answerRow(context, card),
          ),
        TextButton(
          key: const ValueKey('words-review-skip'),
          onPressed: _answering ? null : _skip,
          child: Text(strings(context, 'skipForNow')),
        ),
        const SizedBox(height: NexSpacing.md),
      ],
    );
  }

  /// Which side of which card is up, and in which exercise.
  String _faceKey(WordCard card) =>
      '${card.id}:${_exercise.name}:$_revealed:$_reverse';

  static IconData _exerciseIcon(WordsExercise exercise) => switch (exercise) {
    WordsExercise.flashcard => Icons.style_outlined,
    WordsExercise.type => Icons.keyboard_outlined,
    WordsExercise.choose => Icons.checklist_rounded,
  };

  static String _exerciseLabelKey(WordsExercise exercise) => switch (exercise) {
    WordsExercise.flashcard => 'modeFlashcard',
    WordsExercise.type => 'modeType',
    WordsExercise.choose => 'modeChoose',
  };

  /// Choosing how the cards are asked, in the app's own sheet. Nothing
  /// typed is lost: the session lives in this page, not in the sheet.
  Future<void> _pickExercise() async {
    final chosen = await nexShowSheet<WordsExercise>(
      context: context,
      builder: (ctx) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(NexSpacing.md),
          children: [
            Text(
              wordsStrings(ctx, 'practiceMode'),
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            for (final mode in WordsExercise.values)
              ListTile(
                key: ValueKey('words-exercise-${mode.name}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(_exerciseIcon(mode)),
                title: Text(wordsStrings(ctx, _exerciseLabelKey(mode))),
                trailing: mode == _exercise
                    ? const Icon(Icons.check_rounded)
                    : null,
                selected: mode == _exercise,
                onTap: () => Navigator.pop(ctx, mode),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) _setExercise(chosen);
  }

  /// The choices this card is asked with, drawn from its own deck first.
  List<String> _choicesFor(WordCard card) =>
      wordsChoices(card, _pool, reverse: _reverse, salt: _index);

  /// What is on the front of the card right now. A card with no meaning is
  /// always asked as a flashcard: there is nothing to type or choose, and
  /// the reveal offers «Add meaning».
  Widget _cardFace(WordCard card) {
    if (_revealed) return _revealedCard(context, card);
    if (card.meaning.isEmpty) return _flashcardFront(context, card);
    switch (_exercise) {
      case WordsExercise.flashcard:
        return _flashcardFront(context, card);
      case WordsExercise.type:
        return _typingFront(context, card);
      case WordsExercise.choose:
        final choices = _choicesFor(card);
        // One option is not a question: fall back to typing rather than
        // hand the answer over in a single tap.
        return choices.length < 2
            ? _typingFront(context, card)
            : _choiceFront(context, card, choices);
    }
  }

  /// The four answers, with the interval each one would give. They stay
  /// still while a save is in flight, so a double tap cannot answer twice.
  Widget _answerRow(BuildContext context, WordCard card) {
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
              backgroundColor: wordsGradeColor(entry.$1)
                  .withValues(alpha: 0.16),
              foregroundColor: wordsGradeInk(context, entry.$1),
              padding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
            ),
            onPressed: _answering || card.meaning.isEmpty
                ? null
                : () => onGrade(entry.$1),
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

  void onGrade(WordsGrade grade) => unawaited(_answer(grade));

  /// The two quarter-turns of the flashcard's turn (2.4.0): the old card
  /// accelerates away, the new one settles.
  Widget _turn(Widget child, Animation<double> animation) {
    final incoming =
        (child.key as ValueKey<String>?)?.value == _faceKey(_current!);
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = animation.value;
        // Each side shows only for its half of the turn.
        if (t < 0.5) return const SizedBox.shrink();
        final quarterTurn = math.pi / 2;
        final angle = incoming
            ? (1 - NexMotion.curve.transform(2 * t - 1)) * quarterTurn
            : NexMotion.exitCurve.transform(2 * (1 - t)) * quarterTurn;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(incoming ? -angle : angle),
          child: child,
        );
      },
    );
  }
}
