/// The review session: due cards first, then the day's new ones. Tap to
/// reveal, answer, next — and when the queue is empty, a calm done state
/// that neither praises nor nags.
///
/// An «Again» card leaves the session when it is answered (it comes back
/// tomorrow), so nothing loops forever inside one sitting. Every answer
/// is saved before the next card appears, and the buttons stay still
/// while the save is in flight — a double tap cannot answer twice.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'words_models.dart';
import 'words_scheduler.dart';
import 'words_store.dart';
import 'words_strings.dart';
import 'words_card_page.dart';
part 'words_review_view.dart';
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
  int _index = 0;
  bool _revealed = false;
  bool _answering = false;
  bool _loading = true;
  int _answered = 0;
  bool _failed = false;
  String? _answerId;

  @override
  void initState() {
    super.initState();
    _repository = WordsRepository(widget.store);
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final session = await _repository.loadSession();
      if (!mounted) return;
      setState(() {
        _queue = [...session.due, ...session.fresh];
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(wordsStrings(context, 'saveFailed'))),
      );
      return;
    }
    setState(() {
      _answering = false;
      _answerId = null;
      _revealed = false;
      if (result.status == WordsAnswerStatus.saved) {
        _answered++;
        _index++;
      } else if (result.card != null) {
        _queue[_index] = result.card!;
      } else {
        _index++;
      }
    });
    if (result.status != WordsAnswerStatus.saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(wordsStrings(context, 'reviewChanged'))),
      );
    }
  }

  void _skip() {
    if (_answering || _current == null) return;
    setState(() {
      _index++;
      _answerId = null;
      _revealed = false;
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
        _revealed = false;
        _answerId = null;
        if (body == null || body['paused'] == true) {
          _index++;
        } else {
          _queue[_index] = WordCard.fromRecord(card.id, body);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _answering = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(wordsStrings(context, 'saveFailed'))),
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
        appBar: NexAppBar(title: Text(strings(context, 'reviewTitle'))),
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
            ? _DoneView(answered: _answered, total: _queue.length)
            : _ReviewBody(
                card: _current!,
                revealed: _revealed,
                answering: _answering,
                index: _index,
                total: _queue.length,
                onReveal: () => setState(() => _revealed = true),
                onAnswer: (grade) => unawaited(_answer(grade)),
                onEdit: () => unawaited(_editMeaning()),
                onSkip: _skip,
              ),
      ),
    );
  }
}
