part of '../note_detail_sheet.dart';

/// Keeps the note's own primary actions visible when available. Secondary note actions
/// live in the labelled More sheet; AI has its own workspace below the content.
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.groups});

  final List<List<_DetailAction>> groups;

  @override
  Widget build(BuildContext context) {
    final all = groups.expand((group) => group).toList();
    // The short toolbar takes the three highest-ranked actions — the ones
    // the note's own kind is opened to do: a link's Open, a file's Open, a
    // text's Edit, and Share and Copy after them. Finding them by comparing
    // translated labels and icon codes is why a link's Open — the one thing
    // a link is for — always fell into More: its icon was never one the
    // picker looked for, in any language.
    final ranked =
        <({int rank, int at, _DetailAction action})>[
          for (final (at, action) in all.indexed)
            if (action.primaryRank < _DetailAction.unranked)
              (rank: action.primaryRank, at: at, action: action),
        ]..sort(
          (a, b) => a.rank == b.rank
              ? a.at.compareTo(b.at)
              : a.rank.compareTo(b.rank),
        );
    final visible = [for (final each in ranked.take(3)) each.action];
    final remaining = all.where((action) => !visible.contains(action)).toList();
    return Row(
      children: [
        for (final action in visible.take(3)) Expanded(child: action),
        if (remaining.isNotEmpty)
          Expanded(
            child: _DetailAction(
              icon: Icons.more_horiz,
              label: AppLocalizations.of(context).moreActions,
              onPressed: () => _showMore(context, remaining),
            ),
          ),
      ],
    );
  }

  void _showMore(BuildContext context, List<_DetailAction> actions) {
    // The app's sheet (design language §1), so a pull down closes it like
    // every other: the plain modal's list caught the drag, and the sheet
    // only closed from its handle. It grows to fit its actions — the last
    // of them is Delete, the one people look for.
    nexShowSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, NexSpacing.sm),
              child: Text(
                AppLocalizations.of(context).moreActions,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final action in actions)
              ListTile(
                leading: action.glyph ?? Icon(action.icon),
                title: Text(
                  action.label,
                  style: TextStyle(
                    color: action.onPressed == null
                        ? Theme.of(sheetContext).disabledColor
                        : action.destructive
                        ? Theme.of(sheetContext).colorScheme.error
                        : Theme.of(sheetContext).colorScheme.onSurface,
                  ),
                ),
                textColor: action.destructive
                    ? Theme.of(context).colorScheme.error
                    : null,
                iconColor: action.destructive
                    ? Theme.of(context).colorScheme.error
                    : null,
                enabled: action.onPressed != null,
                onTap: action.onPressed == null
                    ? null
                    : () {
                        Navigator.pop(sheetContext);
                        action.onPressed!.call();
                      },
              ),
          ],
        ),
      ),
    );
  }
}

/// A labelled, thumb-sized action on the detail sheet's short toolbar.
class _DetailAction extends StatelessWidget {
  const _DetailAction({
    this.icon,
    this.glyph,
    required this.label,
    required this.onPressed,
    this.destructive = false,
    this.primaryRank = unranked,
  }) : assert(
         icon != null || glyph != null,
         'an action needs something to show',
       );

  /// Above this rank an action is a candidate for the sheet's short
  /// toolbar; at it, the action belongs to the More sheet only.
  static const unranked = 4;

  /// Where this action stands when the short toolbar picks its three.
  ///
  /// The note's own kind decides what is primary: opening is what a link or
  /// a file is *for*, editing is what a text is opened to do — so those take
  /// the first slot, Share follows, and Copy or Save the third. Everything
  /// else is a setting or a rarity, and lives behind More.
  final int primaryRank;

  final IconData? icon;

  /// For the one action whose meaning no Material glyph carries. Rendered
  /// inside this row's own [IconTheme], so it is sized and coloured with the
  /// rest rather than having to be told twice.
  final Widget? glyph;

  final String label;
  final VoidCallback? onPressed;

  /// Delete's own colour: the row is otherwise neutral, and this is the one
  /// action here that cannot be undone by repeating it.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = onPressed == null
        ? theme.disabledColor
        : destructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    final labelColor = color;
    return Tooltip(
      message: label,
      child: NexPress(
        enabled: onPressed != null,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(NexRadius.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 62),
            // The theme is for [glyph], which has no parameters of its own
            // to be told with; the [Icon] keeps being told directly, because
            // "is this one red" is a thing the tests read off the widget.
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconTheme.merge(
                    data: IconThemeData(size: 22, color: color),
                    child: glyph ?? Icon(icon, size: 22, color: color),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: labelColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The top of a note: what kind it is, in its colour, and when it was made.
class _DetailHeading extends StatelessWidget {
  const _DetailHeading({required this.note, required this.when});

  final Note note;
  final String when;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final type = note.type.wireName;
    final tint = nexNoteTypeTint(type, scheme);
    // A wrap, so at the largest text sizes the time moves under the type
    // instead of running off the edge.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: NexSpacing.md,
      runSpacing: NexSpacing.xs,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: nexNoteTypeWash(type, scheme),
            borderRadius: BorderRadius.circular(NexRadius.pill),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(nexNoteTypeIcon(type), size: 16, color: tint),
                const SizedBox(width: 6),
                // The word in the page's ink; the colour is the glyph's and
                // the wash's. The accent itself on its own wash is under
                // 3:1 for text.
                Flexible(
                  child: Text(
                    l10n.noteType(type),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                if (note.pinnedAt != null) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.push_pin, size: 13, color: tint),
                ],
              ],
            ),
          ),
        ),
        // One run of text with the clock inside it, so at the largest sizes
        // it wraps rather than running off the sheet.
        Text.rich(
          TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(
                  Icons.schedule,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              TextSpan(text: ' $when'),
            ],
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Says why an archived note offers so little (2.3.3): it is read, not worked
/// on, until it is unarchived — and, when it has one, when it comes back.
class _ArchivedStrip extends StatelessWidget {
  const _ArchivedStrip({required this.note, required this.solar});

  final Note note;
  final bool solar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hue = NexHue.amber.on(context);
    final until = note.setAsideUntil;
    return Padding(
      padding: const EdgeInsets.only(top: NexSpacing.sm),
      child: Container(
        key: const ValueKey('detail-archived'),
        padding: const EdgeInsets.symmetric(
          horizontal: NexSpacing.md,
          vertical: NexSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: hue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(NexRadius.md),
        ),
        child: Row(
          children: [
            Icon(Icons.archive_outlined, size: 18, color: hue),
            const SizedBox(width: NexSpacing.sm),
            Expanded(
              child: Text(
                until == null
                    ? l10n.archiveReadOnly
                    : '${l10n.archiveReadOnly} '
                          '${l10n.setAsideBackOn(nexReadableDate(until, solar: solar, persian: l10n.localeName == 'fa'))}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
