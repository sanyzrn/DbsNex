part of '../timeline_screen.dart';

/// The list itself: the header, date groups, folding, pinch and
/// pull-to-refresh, and the filter sheet.
extension _TimelineBody on TimelineScreenState {
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
            for (final type in <NoteType?>[null, ...NoteType.values])
              ListTile(
                leading: Icon(nexNoteTypeIcon(type?.wireName)),
                title: Text(
                  type == null ? l10n.all : l10n.noteType(type.wireName),
                ),
                trailing: _model.selectedType == type
                    ? const Icon(Icons.check)
                    : null,
                selected: _model.selectedType == type,
                // Wrapped, because popping a bare null cannot be told apart
                // from the user dismissing the sheet.
                onTap: () => Navigator.pop(ctx, _TypeChoice(type)),
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
      case _TypeChoice(:final type):
        await _selectType(type);
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
    if (_pinchPointers.isEmpty) _multiTouch = false;
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
    unawaited(
      _foldAll(
        scale < 1
            ? const {'pinned', 'today', 'yesterday', 'week', 'month', 'older'}
            : const {},
      ),
    );
  }

  /// Every day folded, or every day open, from a pinch — with the same
  /// animation a single heading's tap plays, on every group that moves.
  ///
  /// It used to set the folds in one go: the rows were there on one frame
  /// and gone on the next, which is the jump cut [_toggleGroup] exists to
  /// avoid for one group.
  Future<void> _foldAll(Set<String> folded) async {
    final before = _model.collapsedGroups;
    final closing = folded.difference(before);
    final opening = before.difference(folded);
    if (closing.isEmpty && opening.isEmpty) return;
    _rebuild(() {
      _closingGroups
        ..clear()
        ..addAll(closing);
      _openingGroups
        ..clear()
        ..addAll(opening);
    });
    _model.setCollapsedGroups(folded);
    await Future<void>.delayed(_foldDuration);
    if (!mounted) return;
    _rebuild(() {
      _closingGroups.removeAll(closing);
      _openingGroups.removeAll(opening);
    });
    // Same reason as [_toggleGroup]: the cards under the filter row moved
    // without a scroll notification to carry the sticky day along.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateStickyDay();
    });
  }

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
    // The rows come from the cache: the same list instance until the notes,
    // the folds or the day move, so an unrelated rebuild costs neither the
    // walk nor the wrappers nor the list differ's pass — see
    // `_TimelineRowsCache`.
    final (groups, rows) = _rowsCache.assemble(
      context,
      notes: _model.notes,
      collapsed: _model.collapsedGroups,
      closing: _closingGroups,
      l10n: l10n,
      arrange: _arrangeNow(),
    );
    final labels = {for (final group in groups) group.key: group.label};
    final arranged = groups.firstOrNull?.shelf != null;
    // One set of card strings per body build, not one per row: the list's
    // builder used to make a fresh `NexCardStrings` — ten closures deep — for
    // every card it laid out, on every rebuild.
    final cardStrings = nexCardStrings(context);

    final desktop = NexDesktopScope.isDesktop(context);
    return [
      if (desktop)
        ..._desktopSlivers(groups, l10n)
      else if (widget.preferences.timelineGrid)
        ..._gridSlivers(groups, l10n)
      else
        _TimelineList(
          rows: rows,
          revision: _model.notes,
          removedBuilder: (context, row) {
            if (row.moreOf case final group?) return _shelfMore(group, l10n);
            if (row.group case final group?) {
              return _GroupHeader(
                label: group.label,
                count: group.count,
                collapsed: _model.collapsedGroups.contains(group.key),
                leading: _shelfMark(group),
                onToggle: () {},
                onAsk: null,
                onDelete: null,
              );
            }
            return NoteCard(
              note: row.note!,
              strings: cardStrings,
              expanded: widget.preferences.isNoteExpanded(row.note!.id),
            );
          },
          builder: (context, row, index) {
            if (row.moreOf case final group?) {
              return _FoldingRow(
                key: ValueKey('fold-more-${group.key}'),
                open: !_closingGroups.contains(group.key),
                animateIn: _openingGroups.contains(group.key),
                order: row.indexInGroup,
                child: _shelfMore(group, l10n),
              );
            }
            if (row.group case final group?) {
              // Inert while a card is open: the fold, the menu and Ask all sit
              // in the same list as the swiped card, and the tap that puts it
              // away must not also do one of them.
              return _groupHeading(group, groups, l10n);
            }
            final note = row.note!;
            // Neighbours under the same heading are joined — see
            // [NoteCard.threadAbove].
            bool sameRun(int at) =>
                at >= 0 &&
                at < rows.length &&
                rows[at].note != null &&
                rows[at].groupKey == row.groupKey;
            return _DayMark(
              // Arranged, the line under the filters names the shelf being
              // read, as by day it names the day.
              label: arranged
                  ? labels[row.groupKey] ?? ''
                  : _dayLabel(note, l10n),
              marks: _dayMarks,
              child: _FoldingRow(
                // Keyed on the note so the controller survives a rebuild of the
                // list and an entrance is never restarted mid-flight.
                key: ValueKey('fold-${note.id}'),
                open: !_closingGroups.contains(row.groupKey),
                animateIn: _openingGroups.contains(row.groupKey),
                order: row.indexInGroup,
                child: NoteSpotlight(
                  key: _spotlightId == note.id && row.primary
                      ? _spotlightAnchor
                      : null,
                  active: _spotlightId == note.id && _spotlightReady,
                  onDone: () {
                    if (mounted && _spotlightId == note.id) {
                      _rebuild(() => _spotlightId = null);
                    }
                  },
                  child: CommitReceipt(
                    key: ValueKey(note.id),
                    active: landedId == note.id,
                    // Cleared when it finishes, so the receipt is a moment rather than
                    // a permanent mark on whichever note was captured last.
                    onDone: () {
                      if (mounted && landedId == note.id) {
                        _rebuild(() => landedId = null);
                      }
                    },
                    // ADR-022: the action set is open, and each edge is bound
                    // independently.
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
                        child: NoteCard(
                          note: note,
                          strings: cardStrings,
                          onTap: () => _tapNote(note),
                          onLeadingTap: () => _pickNote(note),
                          selected: _selecting
                              ? _selected.contains(note.id)
                              : null,
                          expanded: widget.preferences.isNoteExpanded(note.id),
                          threadAbove: sameRun(index - 1),
                          threadBelow: sameRun(index + 1),
                          ringing: widget.services.ringing.value.contains(
                            note.id,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
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

  /// Folds a date run, or opens it.
  ///
  /// Opening is easy: the rows go into the list and each one animates itself
  /// in. Closing cannot work the same way — a row that has been removed has
  /// nothing left to animate — so the group is marked as closing, its rows
  /// stay in the list for exactly one animation while they shrink to nothing,
  /// and only then is the fold committed.
  ///
  /// The rows are kept rather than the whole group being built eagerly on the
  /// side, so the list stays lazy: `SliverList` still builds only what the
  /// viewport can see, which matters for a run like "Older" holding a
  /// hundred notes.
  Future<void> _toggleGroup(String key) async {
    nexBump();
    final collapsed = _model.collapsedGroups;
    final closing = !collapsed.contains(key);
    if (closing) {
      _rebuild(() {
        _closingGroups.add(key);
        _openingGroups.remove(key);
      });
      _model.setCollapsedGroups({...collapsed, key});
      await Future<void>.delayed(_foldDuration);
      if (!mounted) return;
      _rebuild(() => _closingGroups.remove(key));
    } else {
      _rebuild(() {
        _closingGroups.remove(key);
        _openingGroups.add(key);
      });
      _model.setCollapsedGroups({...collapsed}..remove(key));
      await Future<void>.delayed(_foldDuration);
      if (!mounted) return;
      _rebuild(() => _openingGroups.remove(key));
    }
    // The fold moved the cards under the filter row without a scroll to
    // say so: the sticky day is named again against the new layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateStickyDay();
    });
  }
}
