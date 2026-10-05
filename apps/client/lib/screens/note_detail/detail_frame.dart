part of '../note_detail_sheet.dart';

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NexSpacing.xs / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          if (value.isNotEmpty) ...[
            const SizedBox(width: NexSpacing.sm),
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A horizontally scrolling strip of labelled icon actions.
///
/// Scrolling rather than wrapping: the number of actions depends on the note's
/// type, and a strip that silently grows a second row shifts everything below
/// it as you move between notes. Each action holds the 48px accessibility
/// floor (see [nexMinTapTarget]), so on a narrow or lower-resolution phone the
/// full strip — up to eight actions — routinely does not fit; shrinking the
/// icons to squeeze more in was tried and rejected for exactly the same
/// reason 48px is the floor everywhere else. A faded edge is the fix: it
/// only ever hints that a scroll is possible, never claims one is not needed,
/// which a same-width `Row` that just quietly clips its last icon does not.
/// The action strip, in groups with a hairline between them.
///
/// Keep the three most useful actions visible with labels. The rest are in a
/// sheet where their names are readable, instead of an icon-only strip that
/// concealed half its actions past the edge of a phone.
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.groups});

  final List<List<_DetailAction>> groups;

  @override
  Widget build(BuildContext context) {
    final all = groups.expand((group) => group).toList();
    _DetailAction? find(bool Function(_DetailAction) test) {
      for (final action in all) {
        if (test(action)) return action;
      }
      return null;
    }

    final visible = <_DetailAction>[
      if (find((a) => a.label == AppLocalizations.of(context).edit)
          case final action?)
        action,
      if (find((a) => a.icon == Icons.auto_awesome) case final action?) action,
      if (find((a) => a.icon == Icons.ios_share) case final action?) action,
    ];
    if (visible.length < 3) {
      final copy = find((a) => a.icon == Icons.copy_outlined);
      if (copy != null) visible.add(copy);
    }
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
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // Grows to fit its actions rather than stopping at the default half
      // screen: the last of them is Delete, and a list that hides it below
      // the fold makes the one action people look for the one they miss.
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                AppLocalizations.of(context).moreActions,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final action in actions)
              ListTile(
                leading: action.glyph ?? Icon(action.icon),
                title: Text(action.label),
                textColor: action.destructive
                    ? Theme.of(context).colorScheme.error
                    : null,
                iconColor: action.destructive
                    ? Theme.of(context).colorScheme.error
                    : action.accent
                    ? Theme.of(context).colorScheme.primary
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
    this.accent = false,
  }) : assert(
         icon != null || glyph != null,
         'an action needs something to show',
       );

  final IconData? icon;

  /// For the one action whose meaning no Material glyph carries. Rendered
  /// inside this row's own [IconTheme], so it is sized and coloured with the
  /// rest rather than having to be told twice.
  final Widget? glyph;

  final String label;
  final VoidCallback? onPressed;

  /// The assistant's colour. What the row was missing was not a better glyph
  /// for each AI action but a way to see that three of them are the same kind
  /// of thing — a tint does that across the group where no single icon can.
  final bool accent;

  /// Delete's own colour: the row is otherwise neutral, and this is the one
  /// action here that cannot be undone by repeating it.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = onPressed == null
        ? theme.disabledColor
        : accent
        ? theme.colorScheme.primary
        : destructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(NexRadius.lg),
        child: SizedBox(
          height: 62,
          // The theme is for [glyph], which has no parameters of its own
          // to be told with; the [Icon] keeps being told directly, because
          // "is this one red" is a thing the tests read off the widget.
          child: Column(
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
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
