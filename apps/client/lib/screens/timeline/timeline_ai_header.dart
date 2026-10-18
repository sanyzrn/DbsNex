part of '../timeline_screen.dart';

/// The greeting, the AI headline and recap, and the daily brief card.
extension _TimelineAiHeader on TimelineScreenState {
  /// True when there is a provider configured to generate anything at all.
  /// The whole header — headline and card both — is absent otherwise, rather
  /// than showing empty chrome for a feature that is switched off.
  bool get _aiHeaderAvailable =>
      widget.preferences.aiEnabled &&
      aiTextAvailableWith(widget.preferences.aiProvider);

  /// Whether the brief card is drawn at all.
  ///
  /// Not the same question as [_aiHeaderAvailable], which is about the
  /// greeting as well and is genuinely about whether a model can be reached.
  /// One of the brief's styles asks nothing of a model, and a card that works
  /// without one has no business being hidden because there is none — but
  /// only for somebody who chose that style. Left on the default, an app with
  /// intelligence switched off looks exactly as it did.
  bool get _briefAvailable =>
      _aiHeaderAvailable || !widget.preferences.briefStyle.usesModel;

  /// Builds an adapter with the user's chosen output language applied.
  ///
  /// Every call site here closes it; the caller owning the lifetime is why
  /// this is a factory and not a field.
  CloudAIAdapter _aiAdapter() => CloudAIAdapter(
    config: widget.preferences.aiProvider,
    outputLanguage: widget.preferences.aiOutputLanguage,
    unlimitedSummary: widget.preferences.aiSummaryUnlimited,
  );

  /// All deliveries share one request, including manual taps during a flight.
  Future<void> _loadAiSummary({bool force = false}) {
    if (force) _aiSummaryManualRequested = true;
    final pending = _aiSummaryInFlight;
    if (pending != null) return pending;
    final work = _askAiSummary(force: force);
    final flight = work.whenComplete(() {
      _aiSummaryInFlight = null;
      _aiSummaryManualRequested = false;
      if (mounted) _armBriefRefresh();
    });
    _aiSummaryInFlight = flight;
    return flight;
  }

  String _briefFingerprint() {
    final prefs = widget.preferences;
    final config = prefs.aiProvider;
    final stableSource = _aiRecapSource(forFingerprint: true);
    final budget = nexBriefLines(
      '\n'.allMatches(stableSource).length + 1,
      ceiling: prefs.briefLength.lines,
    );
    final facts = prefs.briefStyle.statesFacts
        ? nexBriefFactsSignature(
            nexBriefFacts(
              _model.all ?? _model.notes,
              commitments: _model.commitments,
            ),
            maxLines: (budget - 1).clamp(1, budget),
          )
        : '';
    return TimelineScreenState.recapFingerprint(
      nexBriefSignature(
        source:
            '$stableSource\n$facts\n'
            '${config.provider.wireName}|${config.resolvedBaseUrl}|${config.resolvedModel}|'
            '${prefs.aiSummaryUnlimited}|${prefs.briefStyle.statesFacts ? Localizations.localeOf(context) : ''}',
        style: prefs.briefStyle,
        tone: prefs.briefTone,
        length: prefs.briefLength,
        language: prefs.aiOutputLanguage,
        instruction: prefs.briefInstruction,
      ),
    );
  }

