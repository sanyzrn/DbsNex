part of 'note_card.dart';

// Card statuses now live on the circular leading icon. The text preview
// remains a fixed-height envelope, with no ShaderMasks or GPU cutouts.
const _showCardStatusLabels = false;

class _CollapsedCardContent extends StatelessWidget {
  const _CollapsedCardContent({
    required this.note,
    required this.strings,
    required this.caption,
    required this.previewOverride,
  });

  final Note note;
  final NexCardStrings strings;
  final String? caption;
  final Widget? previewOverride;

  @override
  Widget build(BuildContext context) {
    final density = NexCardDensity.of(context);
    final rowHeight = nexCardPreviewLineHeightFor(context);
    final lines = density.lines - (caption == null ? 0 : 1);
    return SizedBox(
      height: nexCardHeightFor(context) - density.inset * 2,
      child: Column(
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
      ),
    );
  }
}

/// Solid circular status badges on the lower arc. Physical left-to-right
/// order matches the demo: attachment, priority, reminder. Only present
/// badges occupy space, and they never cause the card or preview to grow.
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final side = NexCardDensity.of(context).leading;
    final radius = side / 2;
    final full = due == null
        ? null
        : strings.dueLabel?.call(due!, note.dueRepeat);
    final badges = <({String id, Widget child})>[
      if (note.attachmentCount > 0)
        (
          id: 'attachment',
          child: _AttachedMark(
            label: strings.attachedShort(note.attachmentCount),
          ),
        ),
      if (note.isUrgent)
        (
          id: 'urgent',
          child: const ExcludeSemantics(
            // Emoji fonts are not guaranteed (Linux goldens had a blank fire).
            // Two vector layers make the flame stable on every platform.
            child: SizedBox(
              key: ValueKey('note-urgent-mark'),
              width: 14,
              height: 14,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.local_fire_department_rounded,
                    size: 15,
                    color: Color(0xFFE95432),
                  ),
                  Positioned(
                    bottom: 1,
                    child: Icon(
                      Icons.local_fire_department_rounded,
                      size: 7,
                      color: Color(0xFFFFCA52),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      if (due != null)
        (
          id: 'reminder',
          child: _DueChip(
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
    ];

    return SizedBox.square(
      dimension: side,
      child: Stack(
        key: const ValueKey('note-status-marks'),
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < badges.length; i++)
            Positioned(
              // Every badge stays inside this square's hit-test region.
              // The raised, slightly smaller circle ends above the badges.
              left: radius + (i - (badges.length - 1) / 2) * 16 - 8,
              top: side - (badges.length == 3 && i != 1 ? 20 : 16),
              child: Container(
                key: ValueKey('note-status-orbit-${badges[i].id}'),
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surfaceContainerLowest,
                ),
                child: badges[i].child,
              ),
            ),
        ],
      ),
    );
  }
}
