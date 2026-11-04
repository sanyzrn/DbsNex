part of 'note_card.dart';

// Temporary display-only trial. Keep labels, schedules and counts in the data
// and accessibility strings so showing them again needs no migration.
const _showCardStatusLabels = false;
const _statusHaloSize = 22.0;
const _statusMarkWidth = 18.0;
const _statusBottomGap = 4.0;

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
    final lines = density.lines - (caption == null ? 0 : 1);
    return SizedBox(
      height: nexCardHeightFor(context) - density.inset * 2,
      child: LayoutBuilder(
        builder: (context, bounds) {
          Widget preview = Column(
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
          final count =
              (due != null ? 1 : 0) +
              (note.attachmentCount > 0 ? 1 : 0) +
              (note.isUrgent ? 1 : 0);
          final columns = math.max(
            1,
            math.min(count, (bounds.maxWidth / _statusMarkWidth).floor()),
          );
          final rows = (count / columns).ceil();
          final groupHeight =
              rows * _statusHaloSize + math.max(0, rows - 1) * NexSpacing.xs;
          for (var i = 0; i < count; i++) {
            final x = _statusMarkWidth / 2 + (i % columns) * _statusMarkWidth;
            final centre = Offset(
              Directionality.of(context) == TextDirection.rtl
                  ? bounds.maxWidth - x
                  : x,
              bounds.maxHeight +
                  density.inset -
                  _statusBottomGap -
                  groupHeight +
                  _statusHaloSize / 2 +
                  (i ~/ columns) * (_statusHaloSize + NexSpacing.xs),
            );
            // Fade just the preview out behind each icon. This reveals the real
            // Material underneath, including its native ripple and highlight;
            // no painted white layer can hide or approximate those effects.
            preview = ShaderMask(
              key: ValueKey('note-status-mask-$i'),
              blendMode: BlendMode.dstOut,
              shaderCallback: (_) =>
                  const RadialGradient(
                    colors: [Colors.white, Colors.white, Colors.transparent],
                    stops: [0, .5, 1],
                  ).createShader(
                    Rect.fromCircle(
                      center: centre,
                      radius: _statusHaloSize / 2,
                    ),
                  ),
              child: preview,
            );
          }
          return Stack(
            clipBehavior: Clip.none,
            fit: StackFit.expand,
            children: [preview],
          );
        },
      ),
    );
  }
}

/// Only existing marks occupy space, ordered reminder, attachment, urgency.
/// The compact per-mark halo never becomes a shared strip behind the text.
class _CardStatusMarks extends StatelessWidget {
  const _CardStatusMarks({
    required this.note,
    required this.strings,
    required this.due,
    this.halos = false,
  });

  final Note note;
  final NexCardStrings strings;
  final DateTime? due;
  final bool halos;

  @override
  Widget build(BuildContext context) {
    Widget mark(String id, Widget icon) => !halos
        ? icon
        : SizedBox(
            key: ValueKey('note-status-halo-$id'),
            width: _statusMarkWidth,
            height: _statusHaloSize,
            child: Center(child: icon),
          );
    final full = due == null
        ? null
        : strings.dueLabel?.call(due!, note.dueRepeat);
    return Wrap(
      key: const ValueKey('note-status-marks'),
      spacing: halos ? 0 : NexSpacing.xs,
      runSpacing: NexSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (due != null)
          mark(
            'reminder',
            _DueChip(
              due: due!,
              repeat: note.dueRepeat,
              description:
                  strings.dueDescription?.call(due!, note.dueRepeat) ?? full,
              compactLabel: strings.dueCompactLabel?.call(due!, note.dueRepeat),
              label: _showCardStatusLabels ? full : null,
              upcoming:
                  note.dueRepeat != NoteRepeat.once ||
                  due!.isAfter(DateTime.now().toUtc()),
            ),
          ),
        if (note.attachmentCount > 0)
          mark(
            'attachment',
            _AttachedMark(label: strings.attachedShort(note.attachmentCount)),
          ),
        if (note.isUrgent)
          mark(
            'urgent',
            ExcludeSemantics(
              child: Icon(
                Icons.local_fire_department_outlined,
                key: const ValueKey('note-urgent-mark'),
                size: 15,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}
