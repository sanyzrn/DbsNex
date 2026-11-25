part of '../timeline_screen.dart';

/// What frames the notes on a phone since 2.8.0: the row over them, the
/// home layout sheet, and the brief under the greeting. Split out of
/// timeline_layout.dart and timeline_ai_header.dart, which were at the size
/// limit.
extension _TimelineHomeChrome on TimelineScreenState {
  /// Where a home tip's button leads (2.8.4).
  void _openTipTarget(NexTipTarget target) {
    switch (target) {
      case NexTipTarget.tools:
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
      case NexTipTarget.homeLayout:
        unawaited(_openHomeLayout());
      case NexTipTarget.guide:
        unawaited(GuideScreen.show(context));
    }
  }

  /// The home layout sheet, one tap from the screen it changes.
  Future<void> _openHomeLayout() async {
    if (_claimedByOverlay()) return;
    // The sheet's own writes rebuild this screen through the preferences
    // listener; what is left to catch is a sheet dismissed without a change,
    // and that must not repaint every card mid sheet-close transition.
    final prefs = widget.preferences;
    String layout() =>
        '${prefs.showGreeting}|${prefs.showDaySummary}|'
        '${prefs.showSearchField}|${prefs.showTagRow}';
    final before = layout();
    await nexShowSheet<void>(
      context: context,
      builder: (_) => HomeLayoutSheet(preferences: widget.preferences),
    );
    if (mounted && layout() != before) _rebuild(() {});
  }

  /// The row over the notes: what narrows them at its head, the tags along
  /// it, and how the notes are laid out at its end.
  ///
  /// The view switch stands still while the tags scroll under its edge:
  /// list or grid is asked for while looking at the notes, and it used to
  /// be two taps and a sheet away.
  Widget _notesToolbar(AppLocalizations l10n, bool otherFilters) => Row(
    children: [
      Expanded(
        // The pills thin out as they reach the switch instead of being cut
        // off against it. A mask over the row's own alpha, so it is right on
        // any background the reader has chosen, where a fade painted in the
        // page colour was a smudge across a patterned one.
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: AlignmentDirectional.centerStart,
            end: AlignmentDirectional.centerEnd,
            colors: const [Colors.white, Colors.white, Colors.transparent],
            stops: [
              0,
              1 - NexSpacing.lg / math.max(bounds.width, NexSpacing.lg),
              1,
            ],
          ).createShader(bounds, textDirection: Directionality.of(context)),
          // The row listens to the model itself, so a tags-only change —
          // the filter row refreshing after a delivery — repaints the pills
          // without rebuilding every card on the screen with them.
          child: ListenableBuilder(
            listenable: _model,
            builder: (context, _) => TagFilterRow(
              padding: const EdgeInsetsDirectional.fromSTEB(
                NexSpacing.md,
                NexSpacing.sm,
                NexSpacing.md,
                NexSpacing.sm,
              ),
              tags: _model.filterTags,
              tagCounts: _model.filterTagCounts,
              hasOtherFilters:
                  _model.selectedType != null || _model.onlyReminders,
              activeFilterLabel: [
                if (_model.selectedType != null)
                  _model.onlyCode
                      ? l10n.code
                      : nexNoteTypeFilterLabel(
                          l10n,
                          _model.selectedType!.wireName,
                        ),
                if (_model.onlyReminders) l10n.filterHasReminder,
              ].join(' · '),
              onOpenActiveFilter: () => unawaited(_pickFilters()),
              onClearAll: () => unawaited(_clearFilters()),
              selectedTagIds: _model.selectedTagIds,
              allLabel: l10n.all,
              untaggedLabel: _model.hasUntagged ? l10n.filterUntagged : null,
              untaggedSelected: _model.onlyUntagged,
              onUntagged: () {
                _tick();
                unawaited(_model.selectUntagged(!_model.onlyUntagged));
              },
              tagLabel: (tag) => nexTagLabel(tag, l10n),
              leading: _FilterButton(
                active: _model.selectedType != null || _model.onlyReminders,
                onPressed: () => unawaited(_pickFilters()),
              ),
              onSelected: (value) => unawaited(_selectTags(value)),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsetsDirectional.only(end: NexSpacing.md),
        child: _ViewToggle(
          grid: widget.preferences.timelineGrid,
          onChanged: (grid) {
            _tick();
            unawaited(widget.preferences.setTimelineGrid(grid));
          },
        ),
      ),
    ],
  );

  /// The brief, under the greeting it follows on from.
  ///
  /// It has a card's corner and none of a note card's height rule: this is
  /// the app reading the day back, and how long it is depends on how much
  /// there was to say. Nor a note card's colour: it is the plain card ground,
  /// with the app's own heading on it.
  ///
  /// The light going round its edge plays once, when it is opened by hand.
  Widget _briefCard(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const corner = BorderRadius.all(Radius.circular(NexRadius.lg));
    // The light along the edge is not tied to a minimal appearance (2.8.1):
    // every designed palette is minimal, so it ran for almost nobody. The
    // surface is the plain card it always was (2.8.2): the 2.8.1 wash of the
    // accent read as one more coloured panel on a screen of them.
    final highContrast = MediaQuery.highContrastOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NexSpacing.md,
        vertical: NexSpacing.sm,
      ),
      child: NexBorderBeam(
        borderRadius: corner,
        colors: [
          scheme.primary.withValues(alpha: 0.08),
          scheme.primary,
          scheme.primary.withValues(alpha: 0.08),
        ],
        thickness: 0.6,
        laps: 1,
        strength: highContrast ? 0 : 0.4,
        active: !_aiSummaryCollapsed && !highContrast,
        token: _aiSummaryExpansion,
        playOnMount: _aiSummaryBeamPending && !highContrast,
        onFinished: () => _aiSummaryBeamPending = false,
        // Only an explicit expansion earns a run; refreshed words do not.
        restsUnlit: true,
        child: NexGlassSurface(
          key: const ValueKey('timeline-recap-surface'),
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
            text: !widget.preferences.briefHabitsAllowed && _aiSummaryHasHabits
                ? widget.preferences.currentAiBrief ?? _notesOnlyBrief()
                : _aiSummaryText ?? '',
            emptyLabel: l10n.aiDaySummaryEmpty,
            collapsed: _aiSummaryCollapsed,
            semanticLabel: widget.preferences.briefStyle.usesModel
                ? '${l10n.aiDaySummarySemanticLabel}. ${l10n.aiDaySummaryByModel}'
                : l10n.aiDaySummarySemanticLabel,
            toggleTooltip: _aiSummaryCollapsed
                ? l10n.aiDaySummaryExpand
                : l10n.aiDaySummaryCollapse,
            onToggle: _toggleAiSummary,
            title: l10n.aiDaySummaryTitle,
            byModel: widget.preferences.briefStyle.usesModel,
            updatedAt:
                widget.preferences.briefStyle.usesModel &&
                    (!widget.preferences.aiDaySummaryIncludesHabits ||
                        widget.preferences.briefHabitsAllowed)
                ? widget.preferences.aiDaySummaryAt
                : null,
            solarCalendar: widget.services.solarCalendar,
            noteFor: (line) => _briefLineNotes[line],
            onOpenNote: (id) {
              if (_claimedByOverlay()) return;
              unawaited(_openNoteById(id));
            },
          ),
        ),
      ),
    );
  }
}
