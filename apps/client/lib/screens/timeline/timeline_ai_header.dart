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

  /// Fetches (or restores) the recap. Called on every timeline delivery; what
  /// keeps that from being a provider call per keystroke is [_recapIsStale].
  ///
  /// Silently does nothing when AI is off or unconfigured: this panel is
  /// additive chrome, never a reason to show an error on the app's home
  /// screen. A failed or empty reply leaves the card's empty line showing.
  ///
  /// [force] skips the cache — it is what the card's refresh button does.
  /// Without it, tapping refresh on a day whose text was already stored would
  /// have re-read the same string and looked broken.
  /// Asks for the brief, or — when one is already being written — waits for
  /// that one.
  ///
  /// A pull used to be dropped outright while any brief was in flight. With
  /// the token ceiling lifted, the one asked for on launch had no time limit
  /// either, and a model that thinks before answering kept it in flight for
  /// minutes: every pull in that time did nothing at all, and the card
  /// looked as if it could not be refreshed by hand.
  Future<void> _loadAiSummary({bool force = false}) async {
    final running = _aiSummaryInFlight;
    if (running != null) {
      final before = _aiSummaryText;
      await running;
      // The one waited for came back with nothing new — usually the quiet
      // launch-time kind, which never says it failed: the pull still gets
      // its own, which does.
      if (!force || !mounted || _aiSummaryText != before) return;
      if (_aiSummaryInFlight != null) return _aiSummaryInFlight;
    }
    final work = _askAiSummary(force: force);
    _aiSummaryInFlight = work;
    return work.whenComplete(() {
      if (identical(_aiSummaryInFlight, work)) _aiSummaryInFlight = null;
    });
  }

  Future<void> _askAiSummary({required bool force}) async {
    final prefs = widget.preferences;
    if (!_aiHeaderAvailable) return;
    // Switched off means no request at all, not a request whose answer is
    // hidden: the card used to be written in the background while turned
    // off, spending tokens on text nobody could see (1.94.0). A refresh
    // asked for by name — the recap widget's button — still runs.
    if (!force && !prefs.showDaySummary) return;
    final today = _aiSummaryDateKey();
    // Whatever is on file goes up first, stale or not. A recap from this
    // morning is worth reading while a newer one is being written, and it is
    // certainly worth more than an empty card.
    final cached = CloudAIAdapter.cleanDecorativeReply(prefs.aiDaySummaryText);
    if (mounted &&
        cached != null &&
        cached.isNotEmpty &&
        cached != _aiSummaryText) {
      _rebuild(() => _aiSummaryText = cached);
    }
    final source = _aiRecapSource();
    if (source.isEmpty) return;
    final style = prefs.briefStyle;
    // Counted off the source rather than off the library — what the brief is
    // allowed to say follows what it was actually given — and then held to
    // whatever the reader asked for. The two are a floor and a ceiling, not
    // two opinions: a quiet day is short under "long", and a busy one does
    // not overflow under "short".
    final budget = nexBriefLines(
      '\n'.allMatches(source).length + 1,
    ).clamp(1, prefs.briefLength.lines);
    // What the app knows for itself. Written before anything is asked of
    // anybody, and under `report` it is the entire brief — which is why that
    // style needs no provider, no key and no signal.
    final written = style.statesFacts
        ? nexBriefReport(
            nexBriefFacts(
              _model.all ?? _model.notes,
              commitments: _model.commitments,
            ),
            AppLocalizations.of(context),
            // One line kept back for the model to answer with, under the two
            // styles that ask it for one.
            maxLines: style.usesModel ? (budget - 1).clamp(1, budget) : budget,
          )
        : null;
    if (!style.usesModel) {
      if (!mounted) return;
      _rebuild(() {
        _aiSummaryLoading = false;
        if (written != null && written.isNotEmpty) _aiSummaryText = written;
      });
      // Deliberately not filed and not pushed to the widget. This one is
      // rebuilt from the database every time the timeline moves, costs
      // nothing, and is never stale — storing it would only give the home
      // screen an older copy of something it can have fresh.
      _refreshDailyNudge();
      return;
    }
    // The settings that shape the brief are part of what it was made from,
    // exactly as the notes are. Without them on file, changing the style, the
    // tone, the length or the language left yesterday's brief on the card
    // until somebody happened to write a note — the setting appeared to do
    // nothing, because nothing asked for a new brief.
    //
    // The headline beside this one has always keyed its cache on the language
    // and so came back in English the moment it was chosen; the brief did
    // not, which is how an English greeting ended up sitting over a Persian
    // brief on the same screen.
    final fingerprint = TimelineScreenState.recapFingerprint(
      nexBriefSignature(
        source: source,
        style: style,
        tone: prefs.briefTone,
        length: prefs.briefLength,
        language: prefs.aiOutputLanguage,
        instruction: prefs.briefInstruction,
      ),
    );
    if (!force && !_recapIsStale(fingerprint)) return;
    if (mounted) _rebuild(() => _aiSummaryLoading = true);
    final adapter = _aiAdapter();
    String? text;
    // Kept apart from `text`, because under the styles that state their own
    // facts a failed request still leaves something on the card — and a tap
    // that quietly half-worked is the same broken control as one that did
    // nothing at all.
    var refused = false;
    try {
      final answer = await adapter.digest(
        source,
        lines: budget,
        style: style,
        tone: prefs.briefTone,
        instruction: prefs.briefInstruction,
        written: written ?? '',
        // A tap gets the full budget; the one that runs itself on launch does
        // not. On a network that is joined but not connected, ninety seconds
        // of spinner at the top of the timeline is what "the app loads slowly"
        // turns out to mean.
        // With the ceiling lifted the model is one that thinks first, and
        // twenty seconds is rarely enough for it even on launch.
        //
        // Never unbounded, though: a brief that never comes back holds the
        // card's spinner, and every pull behind it, for as long as it hangs.
        timeout: force
            ? const Duration(minutes: 5)
            : prefs.aiSummaryUnlimited
            ? const Duration(minutes: 3)
            : CloudAIAdapter.ambientTimeout,
      );
      // The app's lines stand whether or not the model answered. That is the
      // point of stating them separately: a brief that loses the rent being
      // overdue because a request timed out is a brief that cannot be relied
      // on for the one thing it is for.
      text = [
        if (written != null && written.isNotEmpty) written,
        if (answer != null && answer.isNotEmpty) answer,
      ].join('\n');
      if (text.isEmpty) text = null;
      refused = answer == null || answer.isEmpty;
    } catch (_) {
      text = written;
      refused = true;
    } finally {
      adapter.close();
    }
    if (!mounted) return;
    _rebuild(() {
      _aiSummaryLoading = false;
      // A failed refresh keeps whatever was already on screen. Blanking a
      // recap that is still perfectly readable because the network dropped
      // would be the tap actively destroying something.
      if (text != null && text.isNotEmpty) _aiSummaryText = text;
    });
    // Keeping the old line is right; saying nothing about the *tap* is not —
    // silence is what a broken button looks like. A quiet banner says the
    // refresh did not happen, and the old text stays.
    //
    // Only for the tap. This also runs once by itself, the first time the
    // timeline delivers any notes, and there the banner was an error nobody
    // asked for: it arrived seconds after launch, over whatever screen the
    // user had opened by then, about a card they may not even have looked at.
    // This method's own rule at the top says why that is wrong — the panel is
    // additive chrome, never a reason to show an error. A failure with no tap
    // behind it leaves yesterday's recap on the card and says nothing.
    if (force && (refused || text == null || text.isEmpty)) {
      if (!mounted) return;
      NexBannerHost.of(context)?.show(
        message: AppLocalizations.of(context).recapRefreshFailed,
        kind: NexBannerKind.failed,
      );
    }
    if (text != null && text.isNotEmpty) {
      unawaited(
        prefs
            .setAiDaySummary(
              text: text,
              dateKey: today,
              at: DateTime.now(),
              source: fingerprint,
            )
            // After it is on file, not before: the bridge reads the
            // preference rather than being handed the string, so pushing
            // first would write the snapshot from the old brief. This is the
            // whole of how a new recap reaches the home screen — the recap
            // is filed without notifying listeners, so nothing else would.
            .then((_) => widget.widgets?.refresh()),
      );
    }
    _refreshDailyNudge();
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
    // A renamed user changes the greeting's language mid-day, so the day key
    // alone is not enough to decide the cached line still fits beside it.
    if (!force &&
        prefs.aiHeadlineDate == today &&
        prefs.aiHeadlineLang == langKey) {
      final cached = CloudAIAdapter.cleanDecorativeReply(prefs.aiHeadlineText);
      if (mounted && cached != null && cached.isNotEmpty) {
        _rebuild(() => _aiHeadlineText = cached);
        return;
      }
    }
    if (mounted) _rebuild(() => _aiHeadlineLoading = true);
    final adapter = _aiAdapter();
    String? text;
    try {
      // Unlike the recap, an empty library is not a reason to skip this: the
      // line is a mood, and "you have not written anything yet" is a mood the
      // prompt handles on its own.
      text = await adapter.headline(
        _aiHeadlineSource(),
        language: language,
        // Same rule as the recap: a tap waits, a launch does not — unless
        // the ceiling is lifted for a model that thinks first.
        timeout: force || widget.preferences.aiSummaryUnlimited
            ? null
            : CloudAIAdapter.ambientTimeout,
      );
    } catch (_) {
      text = null;
    } finally {
      adapter.close();
    }
    if (!mounted) return;
    _rebuild(() {
      _aiHeadlineLoading = false;
      if (text != null && text.isNotEmpty) _aiHeadlineText = text;
    });
    if (text != null && text.isNotEmpty) {
      unawaited(prefs.setAiHeadline(text: text, dateKey: today, lang: langKey));
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
  }

  String _aiSummaryDateKey() =>
      NexPreferences.daySummaryDateKey(DateTime.now());

  bool _recapIsStale(String fingerprint) =>
      TimelineScreenState.recapNeedsRefresh(
        at: widget.preferences.aiDaySummaryAt,
        text: CloudAIAdapter.cleanDecorativeReply(
          widget.preferences.aiDaySummaryText,
        ),
        storedSource: widget.preferences.aiDaySummarySource,
        fingerprint: fingerprint,
        now: DateTime.now(),
      );

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
  String _aiHeadlineSource() {
    final recent = (_model.all ?? _model.notes).take(20);
    final lines = <String>[
      for (final note in recent)
        (note.content ?? note.transcriptText ?? note.ocrText ?? '').trim(),
    ]..removeWhere((line) => line.isEmpty);
    return lines.join('\n');
  }

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
  String _aiRecapSource() => nexRecapSource(
    _model.all ?? _model.notes,
    commitments: _model.commitments,
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
    if (delivered.isEmpty) return;
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
        strength: _aiSummaryLoading ? 0.4 : 0.25,
        active: !_aiSummaryCollapsed,
        token: _aiSummaryLoading ? '…' : _aiSummaryText,
        child: NexGlassSurface(
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
    return name == null
        ? text[v]('').replaceFirst(RegExp(r'[,،]\s*$'), '').trim()
        : text[v](name);
  }
}
