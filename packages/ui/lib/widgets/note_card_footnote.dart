part of 'note_card.dart';

extension on _CardBody {
  /// The note's words, and under them — only when there is one — a quiet
  /// footnote of what it carries besides: when it will remind, and how many
  /// more files it holds.
  ///
  /// It was a column at the end of the row, one pill above the other, and it
  /// took its width from every line of the note beside it; on a short card
  /// the two pills were as wide as the words. Under the words it costs one
  /// line, on the cards that have it, and the words keep the card's width.
  ///
  /// One line exactly: the card is one height for every note, so the
  /// footnote takes the place of the words' last line instead of adding a
  /// line the card has no room for — in 1.99.93 it was added, and on a
  /// compact card it was cut in half by the card's edge. And it sits on the
  /// side the words start from, so a Persian note in an English app carries
  /// it on the right, under its own first letter.
  Widget _withFootnote(BuildContext context) {
    final due = showDue ? note.dueAt : null;
    final attached = note.attachmentCount > 0;
    final footnote = due != null || attached;
    final preview =
        previewOverride ??
        _Preview(
          note: note,
          expanded: expanded,
          strings: strings,
          lines: math.max(
            1,
            NexCardDensity.of(context).lines - (footnote ? 1 : 0),
          ),
          voiceLength: !footnote,
        );
    if (!footnote) return preview;
    final length = note.type == NoteType.voice && (note.durationMs ?? 0) > 0
        ? note.durationMs!
        : null;
    final ambient = Directionality.of(context);
    // A checklist's boxes keep the interface's side whatever its items are
    // written in; everything else starts where its words do.
    final side = note.type == NoteType.checklist
        ? ambient
        : nexDirectionOf(NexMarkdownText.preview(note.displayText ?? '')) ??
              ambient;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        preview,
        SizedBox(
          height: nexCardPreviewLineHeightFor(context),
          child: Align(
            alignment: side == TextDirection.rtl
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (length != null) ...[
                  Text(
                    strings.durationLabel?.call(length) ??
                        '${length ~/ 60000}:'
                            '${(length ~/ 1000 % 60).toString().padLeft(2, '0')}',
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(width: NexSpacing.md),
                ],
                // A reminder still to come stays in the accent: it is the one
                // thing here that asks for something.
                if (due != null)
                  Flexible(
                    child: _DueChip(
                      due: due,
                      label: strings.dueLabel?.call(due, note.dueRepeat),
                      // A lapsed reminder is not an alarm any more. A
                      // repeating one never lapses: it is always about to
                      // happen again.
                      upcoming:
                          note.dueRepeat != NoteRepeat.once ||
                          due.isAfter(DateTime.now().toUtc()),
                    ),
                  ),
                if (due != null && attached)
                  const SizedBox(width: NexSpacing.md),
                if (attached)
                  _AttachedMark(
                    label: strings.attachedShort(note.attachmentCount),
                  ),
              ],
            ),
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
          const SizedBox(width: 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
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
    required this.label,
    required this.upcoming,
  });

  final DateTime due;
  final String? label;
  final bool upcoming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = upcoming
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;
    final text = label;
    if (text == null) {
      return Icon(Icons.notifications_active_outlined, size: 14, color: color);
    }
    // No box of its own: a line of the card's footnote, not a chip on it.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.notifications_active_outlined, size: 13, color: color),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
