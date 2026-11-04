part of 'note_card.dart';

extension on _CardBody {
  Widget _withFootnote(BuildContext context) {
    final due = showDue ? note.dueAt : null;
    final marked = due != null || note.attachmentCount > 0 || note.isUrgent;
    final caption =
        note.type == NoteType.text && note.caption?.trim().isNotEmpty == true
        ? NexMarkdownText.preview(note.caption!.trim())
        : null;
    if (!expanded) {
      return _CollapsedCardContent(
        note: note,
        strings: strings,
        due: due,
        caption: caption,
        previewOverride: previewOverride,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        previewOverride ??
            _Preview(
              note: note,
              expanded: true,
              strings: strings,
              lines: NexCardDensity.of(context).lines,
            ),
        if (caption != null) _CardCaption(text: caption),
        if (marked) ...[
          const SizedBox(height: NexSpacing.xs),
          _CardStatusMarks(note: note, strings: strings, due: due),
        ],
      ],
    );
  }
}

class _CardCaption extends StatelessWidget {
  const _CardCaption({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => NexTextSurface(
    text,
    key: const ValueKey('note-card-caption'),
    maxLines: 1,
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w400,
    ),
  );
}

/// The files a note carries after its own, in the card's status area: a
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
    this.labelWidth,
  });

  final DateTime due;
  final NoteRepeat repeat;
  final String? description;
  final String? compactLabel;
  final String? label;
  final bool upcoming;
  final double? labelWidth;

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
    Widget labelFor(double maxWidth) {
      final style = theme.textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      );
      final measure = TextPainter(
        text: TextSpan(text: text!, style: style),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
        maxLines: 1,
      )..layout();
      final shown = measure.width > maxWidth && compactLabel != null
          ? compactLabel!
          : text;
      measure.dispose();
      return Text(
        shown,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    // No decorated box of its own: a small status mark in the card's rail.
    final row = text == null
        ? Icon(icon, size: 14, color: color)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: NexSpacing.xs),
              Flexible(
                child: labelWidth == null
                    ? LayoutBuilder(
                        builder: (context, constraints) =>
                            labelFor(constraints.maxWidth),
                      )
                    : labelFor(labelWidth!),
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
