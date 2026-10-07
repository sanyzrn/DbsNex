part of '../timeline_screen.dart';

/// The screen's frame: app bar, list and bottom bar.
extension _TimelineLayout on TimelineScreenState {
  Widget _screen(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final glass = context.nexVisualStyle.liquidGlass;
    // The same condition the header uses to decide whether to draw the recap
    // at all. It decides here whether the pull is wired up, because the pull
    // exists to rewrite the recap and nothing else.
    final showSummary =
        !_searching && _briefAvailable && widget.preferences.showDaySummary;
    return Scaffold(
      appBar: AppBar(
        // Transparent so the blur below has the list to work on rather than a
        // fill of the bar's own — see [NexGlassBar]. Null keeps the theme's
        // opaque colour everywhere else.
        backgroundColor: glass ? Colors.transparent : null,
        flexibleSpace: glass ? const NexGlassBar() : null,
        // The greeting used to live here, squeezed between the mark and the
        // two action icons. It is a header now, at header size, in the list
        // below — which is what it always wanted to be, and what left the bar
        // free to be the small quiet strip it is here.
        titleSpacing: NexSpacing.md,
        title: const _WordmarkTile(),
        actions: [
          // First, so it never moves. The icons after it come and go with
          // settings — the search icon appears only when the field is off —
          // and a control that locks the library is the wrong one to have
          // slide under a thumb that was aiming at something else.
          if (widget.preferences.appLockEnabled && widget.onLock != null)
            IconButton(
              tooltip: l10n.securityLockNow,
              icon: const Icon(Icons.lock_outline),
              onPressed: () {
                if (widget.preferences.haptics) HapticFeedback.mediumImpact();
                widget.onLock!.call();
              },
            ),
          // The icon comes back exactly when the field it used to duplicate
          // is not on screen. It was removed because it pointed at something
          // already visible; with the field switched off, it is the only way
          // to search at all.
          if (!widget.preferences.showSearchField && !_searching)
            IconButton(
              tooltip: l10n.search,
              icon: const Icon(Icons.search),
              onPressed: () => unawaited(revealSearch()),
            ),
          IconButton(
            tooltip: l10n.layoutTitle,
            // Not `tune`: the content-type filter at the head of the tag row
            // already wears that, and two identical icons on one screen
            // meaning two different things is worse than either.
            icon: const Icon(Icons.dashboard_customize_outlined),
            onPressed: () async {
              await nexShowSheet<void>(
                context: context,
                builder: (_) =>
                    HomeLayoutSheet(preferences: widget.preferences),
              );
              if (mounted) _rebuild(() {});
            },
          ),
          // The library and the gear used to be here. They are the two things
          // on this screen somebody reaches for with a thumb rather than with
          // their eyes, and the top-right corner of a phone is the one place
          // a thumb cannot go — see [_bottomBar], which is where they live
          // now.
        ],
      ),
      // Android's back gesture leaves search before it leaves the screen.
      body: PopScope(
        // Never popped by the framework: what Back means here depends on
        // things that change without this screen rebuilding — above all an
        // update downloading in the background.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          // Picking several notes is left before anything else.
          if (_selecting) return _endSelection();
          if (_searching) return _exitSearch();
          unawaited(_leave());
        },
        // The list keeps drawing all the way down, and stops *listening*
        // where the system's own navigation gestures begin. Without this the
        // two competed for the same upward drag at the bottom of the screen,
        // and which one won depended on the angle of the finger.
        //
        // Over the body, under the capture button: the FAB is a Scaffold slot
        // painted above this, so it stays tappable where the two overlap.
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              // A tap anywhere that is not a card closes what is open. Not
              // an action a screen reader should offer: it covered the whole
              // screen as one tappable thing with no name.
              excludeFromSemantics: true,
              onTap: _guard.claim,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  // Scrolling dismisses an open card, the way every list with
                  // swipe actions behaves.
                  if (notification is ScrollStartNotification) {
                    _swipe.closeAll();
                  }
                  // Past 200 notes, this is the only thing that ever asks for
                  // the rest — nothing rendered the tail of a long timeline
                  // before this, it just never loaded.
                  if (notification.metrics.extentAfter < 600) _maybeLoadMore();
                  return false;
                },
                child: Center(
                  // One column, and the filter row is inside it. It used to be a
                  // sibling *above* this, so on a wide window the pills started at
                  // the window edge while the cards sat in a narrower column — two
                  // things that belong to each other, visibly unaligned.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: TimelineScreenState._timelineColumnWidth,
                    ),
                    // The pull rewrites the recap, and that is the only thing
                    // it does.
                    //
                    // For a long time there was no pull here at all, and the
                    // reasoning held: the timeline is a broadcast stream that
                    // every mutation path already re-fires, the filter row
                    // reloads on the same event, and "Sync now" lives in
                    // Settings where a sync server is configured. A pull that
                    // re-reads data which is already current does nothing,
                    // and this screen's own history says why that is worse
                    // than no gesture — the pull used to be "reveal the
                    // search field", and it was replaced precisely because it
                    // never revealed anything.
                    //
                    // The recap is the one thing on this screen that does not
                    // refresh itself, so it owns the pull gesture. When that
                    // gesture exists, sponsor recovery piggybacks on it too;
                    // the sponsor service keeps its own traffic limits.
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScroll,
                      child: _wrapInRefresh(
                        enabled:
                            showSummary &&
                            widget.preferences.briefStyle.usesModel,
                        child: CustomScrollView(
                          controller: _scroll,
                          // Build nearby cards before they enter the viewport
                          // so local photo decoding happens during the scroll,
                          // not after the thumbnail is already on screen.
                          cacheExtent: 900,
                          // Always scrollable, so a short list still bounces rather
                          // than feeling locked.
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            // The headline and the recap card, above the search
                            // field. Both collapse to nothing rather than leaving
                            // the list, the same reason the two headers below do.
                            SliverToBoxAdapter(
                              key: const ValueKey('timeline-header'),
                              child: NexTapGuarded(
                                controller: _guard,
                                child: AnimatedSize(
                                  duration: NexMotion.slow,
                                  curve: NexMotion.curve,
                                  alignment: Alignment.topCenter,
                                  child: _searching
                                      ? const SizedBox.shrink()
                                      : _header(l10n),
                                ),
                              ),
                            ),
                            // Both headers are always in the list, keyed, and collapse
                            // to zero extent rather than leaving it. A sliver list that
                            // changes length while another sliver changes its pinning
                            // leaves the viewport painting a child it never laid out.
                            // Kept in the list while a search is running even
                            // when it is switched off, or the field the app bar
                            // icon just asked for would not exist.
                            if (widget.preferences.showSearchField ||
                                _searching)
                              SliverPersistentHeader(
                                key: const ValueKey('search-header'),
                                delegate: SearchFieldHeader(
                                  extent:
                                      math.max(
                                        nexMinTapTarget,
                                        MediaQuery.textScalerOf(
                                                  context,
                                                ).scale(16) *
                                                1.5 +
                                            16,
                                      ) +
                                      NexSpacing.xs +
                                      NexSpacing.sm,
                                  anchor: _searchAnchor,
                                  controller: _search.query,
                                  focusNode: _searchFocus,
                                  searching: _searching,
                                  onTap: () => unawaited(revealSearch()),
                                  onChanged: (_) => _search.schedule(),
                                  onClear: _exitSearch,
                                  filterCount: _search.activeFilterCount,
                                  onShowFilters: () => unawaited(
                                    nexShowSearchFilterSheet(
                                      context,
                                      search: _search,
                                    ),
                                  ),
                                ),
                              ),
                            // Without the tag row, a pinned hairline still
                            // carries the sticky day.
                            if (!widget.preferences.showTagRow)
                              SliverPersistentHeader(
                                pinned: true,
                                delegate: _FilterRowHeader(
                                  visible: !_searching,
                                  extent: 1,
                                  lineKey: _stickyLine,
                                  below: TimelineStickyDay(day: _stickyDay),
                                  child: const SizedBox.shrink(),
                                ),
                              ),
                            if (widget.preferences.showTagRow)
                              SliverPersistentHeader(
                                key: const ValueKey('filter-header'),
                                pinned: true,
                                delegate: _FilterRowHeader(
                                  visible: !_searching,
                                  lineKey: _stickyLine,
                                  below: TimelineStickyDay(day: _stickyDay),
                                  extent:
                                      math.max(
                                        nexMinTapTarget,
                                        MediaQuery.textScalerOf(
                                                  context,
                                                ).scale(14) *
                                                1.5 +
                                            16,
                                      ) +
                                      NexSpacing.md +
                                      NexSpacing.sm,
                                  child: NexTapGuarded(
                                    controller: _guard,
                                    child: TagFilterRow(
                                      tags: _model.filterTags,
                                      hasOtherFilters:
                                          _model.selectedType != null ||
                                          _model.onlyReminders,
                                      activeFilterLabel: [
                                        if (_model.selectedType != null)
                                          l10n.noteType(
                                            _model.selectedType!.wireName,
                                          ),
                                        if (_model.onlyReminders)
                                          l10n.filterHasReminder,
                                      ].join(' · '),
                                      onOpenActiveFilter: () =>
                                          unawaited(_pickFilters()),
                                      onClearAll: () =>
                                          unawaited(_clearFilters()),
                                      selectedTagIds: _model.selectedTagIds,
                                      allLabel: l10n.all,
                                      tagLabel: (tag) => nexTagLabel(tag, l10n),
                                      leading: _FilterButton(
                                        active:
                                            _model.selectedType != null ||
                                            _model.onlyReminders,
                                        onPressed: () =>
                                            unawaited(_pickFilters()),
                                      ),
                                      onSelected: (value) =>
                                          unawaited(_selectTags(value)),
                                    ),
                                  ),
                                ),
                              ),
                            // Above the list rather than spliced into it.
                            // `SliverList` matches its children by index — the
                            // fold animation depends on that — so a card that
                            // comes and goes inside it would renumber every row
                            // under it. Its own sliver has no such problem, and
                            // "the first card" is an honest place for something
                            // that is not a note.
                            //
                            // What sits here is the brief. The slot was built
                            // for the sponsor card and it is the right shape
                            // for the wrong thing: the first card on the
                            // screen should be the app's own reading of the
                            // day, not an advertisement.
                            if (showSummary)
                              SliverToBoxAdapter(child: _briefCard(l10n)),
                            ..._bodySlivers(l10n),
                            // And the sponsor goes last, under the notes.
                            // Nothing about a card that pays for itself earns
                            // the top of somebody's own page.
                            if (_sponsorCard() case final card?)
                              SliverToBoxAdapter(child: card),
                            // The capture button floats over the list, and on a
                            // device with a three-button navigation bar the system's
                            // own bar sits under that — the last card has to clear
                            // both, or it cannot be read or tapped.
                            SliverToBoxAdapter(
                              child: SizedBox(
                                height:
                                    nexFabClearance + nexBottomInset(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Fade moving cards into the page tone before they pass beneath
            // the dock. This keeps the actions readable without a black band
            // cutting across the bottom of the light or Comfort appearance.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: nexBottomScrim + nexBottomInset(context),
              child: const IgnorePointer(child: _BottomScrim()),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: nexBottomGestureStrip(context),
              child: const AbsorbPointer(),
            ),
          ],
        ),
      ),
      // The whole bottom bar goes in the Scaffold's floating slot, not in
      // `bottomNavigationBar`. A navigation bar is laid out *beside* the
      // body, so the list would stop at its top edge and the glass would
      // have nothing behind it but the page — the same mistake documented on
      // [NexGlassBar] for the top. Floating keeps the timeline running under
      // it, which is the only arrangement in which any of this is glass.
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      // Capture is a timeline action. Left up while searching, the bar read
      // as part of the search flow itself rather than what it actually still
      // did — open a fresh note, unrelated to whatever was just searched.
      floatingActionButton: _searching
          ? null
          : AnimatedSwitcher(
              // The dock does not cross-fade into the selection bar: it
              // gives way. The capsule leaving narrows and sinks, the one
              // arriving rises and widens out of it, and the bar's buttons
              // then land one after another (see [_StaggerIn]) — so the
              // change reads as the same bar turning into a different
              // tool rather than one picture swapped for another.
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 420),
              reverseDuration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: _morphTransition,
              // Bottom-aligned: the selection bar carries a count above it,
              // and centring the two would lift the capsule mid-change.
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.bottomCenter,
                children: [...previous, if (current != null) current],
              ),
              child: _selecting
                  ? KeyedSubtree(
                      key: const ValueKey('selection'),
                      child: _selectionBar(l10n),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('dock'),
                      child: _bottomBar(l10n),
                    ),
            ),
    );
  }

  /// Back with nothing open on the home screen: leave the app — except
  /// that while an update downloads, Nex goes to the background the way
  /// Home sends it, because closing it stopped the download.
  Future<void> _leave() async {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    if ((widget.updates?.isDownloading ?? false) &&
        await NexDownloadNotice.sendAppToBack()) {
      return;
    }
    await SystemNavigator.pop();
  }

  /// One dock along the bottom, with capture lifted above its quieter actions.
  ///
  /// Tools and recurring items stay to one side, library and settings
  /// to the other. The four destinations share a surface so the raised capture
  /// button is unmistakably the primary action.
  ///
  /// It does not mirror in Persian. Every other row in the app does, and
  /// should, because it is made of words; this one is made of four fixed
  /// places at the bottom edge of the screen, and which thumb reaches which
  /// is not a fact about the language being read.
  Widget _bottomBar(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!widget.preferences.captureHoldHintSeen)
          GestureDetector(
            onTap: () => widget.preferences.dismissCaptureHoldHint(),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 230),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.inverseSurface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                Localizations.localeOf(context).languageCode == 'fa'
                    ? 'برای دستیار + را نگه دار • فهمیدم'
                    : 'Hold + for the assistant • Got it',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onInverseSurface,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        NexNavigationDock(
          leading: [
            NexDockAction(
              icon: Icons.space_dashboard_outlined,
              tooltip: l10n.toolsTitle,
              onPressed: () {
                if (_claimedByOverlay()) return;
                _tick();
                unawaited(
                  Navigator.push<void>(
                    context,
                    NexPageRoute<void>(
                      builder: (_) => ToolsScreen(
                        services: widget.services,
                        preferences: widget.preferences,
                      ),
                    ),
                  ),
                );
              },
            ),
            NexDockAction(
              icon: Icons.event_repeat_outlined,
              tooltip: l10n.commitmentsTitle,
              onPressed: () async {
                if (_claimedByOverlay()) return;
                _tick();
                await RecurringScreen.show(context, services: widget.services);
                await _model.loadCommitments();
              },
            ),
          ],
          // Hold capture for the assistant; the leftmost destination is Tools.
          capture: NexLongPressGlow(
            colors: nexAssistantSpectrum,
            onHoldStart: _tick,
            onTriggered: () {
              if (_claimedByOverlay()) return;
              unawaited(widget.preferences.dismissCaptureHoldHint());
              _openAssistant();
            },
            child: FloatingActionButton(
              key: _captureAnchor,
              onPressed: () {
                if (_claimedByOverlay()) return;
                openCapture();
              },
              tooltip: l10n.capture,
              child: const Icon(Icons.add, size: 32),
            ),
          ),
          trailing: [
            NexDockAction(
              key: _libraryAnchor,
              icon: Icons.inventory_2_outlined,
              tooltip: l10n.libraryTitle,
              // Awaited, and the timeline reloads on the way back. Tags
              // and Trash both live behind here and both change what this
              // screen shows, and neither refreshes it on its own.
              onPressed: () async {
                if (_claimedByOverlay()) return;
                await Navigator.push(
                  context,
                  NexPageRoute<void>(
                    builder: (_) => LibraryScreen(
                      services: widget.services,
                      preferences: widget.preferences,
                    ),
                  ),
                );
                await _refresh();
              },
            ),
            NexDockAction(
              key: _settingsAnchor,
              icon: Icons.settings_outlined,
              tooltip: l10n.settings,
              badge: _updateDot(l10n),
              // Awaited so the commitments can be re-read on the way
              // back: they are not on the timeline stream that refreshes
              // everything else, and a brief that had not noticed the one
              // just added would look broken to whoever just added it.
              onPressed: () async {
                if (_claimedByOverlay()) return;
                await nexShowSheet<void>(
                  context: context,
                  builder: (_) => SettingsSheet(
                    services: widget.services,
                    preferences: widget.preferences,
                    updates: widget.updates,
                  ),
                );
                await _model.loadCommitments();
              },
            ),
          ],
        ),
      ],
    );
  }
}
