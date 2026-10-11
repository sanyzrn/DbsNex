part of '../settings_sheet.dart';

/// The FR-2.7 swipe mapping, picked where it is shown.
///
/// It used to be a row that opened a sheet with two rows, each of which
/// opened a list — three taps and two sheets stacked to change one edge, and
/// the answer to "what does that swipe do" hidden behind all of them. Seven
/// actions fit as chips under each edge, so the choice is now one tap on the
/// page itself, and a small note at the top shows both panels in the colours
/// the timeline will draw them — the two edges read as one picture rather than
/// as two settings.
class _SwipeMapping extends StatelessWidget {
  const _SwipeMapping({required this.preferences});

  final NexPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final leading = preferences.leadingAction;
    final trailing = preferences.trailingAction;
    // The arrow shows which way the finger travels. `Icons.arrow_forward` and
    // `Icons.arrow_back` are `matchTextDirection`, so the framework already
    // turns "forward" into a leftward arrow in Persian; swapping them here as
    // well would flip it twice.
    return Padding(
      padding: const EdgeInsets.all(NexSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.swipeActions, style: theme.textTheme.titleSmall),
          const SizedBox(height: NexSpacing.sm),
          _SwipePreview(leading: leading, trailing: trailing),
          const SizedBox(height: NexSpacing.md),
          _EdgeChoices(
            edge: 'leading',
            arrow: Icons.arrow_forward,
            label: l10n.swipeLeading,
            current: leading,
            onPick: (action) => unawaited(
              preferences.setSwipeAction(isLeading: true, action: action),
            ),
          ),
          const SizedBox(height: NexSpacing.md),
          _EdgeChoices(
            edge: 'trailing',
            arrow: Icons.arrow_back,
            label: l10n.swipeTrailing,
            current: trailing,
            onPick: (action) => unawaited(
              preferences.setSwipeAction(isLeading: false, action: action),
            ),
          ),
        ],
      ),
    );
  }
}

/// A note as the timeline draws it, with both edges' panels showing.
///
/// A [Row] lays out from the start of the reading direction, so the leading
/// panel lands on the left in English and on the right in Persian — the side
/// a swipe from that edge really uncovers.
class _SwipePreview extends StatelessWidget {
  const _SwipePreview({required this.leading, required this.trailing});

  final SwipeAction leading;
  final SwipeAction trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget line(double widthFactor) => FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: widthFactor,
      child: Container(
        height: 6,
        decoration: BoxDecoration(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(NexRadius.sm),
        ),
      ),
    );
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NexRadius.md),
        child: SizedBox(
          height: 56,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PreviewPanel(action: leading),
              Expanded(
                child: Container(
                  color: scheme.surfaceContainerLow,
                  padding: const EdgeInsets.symmetric(
                    horizontal: NexSpacing.md,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [line(0.8), const SizedBox(height: 8), line(0.5)],
                  ),
                ),
              ),
              _PreviewPanel(action: trailing),
            ],
          ),
        ),
      ),
    );
  }
}

/// One edge's panel in [_SwipePreview]; an edge bound to nothing has none.
class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({required this.action});

  final SwipeAction action;

  @override
  Widget build(BuildContext context) {
    final color = _swipeColor(context, action);
    final none = action == SwipeAction.none;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: none ? 24 : 64,
      color: none ? color.withValues(alpha: 0.12) : color,
      alignment: Alignment.center,
      child: none
          ? null
          : Icon(nexSwipeActionIcon(action), size: 22, color: Colors.white),
    );
  }
}

/// One edge: which way the finger goes, every action as a chip, and a line
/// saying what the chosen one does — because "Pin" and "Share" explain
/// themselves and "Ask" does not.
class _EdgeChoices extends StatelessWidget {
  const _EdgeChoices({
    required this.edge,
    required this.arrow,
    required this.label,
    required this.current,
    required this.onPick,
  });

