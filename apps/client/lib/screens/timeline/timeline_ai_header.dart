/// The moment the greeting on screen belongs to: this day, this part of it,
/// this language. The one reading of the clock the whole line is built from.

part of '../timeline_screen.dart';

/// The greeting, the AI headline and recap, and the daily brief card.
extension _TimelineAiHeader on TimelineScreenState {
  /// The cache may be updated without changing any note (for example by an
  /// external summary writer). A no-op timeline delivery is still its signal.
  /// Compare the cached text before doing work; never rebuild all note cards.
  void _refreshExternalBriefIfChanged() {
    if (!mounted) return;
    // Only a model-written brief *is* the cache. The report style recomputes
    // its lines from the library on every pass, so a cache written behind its
    // back is not its business: comparing the two asks for a reload on every
    // no-op delivery, forever, without either side ever converging.
    if (!widget.preferences.briefStyle.usesModel) return;
    final cached = CloudAIAdapter.cleanDecorativeReply(
      widget.preferences.aiDaySummaryText,
    );
    if (cached != null && cached.isNotEmpty && cached != _aiSummaryText) {
      unawaited(_loadAiSummary());
    }
  }

  void _onBriefPreferencesChanged() {
    if (!mounted || _briefPreferencesQueued) return;
    _briefPreferencesQueued = true;
    _fadeOnViewChange();
    // The timeline owns its preference-driven content (including the local
    // greeting and home layout); it no longer relies on rebuilding MaterialApp.
    _rebuild(() {});
    // Let the app apply locale/settings dependencies before capturing input.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _briefPreferencesQueued = false;
      if (!mounted) return;
      if (!widget.preferences.briefHabitsAllowed &&
          (widget.preferences.aiDaySummaryIncludesHabits ||
              _aiSummaryHasHabits)) {
        _aiSummaryHasHabits = false;
        _rebuild(
          () => _aiSummaryText =
              widget.preferences.currentAiBrief ?? _notesOnlyBrief(),
        );
      }
      // Settings save while typing. Apply the final choice on return instead
      // of spending a request on each edit to a custom instruction.
      if (!_routeIsCurrent) return;
      final settings = _briefSettingsSignature();
      final changed =
          _briefSettingsKey != null && _briefSettingsKey != settings;
      _briefSettingsKey = settings;
      // Only a change to the brief's own settings, or the card being turned
      // back on, is a reason to rebuild it.
      //
      // This listener fires for *every* preference write: a theme choice, a
      // card size, the list/grid switch. Running the pass for all of them
      // meant a layout toggle spent the habits read, the candidate library
      // and the attention engine on the frame after the switch — the layout
      // switch was blamed on the crossfade. An ordinary data change reaches
      // the brief through `_briefReload`, which is also where a burst of
      // writes is coalesced.
      final shown = widget.preferences.showDaySummary;
      final turnedOn = shown && !_daySummaryShown;
      _daySummaryShown = shown;
      if (!changed && !turnedOn) return;
      // A settings change is explicit, unlike an hourly data refresh.
      unawaited(_loadAiSummary(force: changed));
      unawaited(_loadAiHeadline());
    });
  }

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
  ///
  /// [manual] is a user gesture — the pull-to-refresh — and is the only thing
  /// that marks the flight manual. A settings change forces the same request
  /// for its own reasons, and marking *that* manual once sent the report
  /// style, which never asks a provider, around the completion handler's
  /// escalation loop forever.
  Future<void> _loadAiSummary({bool force = false, bool manual = false}) {
    // This pass reads the library as it is now, so a queued one would
    // repeat the same read.
    _briefReload?.cancel();
    _briefReload = null;
    if (manual) _aiSummaryManualRequested = true;
    final pending = _aiSummaryInFlight;
    if (pending != null) return pending;
    _habitBriefDirty = false;
    _aiSummaryFlightAsked = false;
    final settings = _briefSettingsSignature();
    final work = _askAiSummary(force: force);
    final flight = work.whenComplete(() {
      _aiSummaryInFlight = null;
      // A manual pull that joined this flight after it had already decided
      // not to ask — the window between the request decision and this line —
      // must not read as a completed refresh of nothing. One more pass,
      // forced, is what the pull asked for; when the flight did ask, the
      // pull got its words and nothing more is spent. Only a style that
      // asks anybody anything can be re-asked — the report style's pull is
      // answered by its own recomputation above — and the retry itself is
      // not manual, so a brief that still cannot ask ends the chain here.
      final manualJoined = _aiSummaryManualRequested;
      _aiSummaryManualRequested = false;
      if (mounted) {
        if (settings != _briefSettingsSignature()) {
          // Finish the old request before asking once with the latest choice.
          if (_routeIsCurrent) {
            unawaited(_loadAiSummary(force: true));
          }
        } else if (manualJoined &&
            !_aiSummaryFlightAsked &&
            widget.preferences.briefStyle.usesModel) {
          unawaited(_loadAiSummary(force: true));
        } else if (_habitBriefDirty) {
          unawaited(_loadAiSummary());
        } else {
          _armBriefRefresh();
        }
      }
    });
    _aiSummaryInFlight = flight;
    return flight;
  }

  bool get _briefForeground {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  void _armBriefRefresh() {
    _aiSummaryWake?.cancel();
    final prefs = widget.preferences;
    if (!_briefAvailable || !prefs.showDaySummary || !_briefForeground) return;
    // One build of the source answers both questions: whether there is
    // anything to describe, and (through the fingerprint) whether what is
    // on file was written from it. The fingerprint variant carries the same
    // lines as the readable one, so its emptiness is the same emptiness.
    final source = _briefFingerprintSource();
    if (source.trim().isEmpty) return;
    final fingerprint = TimelineScreenState.recapFingerprint(
      _briefSignatureBody(source),
    );
    final now = DateTime.now();
    DateTime? wakeAt;
    // Two reasons to wake, and they are different questions. The first is
    // that the words on file were written from something else — a capture, a
    // tick, a setting. Only a style that asks anybody can act on it, and the
    // retry is bounded by the cooldown, so a failure cannot spin here.
    if (_aiHeaderAvailable && prefs.briefStyle.usesModel) {
      final stale =
          prefs.aiDaySummarySource != fingerprint || !prefs.aiDaySummaryFresh;
      if (stale) {
        final next = widget.services.briefRefresh.nextAllowedAt();
        wakeAt = next.isAfter(now) ? next : now;
      }
    }
    // The second is that nothing was written at all since the words were:
    // the clock has moved past a fact they state, and no write will announce
    // it. Every style needs this one — the report's own lines say "today at
    // 11:20" until something asks them again — which is why it is armed
    // outside the model branch above.
    final boundary = _briefBoundary;
    if (boundary != null &&
        boundary.isAfter(now) &&
        (wakeAt == null || boundary.isBefore(wakeAt))) {
      wakeAt = boundary;
    }
    if (wakeAt == null) return;
    var wait = wakeAt.difference(now);
    // A timer that fires a hair before its own boundary would compute the
    // same boundary again; a second is enough to have moved past it.
    if (wait < const Duration(seconds: 1)) wait = const Duration(seconds: 1);
    _aiSummaryWake = Timer(wait, () {
      if (mounted) unawaited(_loadAiSummary());
    });
  }

  NexGreetingMoment get _greetingMoment =>
      nexGreetingMomentAt(DateTime.now(), language: _headlineLanguage.wireName);

  /// The model's phrase for the current moment, or null when the cached and
  /// in-memory phrases belong to another one.
  ///
  /// Called from build, so it has to be synchronous and cheap: two map reads
  /// and a validation of at most ninety characters. It is also the last line
  /// of defence for the bug this step exists for — even if a timer is missed
  /// and the cache is old, a night phrase is not shown in the morning.
  String? _greetingPhrase() {
    final moment = _greetingMoment;
    if (_aiHeadlineMoment == moment.key &&
        nexGreetingFits(_aiHeadlineText, moment: moment)) {
      return _aiHeadlineText!.trim();
    }
    final prefs = widget.preferences;
    final cached = prefs.aiHeadlineText;
    if (prefs.aiHeadlineDate == moment.dateKey &&
        prefs.aiHeadlinePart == moment.part.wireName &&
        prefs.aiHeadlineLang == moment.language &&
        nexGreetingFits(cached, moment: moment)) {
      return cached!.trim();
    }
    return null;
  }

  /// Arms one timer for the next boundary (05:00, 12:00, 17:00, 23:00 or
  /// midnight) and re-arms itself from the handler.
  ///
  /// One timer, not a periodic tick: the line changes at four moments a day,
  /// and a minute-by-minute wake-up to find that out would cost more than the
  /// greeting is worth.
  void _scheduleGreetingRollover() {
    _greetingRollover?.cancel();
    final now = DateTime.now();
    final next = nexGreetingBoundaries(now).firstWhere(
      (at) => at.isAfter(now),
      orElse: () => now.add(const Duration(hours: 1)),
    );
    _greetingRollover = Timer(next.difference(now), () {
      if (!mounted) return;
      _onGreetingMomentChanged();
      _scheduleGreetingRollover();
    });
  }

  /// The day or the part of it has turned: stale words go now, the local
  /// phrasing holds the line, and a phrase for the new moment is asked for.
  void _onGreetingMomentChanged() {
    final moment = _greetingMoment;
    if (_aiHeadlineMoment != null && _aiHeadlineMoment != moment.key) {
      _rebuild(() {
        _aiHeadlineText = null;
        _aiHeadlineMoment = null;
      });
    }
    unawaited(_loadAiHeadline());
  }

  /// The headline over the timeline. Same shape as [_loadAiSummary] — cached
  /// per moment, forced by a tap on the line itself.
  Future<void> _loadAiHeadline({bool force = false}) async {
    final prefs = widget.preferences;
    if (!_aiHeaderAvailable) return;
    // Drawn only beside the greeting; with the greeting hidden it is not
    // asked for.
    if (!force && !prefs.showGreeting) return;
    final moment = _greetingMoment;
    // This moment's phrase is already on screen — from the cache or from the
    // last answer. Asking again would rebuild the line to say the same thing.
    if (!force && _greetingPhrase() != null) return;
    final language = _headlineLanguage;
    final langKey = language.wireName;
    if (_aiHeadlineLoading) return;
    _rebuild(() => _aiHeadlineLoading = true);
    try {
      final text = await widget.services.briefRefresh.headline(
        dateKey: moment.dateKey,
        part: moment.part.wireName,
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
                portrait: _portraitHint(),
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
      // The answer is only this request's answer if the clock still says so.
      // A phrase for 22:00 that lands at 00:05 is not a greeting for now, and
      // a language change rewrites the line just as completely.
      if (mounted && moment == _greetingMoment) {
        // A greeting kept from before 2.8.6 may have been cut off with an
        // ellipsis; a phrase that names another part of the day is just as
        // unusable, and the app's own line stands in for it.
        final clean = CloudAIAdapter.cleanDecorativeReply(text);
        final phrase = nexGreetingFits(clean, moment: moment)
            ? clean!.trim()
            : null;
        _rebuild(() {
          _aiHeadlineText = phrase;
          _aiHeadlineMoment = phrase == null ? null : moment.key;
        });
      }
    } finally {
      if (mounted) {
        _rebuild(() => _aiHeadlineLoading = false);
        if (moment != _greetingMoment) unawaited(_loadAiHeadline());
      }
    }
  }

  /// The writing portrait in a line, for the greeting to know who it greets:
  /// its headline and the traits that score highest. The provider wrote it
  /// from the notes before, so nothing new leaves the device for it.
  String? _portraitHint() {
    final portrait = widget.preferences.profilePortrait;
    if (portrait == null) return null;
    final traits = [...portrait.traits]
      ..sort((a, b) => b.score.compareTo(a.score));
    return [
      portrait.headline,
      if (traits.isNotEmpty) traits.take(3).map((t) => t.name).join(', '),
    ].where((part) => part.trim().isNotEmpty).join('. ');
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
        // The hold's own _tick (onHoldStart) already spoke; a second buzz on
        // the same gesture is noise.
        haptics: false,
        message: l10n.assistantNeedsIntelligence,
        actionLabel: l10n.assistantTurnOnIntelligence,
        onAction: () => unawaited(_openIntelligence()),
      );
      return;
    }
    // No buzz here (F-09): the hold's own tick at the glow's start already
    // spoke for this gesture, and the glow-to-sheet handoff confirms the
    // trigger visually — a second haptic ~250ms after the first is noise.
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
  /// Awaited, and the timeline rebuilds on the way back — but only when the
  /// intelligence settings actually moved: turning intelligence on is
  /// exactly the change that makes the button this came from start doing
  /// something else, and a real change rebuilds through the preferences
  /// listener and [didPopNext] as well. A visit that changed nothing must
  /// not repaint every card mid pop-transition.
  Future<void> _openIntelligence() async {
    final before = _briefSettingsSignature();
    await Navigator.push(
      context,
      NexPageRoute<void>(
        builder: (_) => IntelligenceScreen(
          services: widget.services,
          preferences: widget.preferences,
        ),
      ),
    );
    if (mounted && _briefSettingsSignature() != before) _rebuild(() {});
  }

  void _toggleAiSummary() {
    _tick();
    _rebuild(() {
      _aiSummaryCollapsed = !_aiSummaryCollapsed;
      _aiSummaryBeamPending = !_aiSummaryCollapsed;
      if (!_aiSummaryCollapsed) _aiSummaryExpansion++;
    });
    unawaited(widget.preferences.setDaySummaryFolded(_aiSummaryCollapsed));
  }

  String _aiSummaryDateKey() =>
      NexPreferences.daySummaryDateKey(DateTime.now());

  /// Rebuilds the local daily plan and certifies only a newly written,
  /// source-matched summary for optional reuse. This never requests AI.
  void _refreshDailyNudge({bool freshlyGeneratedSummary = false}) {
    if (!mounted || !widget.preferences.dailyNudge) return;
    unawaited(
      DailyNudge.apply(
        services: widget.services,
        freshlyGeneratedSummary: freshlyGeneratedSummary,
      ),
    );
  }

  /// The most recent notes' own text, newest first, under one character
  /// budget — see [nexHeadlineSource].
  ///
  /// The headline's source, and only the headline's. That line is a mood —
  /// it wants to know roughly what someone has been writing about and
  /// nothing else, and telling it what is due would turn a greeting into a
  /// second recap. The count and the per-note cut are derived from what is
  /// actually there: a few notes are read deeply, a busy morning broadly,
  /// and the walk stops when the budget is spent rather than at a fixed
  /// twentieth note.
  String _aiHeadlineSource() =>
      nexHeadlineSource(_headlineRawTexts())
          .map((entry) => entry.line)
          .join('\n');

  /// The notes the headline reads: exactly the ones its source carries, for
  /// the disclosure log.
  Iterable<Note> _aiHeadlineNotes() {
    final notes = (_model.all ?? _model.notes).toList();
    return [
      for (final entry in nexHeadlineSource(_headlineRawTexts()))
        notes[entry.index],
    ];
  }

  List<String> _headlineRawTexts() => [
    for (final note in (_model.all ?? _model.notes))
      (note.content ?? note.transcriptText ?? note.ocrText ?? '').trim(),
  ];

  /// The recap's source: the library's state, not a slice of its prose.
  ///
  /// Everything the recap can say about what is due or unfinished comes from
  /// here — see [nexRecapSource], which sizes its own budget from what is
  /// waiting. The whole candidate set goes in rather than a pre-cut slice,
  /// because the choosing is the part that matters and it needs everything
  /// to choose from — see [_briefLibrary], which reads the library itself
  /// rather than the timeline's window.
  /// The standing obligations, as the brief last saw them.
  ///
  /// Held in a field rather than read inside [_aiRecapSource], because that
  /// method is synchronous and is called to *decide whether* to ask the model
  /// — a database read there would make the staleness check asynchronous and
  /// put a query on a path that mostly concludes "nothing has changed". They
  /// are refreshed when the screen loads and whenever the commitments screen
  /// closes, which is every moment they can have changed.
  String _aiRecapSource({bool forFingerprint = false, List<Note>? notes}) =>
      nexRecapSource(
        notes ?? _model.all ?? _model.notes,
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
    // The recap is deliberately not asked for here.
    //
    // Every delivery already arms the screen's trailing pass — see
    // `_onModelChange` and `_briefReload`. Calling `_loadAiSummary` here
    // started a full pass reading the library on the delivery's own frame and
    // *cancelled* that timer before it could fire, so 2.9.1's "one pass after
    // a burst of writes" never happened: a delete paid for the habits read,
    // the candidate library, the attention engine and the report lines while
    // its Undo notice was still arriving, which is the jank the notice got
    // the blame for. The pass still keeps up with the day through the timer.
    // The headline is not. It is a mood for the day with a day key of its
    // own, and re-rolling it on every capture would make the top of the
    // screen restless.
    if (_aiSummaryRequested) return;
    _aiSummaryRequested = true;
    _scheduleGreetingRollover();
    unawaited(_loadAiHeadline());
  }

  String _notesOnlyBrief() {
    final lines = nexBriefReportLines(
      nexBriefFacts(_briefLibrary(), commitments: _model.commitments),
      AppLocalizations.of(context),
      maxLines: widget.preferences.briefLength.lines,
      maxWords: widget.preferences.briefLength.words,
      notes: _briefLibrary(),
      clock: (local) => nexDueClock(context, local),
    );
    _rememberBriefLines(lines);
    return lines.map((line) => line.text).join('\n');
  }

  /// Keeps which note each line the app wrote is about, so the card can open
  /// it. Added to rather than replaced: a brief on file from a moment ago
  /// still has its lines on screen while the next one is worked out.
  void _rememberBriefLines(List<NexBriefLine> lines) {
    if (_briefLineNotes.length > 64) _briefLineNotes.clear();
    for (final line in lines) {
      if (line.noteId case final id?) _briefLineNotes[line.text] = id;
    }
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

    // Greeted in the app's language, whatever script the name is in
    // (2.4.0): the line belongs to the interface, and a name is one word in
    // it.
    final l10n = interface;
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
    // A comma in the interface's script — the phrase came back in that
    // language.
    if (aiPhrase != null && aiPhrase.isNotEmpty) {
      if (name == null) return aiPhrase;
      final comma = Localizations.localeOf(context).languageCode == 'fa'
          ? '،'
          : ',';
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
