part of '../timeline_screen.dart';

/// The list itself: the header, date groups, folding, pinch and
/// pull-to-refresh, and the filter sheet.
extension _TimelineBody on TimelineScreenState {
  /// Everything this screen shows, read again.
  ///
  /// The pull-down was meant to reveal the search field. It never did — the
  /// field turned out to sit at the top permanently, so there was nothing to
  /// pull in — and a gesture that does nothing is worse than no gesture. This
  /// is what a downward pull on a list means everywhere else, and it is also
  /// the manual escape hatch for anything that fails to refresh on its own.
  ///
  /// Syncing is part of it only when a server is configured, and its failure
  /// is reported without taking the local reload down with it: the notes on
  /// this device are the point, and they reloaded either way.
  Future<void> _refresh() async {
    final banner = NexBannerHost.of(context);
    final l10n = AppLocalizations.of(context);
    await Future.wait([
      widget.services.refreshTimeline(),
      _model.loadFilterTags(),
    ]);
    if (widget.preferences.syncBaseUrl == null) return;
    try {
      await widget.services.syncNow();
    } catch (error) {
      if (!mounted) return;
      banner?.show(
        message: '${l10n.syncFailed} (${NexServices.describeFailure(error)})',
        kind: NexBannerKind.failed,
      );
    }
  }

