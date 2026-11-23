/// The review session: due cards first, then the day's new ones — all of
/// them, or only the deck the home page was narrowed to. A card can be
/// asked as a flashcard, typed, or answered from choices drawn from the
/// same deck, and when the queue is empty, a calm done state that neither
/// praises nor nags.
///
/// An «Again» card leaves the session when it is answered (it comes back
/// tomorrow), so nothing loops forever inside one sitting. A card skipped
/// once waits at the end of the sitting — «for now» means later, not never
/// — and a second skip lets it go. Every answer is saved before the next
/// card appears, and the buttons stay still while the save is in flight, so
/// a double tap cannot answer twice.
///
/// The way the cards are asked and the direction they are asked in are kept
/// in the module's settings: a person who learns by typing is not sent back
/// to flashcards every morning.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'words_models.dart';
import 'words_practice.dart';
import 'words_scheduler.dart';
import 'words_store.dart';
import 'words_strings.dart';
import 'words_card_page.dart';
import 'words_visuals.dart';
part 'words_review_view.dart';
part 'words_review_cards.dart';
part 'words_review_practice.dart';
part 'words_review_done.dart';

class WordsReviewPage extends StatefulWidget {
  const WordsReviewPage({
    super.key,
    required this.store,
    this.deckId,
    this.deckName,
  });

  final NexModuleStore store;

  /// The deck the session draws from, by id — the empty string means the
  /// words outside every deck. Null reviews the whole collection.
  final String? deckId;

  /// The deck's name for the bar and the done state; null when the session
  /// is not narrowed.
  final String? deckName;

  @override
  State<WordsReviewPage> createState() => _WordsReviewPageState();
}

class _WordsReviewPageState extends State<WordsReviewPage> {
  late final WordsRepository _repository;

  /// The cards still to come; the first one is on screen.
  List<WordCard> _queue = const [];

  /// Every card, for drawing wrong choices from the right deck.
  List<WordCard> _pool = const [];

  /// How many cards have left the queue: answered, or let go after a second
  /// skip. The bar and «N of M» count from it.
  int _index = 0;

  /// How many cards the sitting began with; a skipped card that comes back
  /// does not inflate it.
  int _total = 0;

  int _answered = 0;

  /// Cards let go after being skipped twice — said at the end rather than
  /// hidden.
  int _leftOut = 0;

  /// Cards already given their one trip to the back of the queue.
  final _skippedOnce = <String>{};

  bool _revealed = false;

  /// Meaning first: the card asks for the word. A card with no meaning to
  /// show still asks forward.
  bool _reverse = false;
  bool _answering = false;
  bool _loading = true;
  bool _failed = false;
  String? _answerId;

  /// How the card is asked. A typing or choice card still ends on the same
  /// four answers, so the schedule stays in the person's hands.
  WordsExercise _exercise = WordsExercise.flashcard;
  final _typed = TextEditingController();
  final _typedFocus = FocusNode();
  bool _checked = false;
  bool _wasRight = false;
  String? _chosen;

  @override
  void initState() {
    super.initState();
    _repository = WordsRepository(widget.store);
    unawaited(_load());
  }

