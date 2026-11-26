part of '../timeline_screen.dart';

bool _sameBriefDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

extension _TimelineAiBrief on TimelineScreenState {
  Future<void> _askAiSummary({required bool force}) async {
    await _briefCommitmentsReady;
    if (!mounted) return;
    force = force || _aiSummaryManualRequested;
    final prefs = widget.preferences;
    if (!_briefAvailable || (!force && !prefs.showDaySummary)) return;
    _briefPasses++;
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
    // The library's own candidate set, before anything is built from it: the
    // source, the report and the fingerprint below all read this pass's
    // copy, not whatever the last pass happened to leave in the field.
    _briefCandidates = await widget.services.briefCandidates();
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
        () => _aiSummaryText = prefs.currentAiBrief ?? _notesOnlyBrief(),
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
    //
    // The semantic pairs are the library's own embeddings' judgement about
    // which candidates are one subject — read locally for the styles that
    // hand a ledger to a model; the report style asks nobody, so it does not
    // pay for the read.
    final semanticPairs = prefs.briefStyle.usesModel
        ? await widget.services.briefSemanticPairs([
            for (final note in briefNotes) note.id,
          ])
        : const <({String a, String b})>[];
    if (!mounted) return;
    final attention = nexAttention(
      briefNotes,
      commitments: _model.commitments,
      now: DateTime.now(),
      semanticPairs: semanticPairs,
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
        canPersist: () async {
          if (!mounted || settings != _briefSettingsSignature()) return false;
          final current = await widget.services.briefCandidates();
          if (!mounted || settings != _briefSettingsSignature()) return false;
          // The timeline may not have delivered a write outside its window.
          // Compare every eligible candidate, not only the selected lines.
          final revisions = {
            for (final note in _briefCandidates) note.id: note.rev,
          };
          if (current.length != revisions.length ||
              current.any((note) => revisions[note.id] != note.rev)) {
            _briefCandidates = current;
            return false;
          }
          if (includesHabits) {
            final latest = await widget.services.habitsForBrief();
            if (!mounted || latest.source != _habitBriefSource) return false;
          }
          return mounted &&
              settings == _briefSettingsSignature() &&
              fingerprint == _briefFingerprint();
        },
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
      if (!mounted || settings != _briefSettingsSignature()) return;
      // The library moved while the answer was in flight. Its words describe
      // a state that no longer exists — a deleted note, a reminder that has
      // since been met, a day that has turned — so they are not applied. The
      // local lines are already on screen and the cache will be asked again
      // under the new fingerprint.
      if (fingerprint != _briefFingerprint()) return;
      if (result.updated) unawaited(widget.widgets?.refresh());
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
}
