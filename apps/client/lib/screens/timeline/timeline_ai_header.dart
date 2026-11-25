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
              widget.preferences.aiDaySummaryText ?? _notesOnlyBrief(),
        );
      }
      // Settings save while typing. Apply the final choice on return instead
      // of spending a request on each edit to a custom instruction.
      if (!_routeIsCurrent) return;
      final settings = _briefSettingsSignature();
      final changed =
          _briefSettingsKey != null && _briefSettingsKey != settings;
      _briefSettingsKey = settings;
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

  static bool _sameBriefDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _askAiSummary({required bool force}) async {
    await _briefCommitmentsReady;
    if (!mounted) return;
    force = force || _aiSummaryManualRequested;
    final prefs = widget.preferences;
    if (!_briefAvailable || (!force && !prefs.showDaySummary)) return;
    final usesModel = prefs.briefStyle.usesModel;
    final cached = CloudAIAdapter.cleanDecorativeReply(prefs.aiDaySummaryText);
    // A model's brief is about the day it was written for. Yesterday's words
    // describe a day that is over, and the arithmetic beside them has moved
    // on, so they are not adopted — and, if they are the ones on screen, they
    // are taken down rather than left to outlive their date.
    final cachedAt = prefs.aiDaySummaryAt;
    // Today's, and not past the moment its facts moved. The second half is
    // what 2.9.0 added: a brief written at ten that says nothing is overdue
    // is false at eleven past an item's time, and no write accompanies that.
    final cacheIsToday =
        cachedAt != null &&
        _sameBriefDay(cachedAt, DateTime.now()) &&
        prefs.aiDaySummaryFresh;
    // The cache is a model-written brief, and only that: the report style
    // writes its own lines from the library on the next few lines of this
    // very pass, so adopting a stale cache first would paint a brief that
    // is about to be replaced — and on a library too quiet for a report
    // would leave an old model's words standing in for arithmetic.
    if (mounted &&
        usesModel &&
        cacheIsToday &&
        cached != null &&
        cached.isNotEmpty &&
        cached != _aiSummaryText) {
      _rebuild(() {
        _aiSummaryText = cached;
        _aiSummaryHasHabits =
            prefs.aiDaySummaryIncludesHabits && prefs.briefHabitsAllowed;
      });
    } else if (mounted &&
        usesModel &&
        !cacheIsToday &&
        _aiSummaryText != null &&
        _aiSummaryText == cached) {
      _rebuild(() => _aiSummaryText = null);
    }
    final habits = await widget.services.habitsForBrief();
    if (!mounted) return;
    // The notes beyond the window, before anything is built from them: the
    // source, the report and the fingerprint below all read this pass's
    // copy, not whatever the last pass happened to leave in the field.
    _briefWaitingNotes = await widget.services.briefWaitingNotes();
    if (!mounted) return;
    final briefNotes = _briefLibrary();
    // A manual pull may have joined while the habits and the waiting notes
    // were being read — before the request decision below, so still in
    // time to be honoured by it.
    force = force || _aiSummaryManualRequested;
    _habitBriefSource = prefs.briefHabitsAllowed ? habits.source : '';
    final includesHabits = _habitBriefSource.isNotEmpty;
    final habitText = includesHabits
        ? habits.localText(
            AppLocalizations.of(context),
            includeCompleted: prefs.briefStyle == NexBriefStyle.report,
            maxWords: prefs.briefLength.words,
          )
        : '';
    if (!prefs.briefHabitsAllowed && prefs.aiDaySummaryIncludesHabits) {
      _rebuild(
        () => _aiSummaryText = prefs.aiDaySummaryText ?? _notesOnlyBrief(),
      );
    }
    final notesSource = _aiRecapSource(notes: briefNotes);
    final source = [
      notesSource,
      if (includesHabits) _habitBriefSource,
    ].where((s) => s.isNotEmpty).join('\n');
    if (source.isEmpty) {
      // Nothing left to describe — the library was emptied, the permission
      // turned off, the window cleared. A model's brief about a library that
      // no longer exists is exactly the stale claim that must not survive: it
      // is cleared here rather than left standing until the next refresh.
      if (mounted && (_aiSummaryText ?? '').isNotEmpty) {
        _rebuild(() {
          _aiSummaryText = null;
          _aiSummaryHasHabits = false;
        });
      }
      return;
    }
    // One reading of the library, shared with the daily nudge, and the
    // ledger the model is held to. The statuses are computed here rather
    // than inferred from the lines, so "due later today" can never come back
    // as "done" or "overdue".
    final attention = nexAttention(
      briefNotes,
      commitments: _model.commitments,
      now: DateTime.now(),
    );
    final statusLedger = nexAttentionLedger(attention);
    // The next instant these facts change without a row being written. Stored
    // with the answer below and used to wake the card by itself.
    _briefBoundary = nexAttentionNextBoundary(attention);
    // Which notes the brief is written from, for the log of what left the
    // phone: it used to name none (1.99.96 reviews, SEC-01).
    final sourceNotes = nexRecapNoteIds(
      briefNotes,
      commitments: _model.commitments,
    );
    final style = prefs.briefStyle;
    final length = prefs.briefLength;
    final budget = nexBriefLines(
      '\n'.allMatches(source).length + 1,
      ceiling: length.lines,
    );
    final writtenBudget = style.usesModel
        ? (budget - 1).clamp(1, budget)
        : budget;
    final habitLines = habitText.isEmpty ? <String>[] : habitText.split('\n');
    // Spend the factual budget on notes in priority order first. Habit
    // progress may use spare room; it never reserves a row ahead of a note.
    final reportLines = style.statesFacts
        ? nexBriefReportLines(
            nexBriefFacts(briefNotes, commitments: _model.commitments),
            AppLocalizations.of(context),
            maxLines: writtenBudget,
            maxWords: length.words,
            notes: briefNotes,
            clock: (local) => nexDueClock(context, local),
          )
        : const <NexBriefLine>[];
    _rememberBriefLines(reportLines);
    final noteLines = [for (final line in reportLines) line.text];
    final written = style.statesFacts
        ? [
            ...noteLines,
            ...habitLines.take(
              (writtenBudget - noteLines.length).clamp(0, writtenBudget),
            ),
          ].join('\n')
        : null;
    if (!style.usesModel) {
      if (mounted) {
        _rebuild(() {
          _aiSummaryLoading = false;
          _aiSummaryHasHabits = includesHabits;
          _aiSummaryText = written ?? '';
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
    // `notesSource` again rather than a second pass over the library: the
    // question is only whether the model has anything to read, and the
    // answer was settled a moment ago.
    final language =
        prefs.aiOutputLanguage == AiOutputLanguage.auto && notesSource.isEmpty
        ? _headlineLanguage
        : prefs.aiOutputLanguage;
    final unlimited = prefs.aiSummaryUnlimited;
    final tone = prefs.briefTone;
    final instruction = prefs.briefInstruction;
    final settings = _briefSettingsSignature();
    if (mounted) _rebuild(() => _aiSummaryLoading = true);
    try {
      final result = await refresh.refresh(
        fingerprint: fingerprint,
        dateKey: _aiSummaryDateKey(),
        force: force,
        includesHabits: includesHabits,
        // Read by the cache only when habits were included; building the
        // local report is a walk over the library and is not spent on the
        // briefs that cannot use it.
        notesOnlyFallback: includesHabits ? _notesOnlyBrief() : null,
        validUntil: _briefBoundary,
        request: () async {
          // Marked before anything can fail: the flag says a provider was
          // asked, not that it answered.
          _aiSummaryFlightAsked = true;
          if (includesHabits && !prefs.briefHabitsAllowed) return null;
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
                includesHabits: includesHabits,
                lines: budget,
                style: style,
                tone: tone,
                instruction: instruction,
                written: written ?? '',
                statusLedger: statusLedger,
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
            // A brief that calls nothing overdue on a day that has an overdue
            // item, or the day clear while something is waiting, is worse than
            // no model line at all: the local facts already said it correctly.
            // Rejecting it here keeps it out of the cache, the widget and the
            // notification, and the retry interval absorbs the request.
            final violations = nexAttentionViolations(answer, attention);
            if (violations.isNotEmpty) {
              // The reason names the claim and the fact that refused it, so a
              // recurrence in the diagnostics can be read without guessing
              // which sentence was the problem.
              unawaited(
                NexCrashLog.failed(
                  'brief.contradiction',
                  '${violations.first}',
                ),
              );
              return null;
            }
            return [
              if (written != null && written.isNotEmpty) written,
              answer,
            ].join('\n');
          } finally {
            adapter.close();
          }
        },
      );
      _lastBriefRefreshFailed = result.failed;
      if (result.updated) unawaited(widget.widgets?.refresh());
      if (!mounted || settings != _briefSettingsSignature()) return;
      // The library moved while the answer was in flight. Its words describe
      // a state that no longer exists — a deleted note, a reminder that has
      // since been met, a day that has turned — so they are not applied. The
      // local lines are already on screen and the cache will be asked again
      // under the new fingerprint.
      if (fingerprint != _briefFingerprint()) return;
      // A failed refresh hands the old text back. When that text has expired
      // it is not adopted again: the local lines are the current truth, and
      // the words it would restore describe a moment that has passed.
      final usable = prefs.aiDaySummaryFresh;
      _rebuild(() {
        _aiSummaryText = usable
            ? (result.text ?? _aiSummaryText ?? written)
            : written;
        _aiSummaryHasHabits =
            usable &&
            prefs.aiDaySummaryIncludesHabits &&
            prefs.briefHabitsAllowed;
      });
      if ((force || _aiSummaryManualRequested) && result.failed) {
        NexBannerHost.of(context)?.show(
          message: AppLocalizations.of(context).recapRefreshFailed,
          kind: NexBannerKind.failed,
        );
      }
      _refreshDailyNudge(
        freshlyGeneratedSummary:
            result.updated && prefs.aiDaySummarySource == _briefFingerprint(),
      );
    } finally {
      if (mounted) _rebuild(() => _aiSummaryLoading = false);
    }
  }

  /// Which language the generated line has to be written in: the app's own.
  ///
  /// It used to follow the script of the user's name, so a Persian interface
  /// with a name typed in Latin letters opened with an English sentence
  /// (2.4.0). The line is part of the interface, and the name is only a word
  /// in it — "صبحت بخیر، Saeed" reads naturally; a whole English line in a
  /// Persian app does not.
  AiOutputLanguage get _headlineLanguage =>
      Localizations.localeOf(context).languageCode == 'fa'
      ? AiOutputLanguage.persian
      : AiOutputLanguage.english;

  /// The moment the greeting on screen belongs to: this day, this part of it,
  /// this language. The one reading of the clock the whole line is built from.
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
      // Capped like a recap line: the greeting is a mood, and a long note
      // takes the budget the nineteen others were meant to share — every
      // character of it a token on a provider the user is paying for, and
      // on a phone running a local model, context the request cannot fit.
      nexOneLine(
        (note.content ?? note.transcriptText ?? note.ocrText ?? '').trim(),
        160,
      );

  /// The recap's source: the library's state, not a slice of its prose.
  ///
  /// Everything the recap can say about what is due or unfinished comes from
  /// here — see [nexRecapSource], which also explains why the twenty newest
  /// notes were the wrong twenty. The whole set goes in rather than a
  /// pre-cut slice, because the choosing is the part that matters and it
  /// needs everything to choose from — see [_briefLibrary], which is more
  /// than the timeline's window.
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
    // The recap is allowed to re-ask. Its own gate decides whether the notes
    // have moved on and whether an hour has passed, so calling it on every
    // delivery costs a hash and buys a recap that keeps up with the day.
    unawaited(_loadAiSummary());
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