  bool get _briefForeground {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  void _armBriefRefresh() {
    _aiSummaryWake?.cancel();
    final prefs = widget.preferences;
    if (!_aiHeaderAvailable ||
        !prefs.showDaySummary ||
        !prefs.briefStyle.usesModel ||
        _aiRecapSource().isEmpty ||
        !_briefForeground) {
      return;
    }
    final fingerprint = _briefFingerprint();
    // No recurring timer: unchanged information never generates another brief.
    if (prefs.aiDaySummarySource == fingerprint) return;
    final next = widget.services.briefRefresh.nextAllowedAt();
    final wait = next.difference(DateTime.now());
    // A changed input arriving during a flight also gets checked here.
    _aiSummaryWake = Timer(wait.isNegative ? Duration.zero : wait, () {
      if (mounted) unawaited(_loadAiSummary());
    });
  }

  Future<void> _askAiSummary({required bool force}) async {
    await _briefCommitmentsReady;
    if (!mounted) return;
    force = force || _aiSummaryManualRequested;
    final prefs = widget.preferences;
    if (!_briefAvailable || (!force && !prefs.showDaySummary)) return;
    final cached = CloudAIAdapter.cleanDecorativeReply(prefs.aiDaySummaryText);
    if (mounted &&
        cached != null &&
        cached.isNotEmpty &&
        cached != _aiSummaryText) {
      _rebuild(() => _aiSummaryText = cached);
    }
    final source = _aiRecapSource();
    if (source.isEmpty) return;
    // Which notes the brief is written from, for the log of what left the
    // phone: it used to name none (1.99.96 reviews, SEC-01).
    final sourceNotes = nexRecapNoteIds(
      _model.all ?? _model.notes,
      commitments: _model.commitments,
    );
    final style = prefs.briefStyle;
    final length = prefs.briefLength;
    final budget = nexBriefLines(
      '\n'.allMatches(source).length + 1,
      ceiling: length.lines,
    );
    final written = style.statesFacts
        ? nexBriefReport(
            nexBriefFacts(
              _model.all ?? _model.notes,
              commitments: _model.commitments,
            ),
            AppLocalizations.of(context),
            maxLines: style.usesModel ? (budget - 1).clamp(1, budget) : budget,
            clock: (local) => nexDueClock(context, local),
          )
        : null;
    if (!style.usesModel) {
      if (mounted) {
        _rebuild(() {
          _aiSummaryLoading = false;
          _aiSummaryText = written;
        });
      }
      _refreshDailyNudge();
      return;
    }
    if (!force && !_briefForeground) return;
    final fingerprint = _briefFingerprint();
    final refresh = widget.services.briefRefresh;
    if (!force && !refresh.needs(fingerprint)) return;
    final config = prefs.aiProvider;
    final language = prefs.aiOutputLanguage;
    final unlimited = prefs.aiSummaryUnlimited;
    final tone = prefs.briefTone;
    final instruction = prefs.briefInstruction;
    if (mounted) _rebuild(() => _aiSummaryLoading = true);
    try {
      final result = await refresh.refresh(
        fingerprint: fingerprint,
        dateKey: _aiSummaryDateKey(),
        force: force,
        request: () async {
          final adapter = CloudAIAdapter(
            config: config,
            outputLanguage: language,
            unlimitedSummary: unlimited,
          );
          try {
            final answer = await NexDisclosureLog.about(
              notes: sourceNotes,
              () => adapter.digest(
                source,
                lines: budget,
                style: style,
                tone: tone,
                instruction: instruction,
                written: written ?? '',
                words: length.words,
                timeout: force
                    ? const Duration(minutes: 5)
                    : unlimited
                    ? const Duration(minutes: 3)
                    : CloudAIAdapter.ambientTimeout,
              ),
            );
            // Local facts are useful fallback text, never an AI success stamp.
            if (answer == null || answer.trim().isEmpty) return null;
            return [
              if (written != null && written.isNotEmpty) written,
              answer,
            ].join('\n');
          } finally {
            adapter.close();
          }
        },
      );
      if (result.updated) unawaited(widget.widgets?.refresh());
      if (!mounted) return;
      _rebuild(() {
        _aiSummaryText = result.text ?? _aiSummaryText ?? written;
      });
      if ((force || _aiSummaryManualRequested) && result.failed) {
        NexBannerHost.of(context)?.show(
          message: AppLocalizations.of(context).recapRefreshFailed,
          kind: NexBannerKind.failed,
        );
      }
      _refreshDailyNudge();
    } finally {
      if (mounted) _rebuild(() => _aiSummaryLoading = false);
    }
  }

  /// Which language the generated line has to be written in.
  ///
  /// Not the global "language Nex writes in", which is what every other
  /// generated string here follows. This one is glued onto the greeting and
  /// read as a single sentence, and the greeting is written in the language
  /// of the user's own name — so on the default setting ("answer in the
  /// language of the notes") the result was half an English sentence joined
  /// to half a Persian one, full stop at the wrong end.
  ///
  /// Null when there is no name to take the cue from; the line then stands
  /// alone and the global setting is right for it.
  AiOutputLanguage? get _headlineLanguage {
    final name = widget.preferences.shortDisplayName;

    return nexDirectionOf(name) == TextDirection.rtl
        ? AiOutputLanguage.persian
        : AiOutputLanguage.english;
  }

  /// The headline over the timeline. Same shape as [_loadAiSummary] — cached
  /// per day, forced by a tap on the line itself.
  Future<void> _loadAiHeadline({bool force = false}) async {
    final prefs = widget.preferences;
    if (!_aiHeaderAvailable) return;
    // Drawn only beside the greeting; with the greeting hidden it is not
    // asked for.
    if (!force && !prefs.showGreeting) return;
    final today = _aiSummaryDateKey();
    final language = _headlineLanguage;
    final langKey = language?.wireName;
    if (_aiHeadlineLoading) return;
    _rebuild(() => _aiHeadlineLoading = true);
    try {
      final text = await widget.services.briefRefresh.headline(
        dateKey: today,
        language: langKey,
        force: force,
        request: () async {
          final adapter = _aiAdapter();
          try {
            return await NexDisclosureLog.about(
              notes: _aiHeadlineNotes().map((note) => note.id),
              () => adapter.headline(
                _aiHeadlineSource(),
                language: language,
                timeout: force || prefs.aiSummaryUnlimited
                    ? const Duration(minutes: 5)
                    : CloudAIAdapter.ambientTimeout,
              ),
            );
          } finally {
            adapter.close();
          }
        },
      );
      if (mounted && text != null && text.isNotEmpty) {
        _rebuild(
          () => _aiHeadlineText = CloudAIAdapter.cleanDecorativeReply(text),
        );
      }
    } finally {
      if (mounted) _rebuild(() => _aiHeadlineLoading = false);
    }
  }

  /// Holding the headline explicitly asks for a new one.
  ///
  /// With no provider configured there is still something to refresh — the
  /// local greeting has three phrasings per time of day, and re-rolling one
  /// is what the same tap does. A tap target that does nothing on half the
  /// installs would be worse than not having it.
  void _refreshHeadline() {
    if (_aiHeadlineLoading) return;
    _tick();
    if (_aiHeaderAvailable) {
      unawaited(_loadAiHeadline(force: true));
      return;
    }
    _rebuild(() {
      // Never the one already showing: a refresh that lands on the same words
      // one time in three reads as a broken button.
      _greetingVariant = (_greetingVariant + 1 + math.Random().nextInt(2)) % 3;
    });
  }

  /// Opens the assistant, held rather than tapped — see the capture button.
  ///
  /// Offers provider setup when the assistant is not configured yet.
  void _openAssistant() {
    if (!AiChatSheet.availableFor(widget.preferences)) {
      final l10n = AppLocalizations.of(context);
      _tick();
      nexShowBanner(
        context,
        kind: NexBannerKind.ai,
        haptics: widget.preferences.haptics,
        message: l10n.assistantNeedsIntelligence,
        actionLabel: l10n.assistantTurnOnIntelligence,
        onAction: () => unawaited(_openIntelligence()),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    unawaited(
      AiChatSheet.show(
        context,
        preferences: widget.preferences,
        services: widget.services,
        history: widget.preferences.chatHistory,
      ),
    );
  }

  /// The screen where the assistant is switched on, from the notice that
  /// says it is not.
  ///
  /// Awaited, and the timeline rebuilds on the way back: turning intelligence
  /// on is exactly the change that makes the button this came from start
  /// doing something else.
  Future<void> _openIntelligence() async {
    await Navigator.push(
      context,
      NexPageRoute<void>(
        builder: (_) => IntelligenceScreen(
          services: widget.services,
          preferences: widget.preferences,
        ),
      ),
    );
    if (mounted) _rebuild(() {});
  }

  void _toggleAiSummary() {
    _tick();
    _rebuild(() {
      _aiSummaryToggledByUser = true;
      _aiSummaryCollapsed = !_aiSummaryCollapsed;
    });
    unawaited(widget.preferences.setDaySummaryFolded(_aiSummaryCollapsed));
  }

  String _aiSummaryDateKey() =>
      NexPreferences.daySummaryDateKey(DateTime.now());

  /// Re-arms the once-a-day notification with whatever Nex knows right now.
  ///
  /// Every open, not once at setup. The notification repeats daily on its own
  /// — that part the system handles — but its text is fixed at the moment it
  /// was scheduled, and the recap it carries is a day old by the next
  /// morning. So the schedule is rewritten each time the app is in a position
  /// to know something newer, which is here.
  void _refreshDailyNudge() {
    if (!mounted || !widget.preferences.dailyNudge) return;
    unawaited(
      DailyNudge.apply(
        context: context,
        preferences: widget.preferences,
        reminders: widget.services.reminders,
        recap: widget.preferences.lastRecap,
      ),
    );
  }

  /// The most recent notes' own text, newest first.
  ///
  /// The headline's source, and only the headline's. That line is a mood —
  /// it wants to know roughly what someone has been writing about and
  /// nothing else, and telling it what is due would turn a greeting into a
  /// second recap.
  String _aiHeadlineSource() =>
      [for (final note in _aiHeadlineNotes()) _headlineText(note)].join('\n');

  /// The notes the headline reads: the newest twenty with words in them.
  Iterable<Note> _aiHeadlineNotes() => (_model.all ?? _model.notes)
      .take(20)
      .where((note) => _headlineText(note).isNotEmpty);

  static String _headlineText(Note note) =>
      (note.content ?? note.transcriptText ?? note.ocrText ?? '').trim();

  /// The recap's source: the library's state, not a slice of its prose.
  ///
  /// Everything the recap can say about what is due or unfinished comes from
  /// here — see [nexRecapSource], which also explains why the twenty newest
  /// notes were the wrong twenty. The whole list goes in rather than a
  /// pre-cut slice, because the choosing is the part that matters and it
  /// needs everything to choose from.
  /// The standing obligations, as the brief last saw them.
  ///
  /// Held in a field rather than read inside [_aiRecapSource], because that
  /// method is synchronous and is called to *decide whether* to ask the model
  /// — a database read there would make the staleness check asynchronous and
  /// put a query on a path that mostly concludes "nothing has changed". They
  /// are refreshed when the screen loads and whenever the commitments screen
  /// closes, which is every moment they can have changed.
  String _aiRecapSource({bool forFingerprint = false}) => nexRecapSource(
    _model.all ?? _model.notes,
    commitments: _model.commitments,
    forFingerprint: forFingerprint,
  );

  /// The screen used to seed `notes` synchronously from the repository. The
  /// stream alone is not a replacement: it is a broadcast stream, so anything
  /// emitted before initState subscribes is dropped — a refresh that happens
  /// during startup left the timeline empty.
  /// Asks for the header's recap and headline, once, as soon as there is
  /// anything to describe — from whichever delivery arrives first.
  ///
  /// This used to hang off the timeline stream alone, and that was a race the
  /// screen could lose without anything looking wrong. `_timelineController`
  /// is a broadcast controller, so an event fired before anyone is listening
  /// is not queued, it is gone — and `NexServices.bootstrap` fires one, from
  /// a `unawaited(refreshTimeline())`, long before this screen exists. The
  /// notes themselves were never at risk, because [_loadTimeline] fetches
  /// them directly rather than waiting to be told; only the recap was, and it
  /// then sat blank until the *next* event happened to come along — a
  /// capture, or leaving the app and coming back. That could be minutes, and
  /// what a person saw in the meantime was a card saying there was nothing to
  /// summarise on a library full of notes.
  ///
  /// So the trigger goes where the data does. Both paths call this, the flag
  /// makes it once, and whichever gets there first wins.
  void _requestAiHeader(List<Note> delivered) {
    if (delivered.isEmpty && _model.commitments.isEmpty) return;
    // The recap is allowed to re-ask. Its own gate decides whether the notes
    // have moved on and whether an hour has passed, so calling it on every
    // delivery costs a hash and buys a recap that keeps up with the day.
    unawaited(_loadAiSummary());
    // The headline is not. It is a mood for the day with a day key of its
    // own, and re-rolling it on every capture would make the top of the
    // screen restless.
    if (_aiSummaryRequested) return;
    _aiSummaryRequested = true;
    unawaited(_loadAiHeadline());
  }

  /// The brief, as the first card above the notes.
  ///
  /// It has the note card's insets and corner, and none of its height rule.
  /// The sponsor card the slot was built for is pinned to exactly one card's
  /// height on purpose — a banner taller than the things around it has
  /// stopped being an item in a list and started being an interruption — but
  /// that reasoning is about a card selling something. This one is the app
  /// reading the day back, and how long it is depends entirely on how much
  /// there was to say. So it grows with its text.
  ///
  /// No icon, and no heading. The sparkle used to sit at the top of this and
  /// it was naming something already named: it is the only generated surface
  /// on the timeline, and the light going round its edge says so without
  /// spending a row of the screen.
  Widget _briefCard(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    const corner = BorderRadius.all(Radius.circular(NexRadius.lg));
    return Padding(
      padding: nexCardInsets,
      child: NexBorderBeam(
        borderRadius: corner,
        colors: [
          scheme.primary.withValues(alpha: 0.08),
          scheme.primary,
          scheme.primary.withValues(alpha: 0.08),
        ],
        thickness: 0.6,
        laps: 1,
        strength: 0.25,
        active: !_aiSummaryCollapsed,
        token: _aiSummaryText,
        child: NexGlassSurface(
          blur: false,
          borderRadius: corner,
          showShadow: false,
          fallbackColor: scheme.surfaceContainerLowest,
          child: _AiDaySummaryPanel(
            // Keyed so a test can say "the brief is on screen" without
            // reaching for a glyph. It used to be found by its sparkle,
            // which is a thing any other surface could start wearing.
            key: const ValueKey('timeline-recap'),
            loading: _aiSummaryLoading,
            text: _aiSummaryText,
            emptyLabel: l10n.aiDaySummaryEmpty,
            collapsed: _aiSummaryCollapsed,
            semanticLabel: l10n.aiDaySummarySemanticLabel,
            toggleTooltip: _aiSummaryCollapsed
                ? l10n.aiDaySummaryExpand
                : l10n.aiDaySummaryCollapse,
            onToggle: _toggleAiSummary,
          ),
        ),
      ),
    );
  }

  /// "Good evening, Saeed", and the mark that goes after it — or null when
  /// the user never told the app a name.
  ///
  /// Decoration, and it never leaves the device: the name is not sent with a
  /// sync, and not sent to the AI provider either — the generated headline
  /// beside this line is deliberately written without it.
  ///
  /// Three phrasings per time of day. Re-rolled only when the headline is
  /// tapped, never on an ordinary rebuild: a title that changes while you are
  /// reading it is a bug, not a flourish.
  /// The one line the app opens with.
  ///
  /// [aiPhrase] replaces the canned phrasing when a model wrote one; the name
  /// is still appended here rather than sent anywhere. That split is the whole
  /// design: the greeting is the only place the user's own name appears, and
  /// it never leaves the device — not to a provider, not to sync. So the model
  /// is asked for a phrase with a slot after it, and this puts the name in.
  String? _greeting(AppLocalizations interface, {String? aiPhrase}) {
    // Two words at most — a full name pushes this onto a second line and
    // shoves the headline under it out of place.
    final name = widget.preferences.shortDisplayName;

    // Greeted in the language you wrote your own name in, whatever the
    // interface is set to. "صبح بخیر, Sany" and "Good morning, سعید" are both
    // sentences nobody writes, and the name is the one word here the app did
    // not choose — so it is the one that decides.
    final l10n = name == null
        ? interface
        : nexDirectionOf(name) == TextDirection.rtl
        ? lookupAppLocalizations(const Locale('fa'))
        : lookupAppLocalizations(const Locale('en'));
    final v = _greetingVariant;
    // Words only. There used to be a mark on the end of this line — a sun, a
    // moon, an owl, picked by the hour and animated in — and it is gone by
    // request. It was the one piece of decoration on the first screen, and
    // decoration is what this app is against everywhere else: the line is
    // already the softest thing on the timeline, and an emoji beside it made
    // it read as an app being cheerful at somebody rather than as somebody's
    // own notes greeting them.
    final text = switch (DateTime.now().hour) {
      >= 5 && < 12 => [
        l10n.greetingMorning,
        l10n.greetingMorningB,
        l10n.greetingMorningC,
      ],
      >= 12 && < 17 => [
        l10n.greetingAfternoon,
        l10n.greetingAfternoonB,
        l10n.greetingAfternoonC,
      ],
      >= 17 && < 23 => [
        l10n.greetingEvening,
        l10n.greetingEveningB,
        l10n.greetingEveningC,
      ],
      _ => [l10n.greetingNight, l10n.greetingNightB, l10n.greetingNightC],
    };
    // A comma in the script the name is written in — the phrase came back in
    // that language, so an ASCII comma in front of a Persian name is the same
    // seam this used to have between two half-sentences.
    if (aiPhrase != null && aiPhrase.isNotEmpty) {
      if (name == null) return aiPhrase;
      final comma = nexDirectionOf(name) == TextDirection.rtl ? '،' : ',';
      return '$aiPhrase$comma $name';
    }
    return name == null ? nexUnnamedGreeting(text[v]) : text[v](name);
  }
}

/// A greeting written with a slot for a name, said without one.
///
/// The slot goes, and the comma before it: "Still up?", not "Still up, ?".
/// A marker rather than an empty string, because the slot is not always last
/// — two of the phrasings in each language end in a question mark, and only
/// a trailing comma used to be taken off.
String nexUnnamedGreeting(String Function(String name) phrase) =>
    phrase('\u0000').replaceFirst(RegExp('[,،]?\\s*\u0000'), '').trim();
