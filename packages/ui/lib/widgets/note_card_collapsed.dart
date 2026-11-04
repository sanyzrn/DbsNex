part of 'note_card.dart';

class _CollapsedCardContent extends StatelessWidget {
  const _CollapsedCardContent({
    required this.surfaceColor,
    required this.note,
    required this.strings,
    required this.due,
    required this.caption,
    required this.previewOverride,
  });

  final Color surfaceColor;
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
            alignment: AlignmentDirectional.topStart,
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
        builder: (context, constraints) => Stack(
          fit: StackFit.expand,
          children: [
            preview,
            if (marked)
              PositionedDirectional(
                start: 0,
                bottom: 0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth,
                    maxHeight: constraints.maxHeight,
                  ),
                  child: _CardStatusOverlay(
                    note: note,
                    strings: strings,
                    due: due,
                    surfaceColor: surfaceColor,
                  ),
                ),
              ),
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

/// Shared measurement for a packed overlay and the expanded footer. Normal
/// cards use one row; accessibility sizes may wrap within the same envelope.
class _StatusLayout {
  _StatusLayout(
    BuildContext context,
    Note note,
    NexCardStrings strings,
    DateTime? due,
    double width, {
    required bool packed,
  }) {
    final attached = note.attachmentCount > 0;
    final urgentWidth = note.isUrgent ? 15.0 : 0.0;
    final count =
        (due != null ? 1 : 0) + (attached ? 1 : 0) + (note.isUrgent ? 1 : 0);
    final gaps = math.max(0, count - 1) * NexSpacing.xs;
    // Keep room for urgency beside attachments if the reminder needs a row.
    attachmentWidth = attached
        ? math.min(
            math.max(17.0, width - urgentWidth - NexSpacing.xs),
            13 +
                NexSpacing.xs +
                _statusTextWidth(
                  context,
                  strings.attachedShort(note.attachmentCount),
                ),
          )
        : 0.0;
    final full = due == null
        ? null
        : strings.dueLabel?.call(due, note.dueRepeat);
    final compact = due == null
        ? null
        : strings.dueCompactLabel?.call(due, note.dueRepeat);
    final others = attachmentWidth + urgentWidth + gaps;
    final packedBudget = math.max(0.0, width - others - 13 - NexSpacing.xs);
    label = full;
    if (full != null &&
        _statusTextWidth(context, full) >
            (packed ? packedBudget : width - 13 - NexSpacing.xs)) {
      label = compact ?? full;
    }
    final dueWidth = due == null
        ? 0.0
        : label == null
        ? 14.0
        : 13 + NexSpacing.xs + _statusTextWidth(context, label!);
    wraps = !packed || dueWidth + others > width;
    labelWidth = math.max(
      0.0,
      width - (wraps ? 0 : others) - 13 - NexSpacing.xs,
    );
    if (label != null && labelWidth < _statusTextWidth(context, '00')) {
      label = null;
    }
  }

  late final double attachmentWidth;
  late final double labelWidth;
  late final bool wraps;
  String? label;
}

class _CardStatusMarks extends StatelessWidget {
  const _CardStatusMarks({
    required this.note,
    required this.strings,
    required this.due,
    this.layout,
  });

  final Note note;
  final NexCardStrings strings;
  final DateTime? due;
  final _StatusLayout? layout;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final plan =
          layout ??
          _StatusLayout(
            context,
            note,
            strings,
            due,
            constraints.maxWidth,
            packed: false,
          );
      final label = plan.label;
      final marks = <Widget>[
        if (due != null)
          SizedBox(
            width: label == null
                ? 14
                : 13 +
                      NexSpacing.xs +
                      math.min(
                        plan.labelWidth,
                        _statusTextWidth(context, label),
                      ),
            child: _DueChip(
              due: due!,
              repeat: note.dueRepeat,
              description:
                  strings.dueDescription?.call(due!, note.dueRepeat) ??
                  strings.dueLabel?.call(due!, note.dueRepeat),
              compactLabel: null,
              label: label,
              upcoming:
                  note.dueRepeat != NoteRepeat.once ||
                  due!.isAfter(DateTime.now().toUtc()),
              labelWidth: plan.labelWidth,
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
        if (note.attachmentCount > 0)
          SizedBox(
            width: plan.attachmentWidth,
            child: _AttachedMark(
              label: strings.attachedShort(note.attachmentCount),
            ),
          ),
      ];
      if (!plan.wraps) {
        return Row(
          key: const ValueKey('note-status-marks'),
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < marks.length; i++) ...[
              if (i > 0) const SizedBox(width: NexSpacing.xs),
              marks[i],
            ],
          ],
        );
      }
      return Wrap(
        key: const ValueKey('note-status-marks'),
        spacing: NexSpacing.xs,
        runSpacing: NexSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: marks,
      );
    },
  );
}

/// Masks only the bottom-start of the full-width preview. The solid part
/// shrink-wraps existing marks; its trailing edge fades back into the text.
class _CardStatusOverlay extends StatelessWidget {
  const _CardStatusOverlay({
    required this.note,
    required this.strings,
    required this.due,
    required this.surfaceColor,
  });

  final Note note;
  final NexCardStrings strings;
  final DateTime? due;
  final Color surfaceColor;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const fade = 16.0;
      final plan = _StatusLayout(
        context,
        note,
        strings,
        due,
        math.max(0.0, constraints.maxWidth - fade - NexSpacing.xs),
        packed: true,
      );
      final style = Theme.of(context).textTheme.labelSmall;
      final rowHeight = math.max(
        nexCardPreviewLineHeightFor(context),
        MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 12) *
            (style?.height ?? 1.5),
      );
      return SizedBox(
        height: math.min(
          constraints.maxHeight,
          rowHeight * (plan.wraps ? 2 : 1) + (plan.wraps ? NexSpacing.xs : 0),
        ),
        child: Row(
          key: const ValueKey('note-status-overlay'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: ColoredBox(
                key: const ValueKey('note-status-fill'),
                color: surfaceColor,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: NexSpacing.xs),
                  child: _CardStatusMarks(
                    note: note,
                    strings: strings,
                    due: due,
                    layout: plan,
                  ),
                ),
              ),
            ),
            IgnorePointer(
              child: Container(
                key: const ValueKey('note-status-fade'),
                width: fade,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerStart,
                    end: AlignmentDirectional.centerEnd,
                    colors: [surfaceColor, surfaceColor.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
