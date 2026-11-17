/// The review session: due cards first, then the day's new ones. A card
/// can be asked as a flashcard, typed, or answered from choices drawn from
/// the same deck — and when the queue is empty, a calm done state that
/// neither praises nor nags.
///
/// An «Again» card leaves the session when it is answered (it comes back
/// tomorrow), so nothing loops forever inside one sitting. Every answer
/// is saved before the next card appears, and the buttons stay still
/// while the save is in flight — a double tap cannot answer twice.
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
  const WordsReviewPage({super.key, required this.store});

  final NexModuleStore store;

  @override
  State<WordsReviewPage> createState() => _WordsReviewPageState();
}

class _WordsReviewPageState extends State<WordsReviewPage> {
  late final WordsRepository _repository;
  List<WordCard> _queue = const [];

  /// Every card, for drawing wrong choices from the right deck.
  List<WordCard> _pool = const [];
  int _index = 0;
  bool _revealed = false;

  /// Meaning first: the card asks for the word. A card with no meaning to
  /// show still asks forward.
  bool _reverse = false;
  bool _answering = false;
  bool _loading = true;
  int _answered = 0;
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
      final session = await _repository.loadSession();
      final pool = await _repository.loadCards();
      if (!mounted) return;
      setState(() {
        _queue = [...session.due, ...session.fresh];
        _pool = pool;
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

  WordCard? get _current => _index < _queue.length ? _queue[_index] : null;

  int get _total => _queue.length;

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

  void _setExercise(WordsExercise exercise) {
    if (_answering) return;
    setState(() {
      _exercise = exercise;
      _resetAnswer();
    });
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
        _resetAnswer();
      } else if (result.card != null) {
        _queue[_index] = result.card!;
        _resetAnswer();
      } else {
        _index++;
        _resetAnswer();
      }
    });
    if (result.status != WordsAnswerStatus.saved) {
      NexBannerHost.of(context)
          ?.show(message: wordsStrings(context, 'reviewChanged'));
    }
  }

  void _skip() {
    if (_answering || _current == null) return;
    setState(() {
      _index++;
      _resetAnswer();
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
        } else {
          final changed = WordCard.fromRecord(card.id, body);
          _queue[_index] = changed;
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
    return PopScope(
      canPop: !_answering,
      child: Scaffold(
        appBar: NexAppBar(
          title: Text(strings(context, 'reviewTitle')),
          actions: [
            IconButton(
              key: const ValueKey('words-review-reverse'),
              tooltip: strings(
                context,
                _reverse ? 'reverseOnTip' : 'reverseTip',
              ),
              isSelected: _reverse,
              onPressed: _answering
                  ? null
                  : () => setState(() {
                      _reverse = !_reverse;
                      _resetAnswer();
                    }),
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
            ? _DoneView(answered: _answered, total: _total)
            : _reviewBody(context),
      ),
    );
  }
}
