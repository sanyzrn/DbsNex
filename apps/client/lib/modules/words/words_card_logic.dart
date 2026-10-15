part of 'words_card_page.dart';

mixin _WordsCardLogic on State<WordsCardPage> {
  void _repairPaint(VoidCallback change) => setState(change);
  late final WordsRepository _repository;

  /// The card as it stands — the words come from the controllers; the
  /// scheduling fields are carried over untouched when saving.
  late WordCard _card;

  final _headword = TextEditingController();
  final _scroll = ScrollController();
  final _wordFocus = FocusNode();
  final _language = TextEditingController();
  final _meaning = TextEditingController();
  final _example = TextEditingController();
  final _note = TextEditingController();
  final _tag = TextEditingController();

  bool _saving = false;
  bool _restoring = true;
  bool _draftLoadFailed = false;
  late FormDraft _draft;

  @override
  void initState() {
    super.initState();
    _repository = WordsRepository(widget.store);
    final card = widget.card;
    _card =
        card ??
        WordCard(
          id: widget.store.newId(),
          headword: '',
          language: '',
          createdAtIso: DateTime.now().toIso8601String(),
          step: 0,
          due: isoDay(DateTime.now()),
        );
    _headword.text = _card.headword;
    _language.text = _card.language;
    _meaning.text = _card.meaning;
    _example.text = _card.example;
    _note.text = _card.note;
    _tag.text = _card.tag;
    _draft = _makeDraft();
    unawaited(_restore(initial: true));
  }

  @override
  void dispose() {
    _draft.close();
    _scroll.dispose();
    _wordFocus.dispose();
    _headword.dispose();
    _language.dispose();
    _meaning.dispose();
    _example.dispose();
    _note.dispose();
    _tag.dispose();
    super.dispose();
  }

  void _error() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(wordsStrings(context, 'saveFailed'))),
      );
    }
  }

  Future<void> _save() async {
    if (_saving || _restoring || _draftLoadFailed) return;
    final headword = foldWhitespace(_headword.text);
    if (headword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(wordsStrings(context, 'wordRequired'))),
      );
      if (_scroll.hasClients) {
        await _scroll.animateTo(
          0,
          duration: NexMotion.of(context, NexMotion.standard),
          curve: NexMotion.curve,
        );
      }
      if (mounted) _wordFocus.requestFocus();
      return;
    }
    setState(() => _saving = true);
    try {
      final language = foldWhitespace(_language.text);
      final candidate = _card.copyWith(headword: headword, language: language);
      final others = await _repository.loadCards();
      if (!mounted) return;
      final duplicate = others
          .where((other) => other.sameWordAs(candidate))
          .firstOrNull;
      if (duplicate != null) {
        final accepted = await nexShowDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(wordsStrings(ctx, 'duplicateTitle')),
            content: NexDialogBody(
              child: Text(
                wordsStrings(ctx, 'duplicateBody', {
                  'word': headword,
                  'language': duplicate.language,
                }),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(AppLocalizations.of(ctx).cancel),
              ),
              TextButton(
                key: const ValueKey('words-duplicate-add'),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(wordsStrings(ctx, 'duplicateAdd')),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (accepted != true) {
          if (_scroll.hasClients) {
            await _scroll.animateTo(
              0,
              duration: NexMotion.of(context, NexMotion.standard),
              curve: NexMotion.curve,
            );
          }
          if (mounted) _wordFocus.requestFocus();
          return;
        }
      }
      final saved = await _repository.saveCard(
        candidate.copyWith(
          meaning: _meaning.text.trim(),
          example: _example.text.trim(),
          note: _note.text.trim(),
          tag: foldWhitespace(_tag.text),
        ),
        preserveProgress: true,
        requireExisting: widget.card != null,
      );
      if (!mounted) return;
      if (!saved) {
        _error();
        return;
      }
      await _draft.clear();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      _error();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (widget.card == null || _saving || _restoring || _draftLoadFailed) {
      return;
    }
    setState(() => _saving = true);
    try {
      final confirmed = await nexShowDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(wordsStrings(ctx, 'deleteTitle')),
          content: NexDialogBody(child: Text(wordsStrings(ctx, 'deleteBody'))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(ctx).cancel),
            ),
            TextButton(
              key: const ValueKey('words-delete-confirm'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(AppLocalizations.of(ctx).delete),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      if (!await _draft.finish()) {
        _draft.resume();
        _error();
        return;
      }
      final bundle = await _repository.deleteCard(_card);
      if (!mounted) return;
      if (bundle == null) {
        _draft.resume();
        _error();
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      final removed = wordsStrings(context, 'wordDeleted');
      final restored = wordsStrings(context, 'wordRestored');
      final failed = wordsStrings(context, 'saveFailed');
      final undo = AppLocalizations.of(context).undo;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(removed),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: undo,
            onPressed: () => unawaited(
              _repository
                  .restoreBundle(bundle)
                  .then(
                    (ok) => messenger.showSnackBar(
                      SnackBar(content: Text(ok ? restored : failed)),
                    ),
                  ),
            ),
          ),
        ),
      );
    } catch (_) {
      _draft.resume();
      _error();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _togglePaused() async {
    if (_saving || _restoring || widget.card == null) return;
    setState(() => _saving = true);
    try {
      final next = await _repository.setPaused(_card.id, !_card.paused);
      if (!mounted) return;
      if (next == null) {
        _error();
        return;
      }
      setState(() => _card = next);
    } catch (_) {
      _error();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, TextEditingController> get _controllers => {
    'headword': _headword,
    'language': _language,
    'meaning': _meaning,
    'example': _example,
    'note': _note,
    'tag': _tag,
  };
  FormDraft _makeDraft() => FormDraft(
    widget.store,
    'card:${widget.card?.id ?? 'new'}',
    widget.card == null
        ? const {}
        : {
            'headword': widget.card!.headword,
            'language': widget.card!.language,
            'meaning': widget.card!.meaning,
            'example': widget.card!.example,
            'note': widget.card!.note,
            'tag': widget.card!.tag,
          },
    _controllers,
    () => {'recordId': _card.id, 'createdAt': _card.createdAtIso},
  );
  Future<void> _restore({bool initial = false}) async {
    if (_restoring && !initial) return;
    setState(() => _restoring = true);
    final body = await _draft.load();
    if (!mounted) return;
    if (_draft.loadFailed) {
      setState(() {
        _restoring = false;
        _draftLoadFailed = true;
      });
      return;
    }
    if (body != null) {
      _draft.apply(body);
      if (widget.card == null &&
          body['recordId'] is String &&
          (body['recordId'] as String).isNotEmpty) {
        _card = WordCard(
          id: body['recordId'] as String,
          headword: '',
          language: '',
          createdAtIso:
              wordsValidStamp('${body['createdAt'] ?? ''}') ??
              _card.createdAtIso,
          due: isoDay(DateTime.now()),
        );
      }
    }
    _draft.resume();
    setState(() {
      _restoring = false;
      _draftLoadFailed = false;
    });
  }

  Future<void> _cancel() async {
    if (_saving || _restoring) return;
    setState(() => _saving = true);
    if (!await _draft.clear()) {
      if (!_draftLoadFailed) _draft.resume();
      _error();
      if (mounted) setState(() => _saving = false);
      return;
    }
    if (mounted) Navigator.pop(context);
  }
}
