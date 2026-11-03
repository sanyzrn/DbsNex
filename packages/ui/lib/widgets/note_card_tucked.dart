part of 'note_card.dart';

bool _tucksNoteMarks(Note note, bool expanded, Widget? override) =>
    !expanded &&
    override == null &&
    note.type != NoteType.link &&
    note.type != NoteType.checklist &&
    !(note.type == NoteType.voice && (note.durationMs ?? 0) > 0) &&
    note.caption?.trim().isNotEmpty != true;

double _markTextWidth(BuildContext context, String text) {
  final style = Theme.of(
    context,
  ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600);
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

Widget _tuckedNoteMarks(
  BuildContext context,
  double available,
  Note note,
  NexCardStrings strings,
  DateTime? due,
) {
  final width = _noteMarksWidth(context, available, note, strings, due);
  final attached = note.attachmentCount > 0;
  final otherMarks =
      (note.isUrgent ? 15.0 : 0.0) +
      (note.isUrgent && (due != null || attached) ? NexSpacing.sm : 0) +
      (due != null && attached ? NexSpacing.sm : 0) +
      (due != null ? 17.0 : 0.0);
  final attachment = attached
      ? math.min(
          math.max(0.0, width - otherMarks),
          13 +
              NexSpacing.xs +
              _markTextWidth(
                context,
                strings.attachedShort(note.attachmentCount),
              ),
        )
      : 0.0;
  final fixed =
      (note.isUrgent ? 15.0 : 0.0) +
      attachment +
      (note.isUrgent && (due != null || attached) ? NexSpacing.sm : 0) +
      (due != null && attached ? NexSpacing.sm : 0);
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (note.isUrgent) ...[
        ExcludeSemantics(
          child: Icon(
            Icons.local_fire_department_outlined,
            key: const ValueKey('note-urgent-mark'),
            size: 15,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
        if (due != null || attached) const SizedBox(width: NexSpacing.sm),
      ],
      if (due != null)
        Flexible(
          child: _DueChip(
            due: due,
            repeat: note.dueRepeat,
            description: strings.dueDescription?.call(due, note.dueRepeat),
            compactLabel: strings.dueCompactLabel?.call(due, note.dueRepeat),
            label: strings.dueLabel?.call(due, note.dueRepeat),
            upcoming:
                note.dueRepeat != NoteRepeat.once ||
                due.isAfter(DateTime.now().toUtc()),
            labelWidth: math.max(0, width - fixed - 13 - NexSpacing.xs),
          ),
        ),
      if (due != null && attached) const SizedBox(width: NexSpacing.sm),
      if (attached)
        SizedBox(
          width: attachment,
          child: _AttachedMark(
            label: strings.attachedShort(note.attachmentCount),
          ),
        ),
    ],
  );
}

double _noteMarksWidth(
  BuildContext context,
  double width,
  Note note,
  NexCardStrings strings,
  DateTime? due,
) {
  final style = Theme.of(
    context,
  ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600);
  double measure(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final value = painter.width;
    painter.dispose();
    return value;
  }

  final attached = note.attachmentCount > 0;
  var cap = width * 0.55;
  var fixed = note.isUrgent ? 15.0 : 0.0;
  if (note.isUrgent && (due != null || attached)) fixed += NexSpacing.sm;
  if (attached) {
    fixed +=
        13 +
        NexSpacing.xs +
        measure(strings.attachedShort(note.attachmentCount));
  }
  if (due != null && attached) fixed += NexSpacing.sm;
  // Keep the fixed marks/count readable before spending width on reminder text.
  cap = math.max(cap, math.min(width * 0.8, fixed + (due != null ? 17 : 0)));
  var reminder = 0.0;
  if (due != null) {
    final label = strings.dueLabel?.call(due, note.dueRepeat);
    reminder = label == null ? 14 : 13 + NexSpacing.xs + measure(label);
    final short = strings.dueCompactLabel?.call(due, note.dueRepeat);
    if (fixed + reminder > cap && short != null) {
      reminder = 13 + NexSpacing.xs + measure(short);
    }
  }
  return math.min(cap, fixed + reminder);
}

/// The old _Tucked painted and faded words beneath a status overlay. Here the
/// marker is a real text placeholder, so glyphs never run under it. Only the
/// tail of the last visible row is ellipsised; earlier rows keep their width.
/// No shader layer, custom RenderObject or extra timeline row is needed.
class _TuckedPreview extends StatelessWidget {
  const _TuckedPreview({
    required this.text,
    required this.marks,
    required this.marksWidth,
    required this.width,
    required this.lines,
    required this.style,
  });
  final String text;
  final Widget marks;
  final double marksWidth;
  final double width;
  final int lines;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final parts = text
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    final directions = parts
        .map(nexDirectionOf)
        .whereType<TextDirection>()
        .toSet();
    final base = DefaultTextStyle.of(context).style.merge(style);
    final scaler = MediaQuery.textScalerOf(context);
    final visible = <({String text, int rows})>[];
    if (directions.length <= 1) {
      visible.add((text: parts.join('\n'), rows: lines));
    } else {
      // Match NexTextSurface's per-paragraph direction and wrapped-row budget.
      var left = lines;
      for (final part in parts) {
        if (left == 0) break;
        final painter = TextPainter(
          text: TextSpan(text: part, style: base),
          textDirection: nexDirectionOf(part) ?? Directionality.of(context),
          textScaler: scaler,
          maxLines: left,
        )..layout(maxWidth: width);
        final rows = painter.computeLineMetrics().length.clamp(1, left);
        painter.dispose();
        visible.add((text: part, rows: rows));
        left -= rows;
      }
    }
    if (visible.isEmpty) visible.add((text: '', rows: lines));
    final last = visible.last;
    return SizedBox(
      height: nexCardPreviewLineHeightFor(context) * lines,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final part in visible.take(visible.length - 1))
              NexTextSurface(part.text, style: style, maxLines: part.rows),
            _lastParagraph(context, last.text, last.rows, base, scaler),
          ],
        ),
      ),
    );
  }

  Widget _lastParagraph(
    BuildContext context,
    String source,
    int budget,
    TextStyle base,
    TextScaler scaler,
  ) {
    final direction = nexDirectionOf(source) ?? Directionality.of(context);
    // Scale the paragraph's font once here. WidgetSpan would otherwise scale
    // an already accessible-size badge again, growing its line or clipping it.
    final scaledBase = base.copyWith(
      fontSize: scaler.scale(base.fontSize ?? 14),
    );
    final markHeight = math.max(
      15.0,
      nexCardFootnoteHeightFor(context) - NexSpacing.xs,
    );
    final placeholderWidth = math.min(width, marksWidth + NexSpacing.sm);
    final placeholder = WidgetSpan(
      alignment: PlaceholderAlignment.bottom,
      child: Directionality(
        textDirection: Directionality.of(context),
        child: SizedBox(
          width: placeholderWidth,
          height: markHeight,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: NexSpacing.sm),
            child: marks,
          ),
        ),
      ),
    );
    TextSpan span(String value) => TextSpan(
      style: scaledBase,
      children: [
        TextSpan(text: value, semanticsLabel: source),
        placeholder,
      ],
    );
    final painter =
        TextPainter(
            text: span(source),
            textDirection: direction,
            textScaler: TextScaler.noScaling,
            maxLines: budget,
          )
          ..setPlaceholderDimensions([
            PlaceholderDimensions(
              size: Size(placeholderWidth, markHeight),
              alignment: PlaceholderAlignment.bottom,
            ),
          ])
          ..layout(maxWidth: width);
    var shown = source;
    if (painter.didExceedMaxLines) {
      // Bound the search to text on visible rows, rather than repeatedly laying
      // out the whole potentially very long note. Work at grapheme boundaries.
      final position = painter.getPositionForOffset(
        Offset(
          direction == TextDirection.rtl ? 0 : width,
          math.max(0, painter.height - 1),
        ),
      );
      final end = painter.getLineBoundary(position).end.clamp(0, source.length);
      final chars = source.substring(0, end).characters.toList();
      var low = 0;
      var high = chars.length;
      while (low < high) {
        final mid = (low + high + 1) ~/ 2;
        painter.text = span('${chars.take(mid).join().trimRight()}…');
        painter.layout(maxWidth: width);
        if (painter.didExceedMaxLines) {
          high = mid - 1;
        } else {
          low = mid;
        }
      }
      shown = chars.take(low).join().trimRight();
      // Prefer a whole word; long unbroken tokens still have a safe ellipsis.
      final space = shown.lastIndexOf(RegExp(r'\s'));
      if (space > shown.length * 0.75 &&
          end < source.length &&
          !RegExp(
            r'\s',
          ).hasMatch(source.substring(shown.length, shown.length + 1))) {
        shown = shown.substring(0, space);
      }
      shown = '$shown…';
    }
    painter.dispose();
    return Text.rich(
      span(shown),
      maxLines: budget,
      textScaler: TextScaler.noScaling,
      textDirection: direction,
      textAlign: direction == TextDirection.rtl
          ? TextAlign.right
          : TextAlign.left,
    );
  }
}