  final String edge;
  final IconData arrow;
  final String label;
  final SwipeAction current;
  final ValueChanged<SwipeAction> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(arrow, size: 16, color: theme.colorScheme.secondary),
            const SizedBox(width: NexSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(color: muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: NexSpacing.xs),
        Wrap(
          spacing: NexSpacing.xs,
          children: [
            for (final action in SwipeAction.values)
              _ActionChip(
                key: ValueKey('swipe-$edge-${action.name}'),
                icon: nexSwipeActionIcon(action),
                label: nexSwipeActionLabel(l10n, action),
                color: _swipeColor(context, action),
                selected: action == current,
                onTap: () => onPick(action),
              ),
          ],
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Text(
            nexSwipeActionHint(l10n, current),
            key: ValueKey(current),
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
      ],
    );
  }
}

/// A choice drawn in the action's own colour once it is picked.
class _ActionChip extends StatelessWidget {
  const _ActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilterChip(
      selected: selected,
      showCheckmark: false,
      avatar: Icon(
        icon,
        size: 18,
        color: selected ? color : scheme.onSurfaceVariant,
      ),
      label: Text(label),
      selectedColor: color.withValues(alpha: 0.18),
      side: BorderSide(
        color: selected ? color : scheme.outlineVariant,
        width: selected ? 1.5 : 1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NexRadius.md),
      ),
      onSelected: (_) {
        nexTick();
        onTap();
      },
    );
  }
}

/// The colour a swipe action wears in Settings: the panel's own, so the chip
/// and the panel the gesture reveals are recognisably the same thing.
/// [SwipeAction.none] has no panel and no fill, so it borrows the outline.
Color _swipeColor(BuildContext context, SwipeAction action) =>
    nexSwipeSpec(AppLocalizations.of(context), action)?.color ??
    Theme.of(context).colorScheme.outline;

/// Which actions a note's hold menu offers, switched on and off where they
/// are listed rather than on a page of their own.
class _HoldMenuChoices extends StatelessWidget {
  const _HoldMenuChoices({required this.preferences});

  final NexPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chosen = preferences.holdMenuActions.toSet();
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.sm,
        NexSpacing.sm,
        NexSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  nexLabel(context, 'Hold menu', 'منوی نگه‌داشتن'),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(
                nexLabel(
                  context,
                  '${chosen.length} actions',
                  '${chosen.length} گزینه',
                ),
                style: theme.textTheme.labelMedium?.copyWith(color: muted),
              ),
              TextButton(
                onPressed: () => unawaited(
                  preferences.setHoldMenuActions(NexHoldAction.defaults),
                ),
                child: Text(nexLabel(context, 'Reset', 'پیش‌فرض')),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: NexSpacing.sm),
            child: Text(
              nexLabel(
                context,
                'Choose what appears when you hold a note on the home '
                    'screen. A note only shows the actions it can use — '
                    'Open link on a link, Translate when there is a '
                    'provider to ask.',
                'انتخاب کنید با نگه‌داشتن یادداشت در صفحهٔ اصلی چه '
                    'گزینه‌هایی بیاید. هر یادداشت فقط گزینه‌هایی را نشان '
                    'می‌دهد که برایش کار می‌کنند؛ مثلاً باز کردن لینک فقط '
                    'برای لینک.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
          const SizedBox(height: NexSpacing.sm),
          Wrap(
            spacing: NexSpacing.xs,
            children: [
              for (final action in NexHoldAction.choices)
                _ActionChip(
                  key: ValueKey('hold-action-${action.name}'),
                  icon: action.icon,
                  label: action.label(context),
                  color: action == NexHoldAction.delete
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                  selected: chosen.contains(action),
                  onTap: () => unawaited(
                    preferences.setHoldMenuActions([
                      for (final a in NexHoldAction.choices)
                        if (a == action
                            ? !chosen.contains(a)
                            : chosen.contains(a))
                          a,
                    ]),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
