part of '../settings_sheet.dart';

/// The FR-2.7 swipe mapping, as two rows rather than two grids.
///
/// ADR-022 always said the action set was open; for a long time it held two
/// members, and two grids of two cards each was a fine way to show them. At
/// seven it is not — fourteen preview cards stacked in a sheet is a wall, and
/// the thing being chosen (which of *these* does that edge do) stops being
/// legible somewhere around the fifth.
///
/// So each edge is one row saying what it currently does, and the choice moves
/// behind it into a list. That is the shape every settings screen uses for a
/// list that can grow, and it means the next action costs one entry rather
/// than another row of cards.
class _SwipeMapping extends StatefulWidget {
  const _SwipeMapping({required this.preferences});

  final NexPreferences preferences;

  @override
  State<_SwipeMapping> createState() => _SwipeMappingState();
}

class _SwipeMappingState extends State<_SwipeMapping> {
  Future<void> _choose({required bool isLeading}) async {
    final l10n = AppLocalizations.of(context);
    final current = isLeading
        ? widget.preferences.leadingAction
        : widget.preferences.trailingAction;
    final picked = await nexShowSheet<SwipeAction>(
      context: context,
      builder: (sheetContext) => _PickerSheet(
        title: isLeading ? l10n.swipeLeadingEdge : l10n.swipeTrailingEdge,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in SwipeAction.values)
              _SwipeChoiceRow(
                action: action,
                selected: action == current,
                onTap: () => Navigator.pop(sheetContext, action),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await widget.preferences.setSwipeAction(
      isLeading: isLeading,
      action: picked,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The arrow shows which way the finger travels: a swipe from the leading
    // edge moves rightwards in an English UI and leftwards in a Persian one.
    //
    // Which is why neither of these picks its icon by direction any more.
    // `Icons.arrow_forward` and `Icons.arrow_back` are both declared
    // `matchTextDirection: true`, and `Icon` mirrors such an icon under an RTL
    // `Directionality` — so the framework already turns "forward" into a
    // leftward arrow in Persian. Swapping them here as well flipped it twice:
    // in the app's primary language both arrows pointed the way they do in
    // English, which made the leading row describe the trailing gesture and
    // the trailing row the leading one.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SwipeEdgeRow(
          arrow: Icons.arrow_forward,
          label: l10n.swipeLeading,
          action: widget.preferences.leadingAction,
          onTap: () => unawaited(_choose(isLeading: true)),
        ),
        const SizedBox(height: NexSpacing.sm),
        _SwipeEdgeRow(
          arrow: Icons.arrow_back,
          label: l10n.swipeTrailing,
          action: widget.preferences.trailingAction,
          onTap: () => unawaited(_choose(isLeading: false)),
        ),
      ],
    );
  }
}

/// One edge, saying what it does now and opening the list that changes it.
class _SwipeEdgeRow extends StatelessWidget {
  const _SwipeEdgeRow({
    required this.arrow,
    required this.label,
    required this.action,
    required this.onTap,
  });

  final IconData arrow;
  final String label;
  final SwipeAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(NexRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          nexTick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NexSpacing.md,
            vertical: NexSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(arrow, size: 16, color: theme.colorScheme.secondary),
              const SizedBox(width: NexSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.bodySmall),
                    Text(
                      nexSwipeActionLabel(l10n, action),
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
              _SwipeActionPreview(action: action),
            ],
          ),
        ),
      ),
    );
  }
}

/// One action in the picker: its glyph, its name, and one line saying what it
/// does — because "Pin" and "Share" explain themselves and "Ask" does not.
class _SwipeChoiceRow extends StatelessWidget {
  const _SwipeChoiceRow({
    required this.action,
    required this.selected,
    required this.onTap,
  });

  final SwipeAction action;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _SwipeActionPreview(action: action),
      title: Text(nexSwipeActionLabel(l10n, action)),
      subtitle: Text(
        nexSwipeActionHint(l10n, action),
        style: theme.textTheme.bodySmall,
      ),
      trailing: selected
          ? Icon(Icons.check, color: theme.colorScheme.primary)
          : null,
      selected: selected,
      onTap: () {
        nexTick();
        onTap();
      },
    );
  }
}

/// The colour a swipe action wears in Settings.
///
/// The panel's own fill, dimmed onto a tinted disc, so the row in Settings and
/// the panel the gesture reveals are recognisably the same thing. [SwipeAction
/// .none] has no panel and no fill, so it borrows the outline.
Color _swipeColor(BuildContext context, SwipeAction action) =>
    nexSwipeSpec(AppLocalizations.of(context), action)?.color ??
    Theme.of(context).colorScheme.outline;

/// A swipe action's glyph on its tinted disc — the same language the theme and
/// language pickers use.
class _SwipeActionPreview extends StatelessWidget {
  const _SwipeActionPreview({required this.action});

  final SwipeAction action;

  @override
  Widget build(BuildContext context) {
    final color = _swipeColor(context, action);
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.14),
      ),
      child: Icon(nexSwipeActionIcon(action), size: 20, color: color),
    );
  }
}

/// Which actions a note's hold menu offers: every action on the detail sheet
/// and its More menu, each switched on or off.
class _HoldMenuScreen extends StatelessWidget {
  const _HoldMenuScreen({required this.preferences});

  final NexPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(nexLabel(context, 'Hold menu', 'منوی نگه‌داشتن')),
        actions: [
          TextButton(
            onPressed: () => unawaited(
              preferences.setHoldMenuActions(NexHoldAction.defaults),
            ),
            child: Text(nexLabel(context, 'Reset', 'پیش‌فرض')),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: preferences,
        builder: (context, _) {
          final chosen = preferences.holdMenuActions.toSet();
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, NexSpacing.xs, 20, 12),
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
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final action in NexHoldAction.choices)
                CheckboxListTile(
                  key: ValueKey('hold-action-${action.name}'),
                  value: chosen.contains(action),
                  secondary: Icon(
                    action.icon,
                    color: action == NexHoldAction.delete
                        ? theme.colorScheme.error
                        : null,
                  ),
                  title: Text(action.label(context)),
                  onChanged: (on) => unawaited(
                    preferences.setHoldMenuActions([
                      for (final a in NexHoldAction.choices)
                        if (a == action ? on == true : chosen.contains(a)) a,
                    ]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
