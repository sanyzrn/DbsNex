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
    final headlineStyle = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w600,
      fontSize: MediaQuery.sizeOf(context).height < 700 ? 20 : null,
      height: 1.25,
    );
    // The generated line is written at the daily recap's size and weight, not
    // at display size. It is a flourish, not a title: set large and bold it
    // was the loudest thing on a screen whose subject is the notes below it,
    // and a model's turn of phrase does not earn that.
    final generatedStyle = theme.textTheme.bodyMedium?.copyWith(height: 1.35);
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
                child: _GreetingLine(
                  text: greeting ?? _aiHeadlineText ?? '',
                  loading: hasHeadlineSlot && _aiHeadlineLoading,
                  style: hasHeadlineSlot ? generatedStyle : headlineStyle,
                ),
              ),
            ),
        ],
      ),
    );
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
  }

  Widget _wrapInRefresh({required bool enabled, required Widget child}) {
    child = Listener(
      onPointerDown: (event) {
        _pinchPointers[event.pointer] = event.localPosition;
        if (_pinchPointers.length == 2) {
          final points = _pinchPointers.values.toList();
          _pinchDistance = (points[0] - points[1]).distance;
          _pinchApplied = false;
        }
      },
      onPointerMove: _pinchMove,
      onPointerUp: (event) => _pinchPointers.remove(event.pointer),
      onPointerCancel: (event) => _pinchPointers.remove(event.pointer),
      child: child,
    );
    if (!enabled) return child;
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      color: scheme.primary,
      backgroundColor: scheme.surfaceContainerLowest,
      // Not `force: true` on a request already in flight: two in flight means
      // whichever finishes last wins, which is not necessarily the one the
      // pull asked for. The spinner still runs, and it is the honest picture
      // — something is being written, just not a second something.
      onRefresh: () async {
        if (_aiSummaryLoading) return;
        nexBump();
        await _loadAiSummary(force: true);
      },
      child: child,
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
      return searchResultSlivers(
        context: context,
        search: _search,
        preferences: widget.preferences,
        onUseSaved: (query) {
          _search.query.text = query;
          _search.run();
        },
        onOpen: (note) {
          if (_searchStarted case final started?) {
            NexMetrics.shared.record(NexMetric.searchToOpen, started.elapsed);
            _searchStarted = null;
          }
          unawaited(_openNote(note));
        },
      );
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
          itemBuilder: (_, __) => const NexCardSkeleton(),
        ),
      ];
    }

    // The empty state belongs to an empty *library*, not an empty result. It
    // used to replace the whole body whenever a filter matched nothing, taking
    // the filter row with it — so the filter that caused it could not be
    // cleared without restarting the app.
    if (all.isEmpty && !_model.filtering) {
      return const [
        SliverFillRemaining(hasScrollBody: false, child: EmptyTimeline()),
      ];
    }
    if (_model.notes.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _FilteredEmpty(onClear: () => unawaited(_clearFilters())),
        ),
      ];
    }

    // Grouped by date, and only by date. Manual arrangement is gone (the
    // repository's ORDER BY says why): a heading that says "Yesterday" has to
    // be telling the truth about every row beneath it, and a hand-placed note
    // lands wherever it was dropped.
    final groups = _groupNotes(_model.notes, l10n);
    final rows = <_TimelineRow>[
      for (final group in groups) ...[
        _TimelineRow.header(group),
        // A closing group keeps its rows for one animation. Without that the
        // fold was a jump cut: the rows were simply gone on the next frame,
        // which is the report this fixes. See [_toggleGroup].
        if (!_model.collapsedGroups.contains(group.key) ||
            _closingGroups.contains(group.key))
          for (final note in group.notes) _TimelineRow.note(note, group.key),
      ],
    ];

    return [
      SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          if (row.group case final group?) {
            // Inert while a card is open: the fold, the menu and Ask all sit
            // in the same list as the swiped card, and the tap that puts it
            // away must not also do one of them.
            return NexTapGuarded(
              controller: _guard,
              child: _GroupHeader(
                label: group.label,
                count: group.notes.length,
                collapsed: _model.collapsedGroups.contains(group.key),
                onToggle: () => unawaited(_toggleGroup(group.key)),
                onAsk: AiChatSheet.availableFor(widget.preferences)
                    ? () => unawaited(_askAboutGroup(group))
                    : null,
                onDelete: () => unawaited(_deleteGroup(group, l10n)),
              ),
            );
          }
          final note = row.note!;
          return _DayMark(
            label: _dayLabel(note, l10n),
            marks: _dayMarks,
            child: _FoldingRow(
              // Keyed on the note so the controller survives a rebuild of the
              // list and an entrance is never restarted mid-flight.
              key: ValueKey('fold-${note.id}'),
              open: !_closingGroups.contains(row.groupKey),
              animateIn: _openingGroups.contains(row.groupKey),
              child: NoteSpotlight(
                key: _spotlightId == note.id ? _spotlightAnchor : null,
                active: _spotlightId == note.id,
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
                      entries: _holdEntries(note),
                      child: NoteCard(
                        note: note,
                        strings: nexCardStrings(context),
                        onTap: () => _tapNote(note),
                        selected: _selecting
                            ? _selected.contains(note.id)
                            : null,
                        expanded: widget.preferences.isNoteExpanded(note.id),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
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
  }

  /// Splits an already-ordered list into date runs.
  ///
  /// Walks the list rather than sorting it: the order is the repository's —
  /// pinned first, then newest — and re-deriving it here would be a second
  /// answer to the same question that could disagree with the first. A group
  /// simply ends where the bucket changes, which only works because the list
  /// arrives ordered, and which is why the pin gets its own group instead of
  /// interrupting whichever day it belongs to.
  List<_NoteGroup> _groupNotes(List<Note> source, AppLocalizations l10n) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final groups = <_NoteGroup>[];

    for (final note in source) {
      final (key, label) = _bucketFor(note, today, l10n);
      if (groups.isEmpty || groups.last.key != key) {
        groups.add(_NoteGroup(key: key, label: label, notes: [note]));
      } else {
        groups.last.notes.add(note);
      }
    }
    return groups;
  }

  (String, String) _bucketFor(
    Note note,
    DateTime today,
    AppLocalizations l10n,
  ) {
    // Pinned before dated: a pinned note is held at the top on purpose, and
    // filing it under "Today" would put a heading over one row that then
    // repeats itself two rows later.
    if (note.pinnedAt != null) return ('pinned', l10n.timelineGroupPinned);

    // The same timestamp the list is ordered by. Grouping by createdAt while
    // sorting by updatedAt would scatter a group across the whole list.
    final at = note.updatedAt.toLocal();
    final day = DateTime(at.year, at.month, at.day);
    final days = today.difference(day).inDays;
    if (days <= 0) return ('today', l10n.timelineGroupToday);
    if (days == 1) return ('yesterday', l10n.timelineGroupYesterday);
    if (days <= 7) return ('week', l10n.timelineGroupWeek);
    if (days <= 31) return ('month', l10n.timelineGroupMonth);
    return ('older', l10n.timelineGroupOlder);
  }
}
