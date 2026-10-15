part of 'note_card.dart';

extension on _CardBody {
  /// The preview and a compact status row below it. The row follows the
  /// interface direction, never the note's language, and owns its space:
  /// nothing is painted over or faded out of the note's last line.
  Widget _withFootnote(BuildContext context) {
    final due = showDue ? note.dueAt : null;
    final attached = note.attachmentCount > 0;
    final marked = due != null || attached;
    final preview =
        previewOverride ??
        _Preview(
          note: note,
          expanded: expanded,
          strings: strings,
          lines: NexCardDensity.of(context).lines,
        );
    if (!marked) return preview;
    final marks = LayoutBuilder(
      builder: (context, constraints) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (due != null)
            Flexible(
              child: _DueChip(
                due: due,
                repeat: note.dueRepeat,
                description: strings.dueDescription?.call(due, note.dueRepeat),
                compactLabel: strings.dueCompactLabel?.call(
                  due,
                  note.dueRepeat,
                ),
                label: strings.dueLabel?.call(due, note.dueRepeat),
                upcoming:
                    note.dueRepeat != NoteRepeat.once ||
                    due.isAfter(DateTime.now().toUtc()),
              ),
            ),
          if (due != null && attached) const SizedBox(width: NexSpacing.sm),
          if (attached)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.3),
              child: _AttachedMark(
                label: strings.attachedShort(note.attachmentCount),
              ),
            ),
        ],
      ),
    );
    final density = NexCardDensity.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (expanded)
          preview
        else
          SizedBox(
            height: nexCardPreviewLineHeightFor(context) * density.lines,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: preview,
            ),
          ),
        const SizedBox(height: NexSpacing.xs),
        SizedBox(
          height: nexCardFootnoteHeightFor(context) - NexSpacing.xs,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: marks,
          ),
        ),
      ],
    );
  }
}

/// The files a note carries after its own, in the card's footnote: a
/// paperclip and "+3". Not on the leading square, whose corners already hold
/// the tag dots and the pin. Announced with the card (see `attachedLabel`),
/// so the mark itself is silent.
class _AttachedMark extends StatelessWidget {
  const _AttachedMark({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.attach_file, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: NexSpacing.xs),
          Flexible(
            child: Text(
              label,
              textDirection: TextDirection.ltr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The bell on a card, and when it will ring.
///
/// It was the bell on its own, which said a reminder existed and nothing
/// about it — so the only thing anyone could do with a reminder they could not
/// read was delete it. Every app that sets reminders on a list row puts the
/// time on the row.
///
/// The text is optional and the bell is not: a caller with no localisation
/// still gets the mark it always had.
class _DueChip extends StatelessWidget {
  const _DueChip({
    required this.due,
    required this.repeat,
    required this.description,
    required this.compactLabel,
    required this.label,
    required this.upcoming,
  });

  final DateTime due;
  final NoteRepeat repeat;
  final String? description;
  final String? compactLabel;
  final String? label;
  final bool upcoming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = upcoming
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;
    final text = label;
    final icon = repeat == NoteRepeat.once
        ? Icons.notifications_active_outlined
        : Icons.repeat_rounded;
    if (text == null) return Icon(icon, size: 14, color: color);
    // No box of its own: a line of the card's footnote, not a chip on it.
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: NexSpacing.xs),
        Flexible(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final style = theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              );
              final measure = TextPainter(
                text: TextSpan(text: text, style: style),
                textScaler: MediaQuery.textScalerOf(context),
                textDirection: Directionality.of(context),
                maxLines: 1,
              )..layout();
              final shown =
                  measure.width > constraints.maxWidth && compactLabel != null
                  ? compactLabel!
                  : text;
              measure.dispose();
              return Text(
                shown,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              );
            },
          ),
        ),
      ],
    );
    final full = description;
    if (full == null) return row;
    return Semantics(
      container: true,
      label: full,
      excludeSemantics: true,
      child: Tooltip(message: full, excludeFromSemantics: true, child: row),
    );
  }
}
