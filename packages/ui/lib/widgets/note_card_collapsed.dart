part of 'note_card.dart';

// One rail width for a given card width and text scale. Reserve a short clock
// before allocating preview width; reminder wording and mark presence do not
// move its anchor. Very narrow cards still retain space for the preview.
double _collapsedStatusWidth(BuildContext context, double available) =>
    math.min(
      available * 0.7,
      math.max(
        math.min(224.0, math.max(36.0, available * 0.48)),
        13 + NexSpacing.xs + _statusTextWidth(context, '00:00'),
      ),
    );

class _CollapsedCardContent extends StatelessWidget {
  const _CollapsedCardContent({
    required this.note,
    required this.strings,
    required this.due,
    required this.caption,
    required this.previewOverride,
  });

  final Note note;
  final NexCardStrings strings;
  final DateTime? due;
  final String? caption;
  final Widget? previewOverride;

  @override
  Widget build(BuildContext context) {
    final density = NexCardDensity.of(context);
    final rowHeight = nexCardPreviewLineHeightFor(context);
    final marked = due != null || note.isUrgent || note.attachmentCount > 0;
    final lines = density.lines - (caption == null ? 0 : 1);
    final preview = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          key: const ValueKey('note-card-preview'),
          height: rowHeight * lines,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child:
                previewOverride ??
                _Preview(
                  note: note,
                  expanded: false,
                  strings: strings,
                  lines: lines,
                ),
          ),
        ),
        if (caption != null)
          SizedBox(
            height: rowHeight,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _CardCaption(text: caption!),
            ),
          ),
      ],
    );
    return SizedBox(
      height: nexCardHeightFor(context) - density.inset * 2,
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: preview),
            if (marked) ...[
              const SizedBox(width: NexSpacing.xs),
              SizedBox(
                key: const ValueKey('note-status-rail'),
                width: _collapsedStatusWidth(context, constraints.maxWidth),
                child: _CardStatusMarks(note: note, strings: strings, due: due),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

double _statusTextWidth(BuildContext context, String text) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// The rail is independent of the note's paragraphs. Only existing marks are
/// built: reminder, urgency, attachment. Wrap packs them without empty slots,
/// retaining the same start anchor on narrow screens and with larger text.
class _CardStatusMarks extends StatelessWidget {
  const _CardStatusMarks({
    required this.note,
    required this.strings,
    required this.due,
  });

  final Note note;
  final NexCardStrings strings;
  final DateTime? due;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final attached = note.attachmentCount > 0;
      final attachedText = strings.attachedShort(note.attachmentCount);
      final attachmentWidth = attached
          ? math.min(
              width,
              13 + NexSpacing.xs + _statusTextWidth(context, attachedText),
            )
          : 0.0;
      // A reminder can use the whole rail. Other marks wrap rather than
      // subtracting the space its compact clock needs.
      final dueLabelWidth = math.max(0.0, width - 13 - NexSpacing.xs);
      final full = due == null
          ? null
          : strings.dueLabel?.call(due!, note.dueRepeat);
      final compact = due == null
          ? null
          : strings.dueCompactLabel?.call(due!, note.dueRepeat);
      final label =
          full == null || dueLabelWidth < _statusTextWidth(context, '00')
          ? null
          : _statusTextWidth(context, full) > dueLabelWidth && compact != null
          ? compact
          : full;
      return Wrap(
        key: const ValueKey('note-status-marks'),
        spacing: NexSpacing.xs,
        runSpacing: NexSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (due != null)
            SizedBox(
              width: label == null
                  ? 14
                  : 13 +
                        NexSpacing.xs +
                        math.min(
                          dueLabelWidth,
                          _statusTextWidth(context, label),
                        ),
              child: _DueChip(
                due: due!,
                repeat: note.dueRepeat,
                description:
                    strings.dueDescription?.call(due!, note.dueRepeat) ?? full,
                compactLabel: null,
                label: label,
                upcoming:
                    note.dueRepeat != NoteRepeat.once ||
                    due!.isAfter(DateTime.now().toUtc()),
                labelWidth: dueLabelWidth,
              ),
            ),
          if (note.isUrgent)
            ExcludeSemantics(
              child: Icon(
                Icons.local_fire_department_outlined,
                key: const ValueKey('note-urgent-mark'),
                size: 15,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          if (attached)
            SizedBox(
              width: attachmentWidth,
              child: _AttachedMark(label: attachedText),
            ),
        ],
      );
    },
  );
}