  @override
  void dispose() {
    _typed.dispose();
    _typedFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await _repository.loadSettings();
      final session = await _repository.loadSession(deckId: widget.deckId);
      final pool = await _repository.loadCards();
      if (!mounted) return;
      setState(() {
        _queue = [...session.due, ...session.fresh];
        _pool = pool;
        _total = _queue.length;
        _index = 0;
        _answered = 0;
        _leftOut = 0;
        _reverse = settings.reverse;
        _exercise =
            WordsExercise.values.asNameMap()[settings.exercise] ??
            WordsExercise.flashcard;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  WordCard? get _current => _queue.isEmpty ? null : _queue.first;

  /// Turning the flashcard over. (A `part` cannot call `setState` on the
  /// state it extends, so the one place that does lives here.)
  void _reveal() => setState(() => _revealed = true);

  /// Everything a card's answer leaves behind, cleared for the next one.
  void _resetAnswer() {
    _revealed = false;
    _checked = false;
    _wasRight = false;
    _chosen = null;
    _answerId = null;
    _typed.clear();
  }

  /// Checking a typed answer reveals the card and says whether it matched;
  /// the person still grades it, because only they know how hard it was.
  void _checkTyped(WordCard card) {
    if (_answering || _revealed) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _checked = true;
      _wasRight = wordsAnswerMatches(
        _typed.text,
        wordsAnswerOf(card, reverse: _reverse),
      );
      _revealed = true;
    });
  }

  void _choose(WordCard card, String option) {
    if (_answering || _revealed) return;
    setState(() {
      _chosen = option;
      _wasRight =
          wordsNormalize(option) ==
          wordsNormalize(wordsAnswerOf(card, reverse: _reverse));
      _revealed = true;
    });
  }

  /// Keeping the person's way of practising: the mode and the direction
  /// outlive the session, and a failed save is not worth interrupting a
  /// review for.
  void _remember({String? exercise, bool? reverse}) => unawaited(
    _repository.updateSettings(exercise: exercise, reverse: reverse),
  );

  void _setExercise(WordsExercise exercise) {
    if (_answering || exercise == _exercise) return;
    setState(() {
      _exercise = exercise;
      _resetAnswer();
    });
    _remember(exercise: exercise.name);
  }

  void _toggleReverse() {
    if (_answering) return;
    setState(() {
      _reverse = !_reverse;
      _resetAnswer();
    });
    _remember(reverse: _reverse);
  }

  Future<void> _answer(WordsGrade grade) async {
    final card = _current;
    if (card == null || _answering || !_revealed || card.meaning.isEmpty) {
      return;
    }
    setState(() => _answering = true);
    _answerId ??= widget.store.newId();
    final result = await _repository.answer(card, grade, _answerId!);
    if (!mounted) return;
    if (result.status == WordsAnswerStatus.failed) {
      setState(() => _answering = false);
      NexBannerHost.of(context)?.show(
        kind: NexBannerKind.failed,
        message: wordsStrings(context, 'saveFailed'),
      );
      return;
    }
    setState(() {
      _answering = false;
      if (result.status == WordsAnswerStatus.saved) {
        _answered++;
        _index++;
        _queue = _queue.sublist(1);
      } else if (result.card != null) {
        _queue = [result.card!, ..._queue.sublist(1)];
      } else {
        _index++;
        _queue = _queue.sublist(1);
      }
      _resetAnswer();
    });
    if (result.status != WordsAnswerStatus.saved) {
      NexBannerHost.of(context)
          ?.show(message: wordsStrings(context, 'reviewChanged'));
    }
  }

  /// «For now» means later: the first skip puts the card back at the end of
  /// this sitting, and only a second skip lets it go — counted in the done
  /// state instead of vanishing.
  void _skip() {
    final card = _current;
    if (_answering || card == null) return;
    setState(() {
      _resetAnswer();
      final rest = _queue.sublist(1);
      if (rest.isNotEmpty && _skippedOnce.add(card.id)) {
        _queue = [...rest, card];
      } else {
        _queue = rest;
        _index++;
        _leftOut++;
      }
    });
  }

  Future<void> _editMeaning() async {
    final card = _current;
    if (card == null || _answering) return;
    setState(() => _answering = true);
    await Navigator.of(context).push(
      NexPageRoute<void>(
        builder: (_) => WordsCardPage(store: widget.store, card: card),
      ),
    );
    if (!mounted) return;
    try {
      final body = await widget.store.get('card', card.id);
      if (!mounted) return;
      setState(() {
        _answering = false;
        _resetAnswer();
        if (body == null || body['paused'] == true) {
          _index++;
          _queue = _queue.sublist(1);
        } else {
          final changed = WordCard.fromRecord(card.id, body);
          _queue = [changed, ..._queue.sublist(1)];
          _pool = [
            for (final other in _pool)
              if (other.id == card.id) changed else other,
          ];
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _answering = false);
        NexBannerHost.of(context)?.show(
          kind: NexBannerKind.failed,
          message: wordsStrings(context, 'saveFailed'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = wordsStrings;
    final deckName = widget.deckName;
    return PopScope(
      canPop: !_answering,
      child: Scaffold(
        appBar: NexAppBar(
          title: Text(
            deckName == null
                ? strings(context, 'reviewTitle')
                : strings(context, 'reviewDeck', {'name': deckName}),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              key: const ValueKey('words-review-reverse'),
              tooltip: strings(
                context,
                _reverse ? 'reverseOnTip' : 'reverseTip',
              ),
              isSelected: _reverse,
              onPressed: _answering ? null : _toggleReverse,
              icon: const Icon(Icons.swap_horiz),
              selectedIcon: const Icon(Icons.swap_horiz),
              style: _reverse
                  ? IconButton.styleFrom(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .secondaryContainer,
                    )
                  : null,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _failed
            ? NexEmptyState(
                icon: Icons.cloud_off_outlined,
                message: strings(context, 'loadError'),
                action: TextButton(
                  onPressed: () => unawaited(_load()),
                  child: Text(strings(context, 'retry')),
                ),
              )
            : _current == null
            ? _DoneView(
                answered: _answered,
                total: _total,
                leftOut: _leftOut,
                deckName: deckName,
              )
            : _reviewBody(context),
      ),
    );
  }
}