  /// The content filter, behind the mockup's icon button.
  Future<void> _pickFilters() async {
    final l10n = AppLocalizations.of(context);
    final chosen = await nexShowSheet<_FilterChoice>(
      context: context,
      // Scrollable, because the sheet's own body is `Flexible`: eight rows
      // fit a phone at the default text size and stop fitting a few notches
      // up, and a list that overflows is a list whose last row cannot be
      // reached at all.
      builder: (ctx) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                l10n.filters,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final type in <NoteType?>[null, ...nexShelfTypeOrder])
              ListTile(
                leading: Icon(
                  nexNoteTypeIcon(
                    type == NoteType.photo ? 'media' : type?.wireName,
                  ),
                ),
                title: Text(
                  type == null
                      ? l10n.all
                      : nexNoteTypeFilterLabel(l10n, type.wireName),
                ),
                trailing: !_model.onlyCode && _model.selectedType == type
                    ? const Icon(Icons.check)
                    : null,
                selected: !_model.onlyCode && _model.selectedType == type,
                // Wrapped, because popping a bare null cannot be told apart
                // from the user dismissing the sheet.
                onTap: () => Navigator.pop(ctx, _TypeChoice(type)),
              ),
            ListTile(
              leading: const Icon(Icons.code_rounded),
              title: Text(l10n.code),
              trailing: _model.onlyCode ? const Icon(Icons.check) : null,
              selected: _model.onlyCode,
              onTap: () => Navigator.pop(
                ctx,
                const _TypeChoice(NoteType.text, code: true),
              ),
            ),
            // The rows above answer "which kind of thing is it", and each of
            // them rules the others out. This one is not one of those: it is
            // a fact about a note rather than a kind of note, and it layers
            // on top of whichever kind is chosen. The line is what says so.
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.alarm),
              title: Text(l10n.filterHasReminder),
              trailing: _model.onlyReminders ? const Icon(Icons.check) : null,
              selected: _model.onlyReminders,
              // Tapping closes the sheet and applies, exactly like every row
              // above it — a switch that stayed put while the rest dismissed
              // would be two interaction models in one list.
              onTap: () => Navigator.pop(
                ctx,
                _ReminderChoice(only: !_model.onlyReminders),
              ),
            ),
          ],
        ),
      ),
    );
    switch (chosen) {
      case null:
        return;
      case _TypeChoice(:final type, :final code):
        await _selectType(type, code: code);
      case _ReminderChoice(:final only):
        await _selectOnlyReminders(only);
    }
  }

  /// Everything above the search field: the greeting, the generated headline,
  /// and the recap card.
  ///
  /// Which of those appear depends on what is configured, and the four cases
  /// are the whole design:
  ///
  /// - nothing set up at all — no header, just the search field, as before;
  /// - a name but no AI — the greeting *is* the headline, at headline size,
  ///   and holding it re-rolls the phrasing;
  /// - AI but no name — the generated line alone;
  /// - both — the greeting small above, the generated line large below.
  ///
  /// The whole text block is one tap target rather than two: they read as one
  /// paragraph, and a refresh that only fires on the second of two adjacent
  /// lines is a refresh people report as broken.
  Widget _header(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final showGreeting = widget.preferences.showGreeting;
    final greeting = showGreeting
        ? _greeting(l10n, aiPhrase: _aiHeadlineText)
        : null;
    // The line is there either because there is a greeting to say or because
    // a provider is going to write one — the slot is a skeleton first and
    // text second, rather than appearing from nowhere later and pushing the
    // card below it down.
    final showLine = showGreeting && (greeting != null || _aiHeaderAvailable);
    // The brief used to live here too. It is its own card now, in the slot
    // above the notes — see [_briefCard].
    if (!showLine) return const SizedBox.shrink();
    // The greeting has a face of its own (2.4.0): Fraunces in English and
    // Markazi Text in Persian, a size under display, at a regular weight —
    // the date above it keeps its small label. Whether a model wrote the
    // phrase or the app chose it, it is the same line and looks the same.
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    final compact = MediaQuery.sizeOf(context).height < 700;
    final headlineStyle = TextStyle(
      fontFamily: persian ? 'MarkaziText' : 'Fraunces',
      fontFamilyFallback: const ['Vazirmatn', 'Inter'],
      fontSize: persian ? (compact ? 28 : 32) : (compact ? 24 : 28),
      fontWeight: FontWeight.w400,
      height: persian ? 1.3 : 1.2,
      color: theme.colorScheme.onSurface,
    );
    // The generated line has a slot as soon as there is a provider: it is a
    // skeleton first and text second, rather than appearing from nowhere and
    // pushing the card down once the request lands.
    final hasHeadlineSlot = _aiHeaderAvailable && showGreeting;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        NexSpacing.md,
        MediaQuery.sizeOf(context).height < 700 ? NexSpacing.xs : NexSpacing.sm,
        NexSpacing.md,
        0,
      ),
      child: Column(
        // Stretch, so the tappable text block spans the column and the
        // centring inside it has something to centre against — sized to its
        // own content it would sit at one edge no matter how it aligned its
        // children. The card below wants the full width anyway.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showLine)
            NexTappable(
              onTap: () {},
              onLongPress: _refreshHeadline,
              semanticLabel: l10n.aiHeadlineRefresh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(NexRadius.lg),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: NexSpacing.xs,
                  vertical: NexSpacing.sm,
                ),
                // One line, and now genuinely one. It used to be the greeting
                // and a separate generated sentence joined by an em dash, which
                // read as two openings competing — "The quiet hours, Saeed —
                // Midnight code audits taste like stale glue." The model now
                // writes the greeting itself and the name follows it, so there
                // is one thought here instead of two.
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TodayLine(solar: widget.services.solarCalendar),
                    const SizedBox(height: NexSpacing.xs),
                    _GreetingLine(
                      text: greeting ?? _aiHeadlineText ?? '',
                      loading: hasHeadlineSlot && _aiHeadlineLoading,
                      style: headlineStyle,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// A finger off the list. The gesture stays a multi-touch one until the
  /// last finger is up, so the finger left behind after a pinch cannot turn
  /// into a pull.
  void _pinchLift(PointerEvent event) {
    _pinchPointers.remove(event.pointer);
    // After this event, not during it: the scroll view ends its drag on the
    // same lift, after this listener has seen it, and the fling it starts
    // must still find the list held — see `_PinchHoldPhysics`.
    if (_pinchPointers.isEmpty) {
      scheduleMicrotask(() {
        if (_pinchPointers.isEmpty) _multiTouch = false;
      });
    }
  }

  void _pinchMove(PointerMoveEvent event) {
    if (!_pinchPointers.containsKey(event.pointer)) return;
    _pinchPointers[event.pointer] = event.localPosition;
    if (_pinchPointers.length != 2 || _pinchApplied || _searching) return;
    final points = _pinchPointers.values.toList();
    final distance = (points[0] - points[1]).distance;
    final initial = _pinchDistance;
    if (initial == null || initial < 40) {
      _pinchDistance = distance;
      return;
    }
    final scale = distance / initial;
    if (scale > .80 && scale < 1.25) return;
    _pinchApplied = true;
    nexBump();
    // The headings on screen now — days, or shelves by kind or tag. It used
    // to be a fixed list of day keys: arranged by kind or tag, a pinch in
    // folded nothing, and a pinch out opened every shelf (2.7.1). Folds
    // remembered for headings not on screen are left as they are.
    final shown = {
      for (final group in _rowsCache._groups ?? const <_NoteGroup>[]) group.key,
      // By day, every day there can be, as before: a day that is not on
      // screen yet is folded too, and comes in folded.
      if (widget.preferences.timelineArrangement ==
          NexTimelineArrangement.time) ...const {
        'pinned',
        'today',
        'yesterday',
        'week',
        'month',
        'older',
      },
    };
    final before = _model.collapsedGroups;
    unawaited(
      _foldAll(scale < 1 ? {...before, ...shown} : before.difference(shown)),
    );
  }

  /// A tap or pinch changes the fold target immediately. Reversing a group
  /// reuses its current progress, even if a previous animation is still on.
  Future<void> _foldAll(Set<String> folded) async {
    final before = _model.collapsedGroups;
    final changed = {
      ...folded.difference(before),
      ...before.difference(folded),
    };
    if (changed.isEmpty) return;
    final duration = NexMotion.of(context, NexMotion.standard);
    final moving = <String, AnimationController>{};
    for (final group in _rowsCache._groups ?? const <_NoteGroup>[]) {
      final key = group.key;
      if (!changed.contains(key)) continue;
      if (duration == Duration.zero) {
        _groupFolds.remove(key)?.dispose();
        continue;
      }
      moving[key] = _groupFolds.putIfAbsent(
        key,
        () => AnimationController(
          vsync: this,
          duration: duration,
          value: before.contains(key) ? 0 : 1,
        ),
      );
    }
    _model.setCollapsedGroups(folded);
    await Future.wait([
      for (final entry in moving.entries)
        _finishGroupFold(
          entry.key,
          entry.value,
          closing: folded.contains(entry.key),
        ),
    ]);
    if (!mounted) return;
    // No scroll notification accompanies the new heading position.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateStickyDay();
    });
  }

  Future<void> _finishGroupFold(
    String key,
    AnimationController progress, {
    required bool closing,
  }) async {
    try {
      await (closing
              ? progress.animateBack(0, curve: NexMotion.curve)
              : progress.animateTo(1, curve: NexMotion.curve))
          .orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted || !identical(_groupFolds[key], progress)) return;
    // The settled group's reveal hands back to the viewport's own layout,
    // and its scope drops the body it was holding open. Only that group's
    // own sliver hears this — no card anywhere rebuilds for a fold settling.
    _groupFolds.remove(key);
    _groupFoldPulse.value++;
    progress.dispose();
  }

  Widget _groupBody(_NoteGroup group, Widget sliver) => _GroupReveal(
    key: ValueKey('group-body-${group.key}'),
    progress: _groupFolds[group.key] ?? kAlwaysCompleteAnimation,
    sliver: sliver,
  );

  Widget _wrapInRefresh({required bool enabled, required Widget child}) {
    child = Listener(
      onPointerDown: (event) {
        _pinchPointers[event.pointer] = event.localPosition;
        if (_pinchPointers.length >= 2) _multiTouch = true;
        if (_pinchPointers.length == 2) {
          final points = _pinchPointers.values.toList();
          _pinchDistance = (points[0] - points[1]).distance;
          _pinchApplied = false;
        }
      },
      onPointerMove: _pinchMove,
      onPointerUp: _pinchLift,
      onPointerCancel: _pinchLift,
      child: child,
    );
    if (!enabled) return child;
    return NexPullRefresh(
      controller: _pullRefresh,
      completion: () =>
          _pullCancelled ||
              !_aiHeaderAvailable ||
              !widget.preferences.showDaySummary
          ? NexRefreshOutcome.cancelled
          : _lastBriefRefreshFailed
          ? NexRefreshOutcome.failed
          : NexRefreshOutcome.success,
      semanticsLabel: AppLocalizations.of(context).recapRefreshing,
      // Not while two fingers are on the list (2.1.7). A pinch at the top
      // of the timeline moves one finger down, which the list reads as a
      // pull, and the refresh started under the pinch that was folding the
      // days. The end of the gesture still gets through, so a pull that was
      // already under way when the second finger landed is put away rather
      // than left half drawn.
      notificationPredicate: (notification) =>
          notification.depth == 0 &&
          (!_multiTouch || notification is ScrollEndNotification),
      // A quiet Nex accent settles at the top after a successful refresh.
      onSettled: () => _refreshPulse.value++,
      // Not `force: true` for the sponsor: the gesture must not bypass its
      // daily success interval or failed-refresh cool-off.
      onRefresh: () async {
        _lastBriefRefreshFailed = false;
        _pullCancelled = false;
        final settings = _briefSettingsSignature();
        // Not dropped while a brief is already being written: the pull
        // waits for that one (see [_loadAiSummary]), and a flight that had
        // already decided not to ask is re-asked once it lands — the pull
        // is manual, which is what tells them apart.
        await Future.wait<void>([
          _sponsor.refresh(manual: true),
          _loadAiSummary(force: true, manual: true),
        ]);
        _pullCancelled = settings != _briefSettingsSignature();
        if (mounted) _rebuild(() {});
      },
      child: NexRefreshCompletion(
        pulse: _refreshPulse,
        strength: 0.14,
        child: child,
      ),
    );
  }

  /// The dot on the gear, or nothing.
  ///
  /// Rebuilt from the update service rather than from this screen's state, so
  /// a check that finishes while the timeline is idle still shows.
  Widget? _updateDot(AppLocalizations l10n) {
    final service = widget.updates;
    if (service == null) return null;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) => service.hasUpdate
          // TalkBack users get the one fact the dot carries — the only
          // update signal in the app was invisible to them.
          ? Semantics(
              label: l10n.updateAvailableBadge,
              child: const ExcludeSemantics(child: NexBadgeDot()),
            )
          : const SizedBox.shrink(),
    );
  }

  /// Whatever belongs under the chrome: results, skeletons, an empty state, or
  /// the timeline itself.
  List<Widget> _bodySlivers(AppLocalizations l10n) {
    if (_searching) {
      // Words typed and the keyboard up: a touch on a result only puts the
      // keyboard away, so a result is never opened by the touch meant to
      // close it. The touch passes through to the app's keyboard dismisser.
      // Scrolling the results still works.
      final hold =
          _search.query.text.trim().isNotEmpty &&
          _searchFocus.hasFocus &&
          MediaQuery.viewInsetsOf(context).bottom > 0;
      return [
        for (final sliver in searchResultSlivers(
          context: context,
          search: _search,
          preferences: widget.preferences,
          onUseSaved: (query) {
            _search.query.text = query;
            _search.run();
          },
          onOpen: (note) {
            unawaited(widget.preferences.rememberSearch(_search.query.text));
            if (_searchStarted case final started?) {
              NexMetrics.shared.record(NexMetric.searchToOpen, started.elapsed);
              _searchStarted = null;
            }
            // The field gives up its focus first: kept, it was handed back when
            // the note closed, and the keyboard came up again unasked.
            _searchFocus.unfocus();
            unawaited(_openNote(note));
          },
        ))
          SliverIgnorePointer(ignoring: hold, sliver: sliver),
      ];
    }

    // Three states, not two. "Not loaded yet" was indistinguishable from
    // "empty", which is why the onboarding screen flashed on every launch.
    final all = _model.all;
    if (all == null) {
      // A failed first read is a fourth state: skeletons that never resolve
      // are a hang the user can only interpret as "the app is broken".
      if (_model.loadFailed) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: NexEmptyState(
              icon: Icons.error_outline,
              message: l10n.timelineLoadFailed,
              action: FilledButton(
                onPressed: () async {
                  final loaded = await _model.retry();
                  if (!mounted || loaded == null) return;
                  _requestAiHeader(loaded);
                  _tourWhenReady();
                },
                child: Text(l10n.tryAgain),
              ),
            ),
          ),
        ];
      }
      return [
        SliverList.builder(
          itemCount: 4,
          itemBuilder: (_, _) => const NexCardSkeleton(),
        ),
      ];
    }

    // The empty state belongs to an empty *library*, not an empty result. It
    // used to replace the whole body whenever a filter matched nothing, taking
    // the filter row with it — so the filter that caused it could not be
    // cleared without restarting the app.
    // Grouped by date — or, when the reader chose it, onto shelves by kind
    // or tag (2.7.0, ADR-043). Never by hand: manual arrangement is gone (the
    // repository's ORDER BY says why): a heading that says "Yesterday" has to
    // be telling the truth about every row beneath it, and a hand-placed note
    // lands wherever it was dropped. A shelf's order can move; a note's
    // place inside it cannot.
    //
    final groups = _rowsCache.assemble(
      context,
      notes: _model.notes,
      l10n: l10n,
      arrange: _arrangeNow(),
    );

    final desktop = NexDesktopScope.isDesktop(context);
    final cardStrings = nexCardStrings(context);
    return [
      if (desktop)
        ..._desktopSlivers(groups, l10n)
      else if (widget.preferences.timelineGrid)
        ..._gridSlivers(groups, l10n)
      else ...[
        for (final group in groups)
          _GroupSliver(
            key: ValueKey(group.key),
            screen: this,
            group: group,
            folds: _groupFoldPulse,
            heading: () => _groupHeading(group, groups, l10n),
            body: () => _listSliver(group, l10n, cardStrings),
          ),
      ],
      if (_model.notes.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: all.isEmpty && !_model.filtering
              ? EmptyTimeline(
                  onWrite: () => unawaited(openCapture()),
                  onSpeak: () =>
                      unawaited(openCapture(kind: CaptureKind.voice)),
                  onPhotograph: () =>
                      unawaited(capturePhoto(ImageSource.camera)),
                  setAsideCount: _setAsideTotal,
                  onShowSetAside: () => unawaited(_openSetAside()),
                )
              : _FilteredEmpty(onClear: () => unawaited(_clearFilters())),
        ),
    ];
  }

  Widget _listSliver(
    _NoteGroup group,
    AppLocalizations l10n,
    NexCardStrings cardStrings,
  ) => _TimelineList(
    rows: group.rows,
    removedBuilder: (context, row) {
      if (row.moreOf case final group?) return _shelfMore(group, l10n);
      return _listCard(row.note!, cardStrings, interactive: false);
    },
    builder: (context, row) {
      if (row.moreOf case final group?) return _shelfMore(group, l10n);
      final note = row.note!;
      return _rowWidget(
        note,
        group: group,
        primary: row.primary,
        l10n: l10n,
        build: (label) {
          final wide = _usesWideListTile(note);
          return _DayMark(
            label: label,
            marks: _dayMarks,
            child: NoteSpotlight(
              key: _spotlightId == note.id && row.primary
                  ? _spotlightAnchor
                  : null,
              active: _spotlightId == note.id && _spotlightReady,
              radius: wide ? NexRadius.xl : NexRadius.lg,
              onDone: () {
                if (mounted && _spotlightId == note.id) {
                  _rebuild(() => _spotlightId = null);
                }
              },
              child: CommitReceipt(
                key: ValueKey(note.id),
                active: landedId == note.id,
                onDone: () {
                  if (mounted && landedId == note.id) {
                    _rebuild(() => landedId = null);
                  }
                },
                child: SwipeableNoteCard(
                  haptics: widget.preferences.haptics,
                  controller: _swipe,
                  resolveAction: ({required bool isLeading}) => _selecting
                      ? null
                      : nexSwipeSpec(
                          l10n,
                          isLeading
                              ? widget.preferences.leadingAction
                              : widget.preferences.trailingAction,
                        ),
                  onAction: (action) => unawaited(_runSwipe(action, note)),
                  child: NoteContextMenu(
                    entriesBuilder: (menuContext, width) =>
                        _holdEntries(note, menuContext, width),
                    onHold: _selecting ? () => _pickNote(note) : null,
                    child: _pickShield(note, _listCard(note, cardStrings)),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );

  Future<void> _toggleGroup(String key) {
    nexBump();
    final folded = {..._model.collapsedGroups};
    if (!folded.remove(key)) folded.add(key);
    return _foldAll(folded);
  }
}
