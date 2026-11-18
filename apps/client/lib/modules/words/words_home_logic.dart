part of 'words_screen.dart';

mixin _WordsHomeLogic on State<WordsScreen>, WidgetsBindingObserver {
  late final WordsRepository _repository;
  List<WordCard> _cards = const [];
  List<WordsDeck> _decks = const [];
  WordsSettings _settings = const WordsSettings(
    newPerDay: WordsSettings.defaultPerDay,
  );
  StreamSubscription<void>? _changes;
  bool _loading = true;
  bool _failed = false;
  bool _showAllTags = false;
  bool _settingsOpen = false;
  int _generation = 0;

  final _search = TextEditingController();
  String _query = '';
  _StatusFilter _filter = _StatusFilter.all;
  String? _tagFilter;

  /// The deck the list is narrowed to; null shows every word, and an empty
  /// string means the words that sit outside every deck.
  String? _deckFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _repository = WordsRepository(widget.store);
    _changes = _repository.changes.listen((_) => unawaited(_reload()));
    unawaited(_reload());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_changes?.cancel());
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_reload());
  }

  /// Repainting the page from a `part` file: `setState` is protected, so
  /// the one place that may call it lives in the state itself.
  void _paint(VoidCallback change) => setState(change);

  Future<void> _reload() async {
    final generation = ++_generation;
    try {
      final cards = await _repository.loadCards();
      final settings = await _repository.loadSettings();
      final decks = await _repository.loadDecks();
      if (!mounted || generation != _generation) return;
      setState(() {
        _cards = cards;
        _settings = settings;
        _decks = decks;
        _loading = false;
        _failed = false;
      });
      // The reminder follows the cards: a review moves the next due day.
      unawaited(
        wordsArmReminder(
          widget.store,
          AppLocalizations.of(context),
          preserveShown: true,
        ).catchError((_) => false),
      );
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  String get _todayIso => isoDay(DateTime.now());

  /// Copies the list on screen — every word the filters leave — as the text
  /// the paste box takes back: one word per line, a Tab, the meaning.
  Future<void> _copyList() async {
    final cards = _visible;
    if (cards.isEmpty) return;
    await nexModuleCopyText(wordsListText(cards));
    if (!mounted) return;
    nexShowBanner(
      context,
      message: wordsStrings(
        context,
        cards.length == 1 ? 'listCopiedOne' : 'listCopiedMany',
        {'count': cards.length},
      ),
    );
  }

  List<WordCard> get _visible {
    final query = _query.toLowerCase();
    Iterable<WordCard> cards = _cards;
    if (_filter == _StatusFilter.newWords) {
      cards = cards.where((card) => card.isNew);
    } else if (_filter == _StatusFilter.due) {
      final today = _todayIso;
      cards = cards.where((card) => card.isDueOn(today));
    } else if (_filter == _StatusFilter.paused) {
      cards = cards.where((card) => card.paused);
    }
    if (_filter == _StatusFilter.learned) {
      cards = cards.where(
        (card) => !card.paused && !card.isNew && card.step >= 5,
      );
    }
    if (_tagFilter != null) {
      cards = cards.where((card) => card.tag == _tagFilter);
    }
    final deckFilter = _deckFilter;
    if (deckFilter != null) {
      cards = cards.where((card) => wordsCardDeck(_decks, card) == deckFilter);
    }
    if (query.isNotEmpty) {
      cards = cards.where((card) {
        final haystack = [
          card.headword,
          card.language,
          card.meaning,
          card.example,
          card.note,
          card.tag,
        ].join('\n');
        return haystack.toLowerCase().contains(query);
      });
    }
    return cards.toList();
  }

  int get _dueCount => _cards.where((card) => card.isDueOn(_todayIso)).length;

  /// The small daily goal in answers, and how many were given today. A
  /// missed day is not counted anywhere — there is no streak.
  int get _goal => _settings.goalPerDay;
  int get _reviewedToday => wordsReviewsOn(_cards, _todayIso);

  void _openProgress() => unawaited(
    showWordsProgressSheet(context, cards: _cards, settings: _settings),
  );

  /// The deck sheet doubles as «new deck» and as the way to narrow the
  /// list: choosing a deck here filters the words to it.
  void _manageDecks() => unawaited(
    showWordsDeckPicker(
      context,
      _repository,
      selectedId: _deckFilter ?? '',
      onPicked: (id) => setState(() => _deckFilter = id.isEmpty ? null : id),
    ),
  );

  /// New cards the day may still introduce, with the cap applied.
  int get _newToday => buildSession(
    cards: _cards,
    todayIso: _todayIso,
    newPerDay: _settings.newPerDay,
    sessionLimit: 0,
  ).fresh.length;
}

/// [cards] as pasteable lines: `word<TAB>meaning`. A Tab or a line break
/// inside a word or meaning would break the line, so each becomes a space
/// (senses of a meaning are joined with « ; »). A word with no meaning is
/// just the word. The paste box reads this back unchanged.
String wordsListText(Iterable<WordCard> cards) {
  String flat(String text, String between) => text
      .split(RegExp(r'[\r\n]+'))
      .map((part) => part.replaceAll('\t', ' ').trim())
      .where((part) => part.isNotEmpty)
      .join(between);
  return cards
      .map((card) {
        final word = flat(card.headword, ' ');
        final meaning = flat(card.meaning, ' ; ');
        return meaning.isEmpty ? word : '$word\t$meaning';
      })
      .join('\n');
}
