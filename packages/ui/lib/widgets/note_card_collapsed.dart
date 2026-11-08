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
    required this.backgroundColor,
    required this.due,
  });

  final Note note;
  final NexCardStrings strings;
  final Color backgroundColor;
  final DateTime? due;

  @override
  Widget build(BuildContext context) {
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
          child: ExcludeSemantics(
            child: SizedBox(
              key: const ValueKey('note-urgent-mark'),
              width: 14,
              height: 14,
              child: Center(
                // Android draws the requested coloured emoji. Linux test and
                // desktop fonts may not include it; keep a visible fallback.
                child: Platform.isLinux
                    ? const Icon(
                        Icons.local_fire_department_rounded,
                        size: 14,
                        color: Color(0xFFE95432),
                      )
                    : const Text(
                        '🔥',
                        style: TextStyle(fontSize: 14, height: 1),
                      ),
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

    final markSize = _noteStatusBadgeSize(context, badges.length);
    // Preserve the existing spacing angles; only the badge centres move
    // to the main circle's exact circumference.
    final statusRadius = radius - markSize / 2;
    final outerAngle = badges.length == 3
        ? math.asin(math.min(1, markSize / statusRadius))
        : math.min(math.pi / 4, math.asin((radius - markSize / 2) / radius));

    return SizedBox.square(
      dimension: side,
      child: Stack(
        key: const ValueKey('note-status-marks'),
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < badges.length; i++)
            Positioned(
              // The badge centre sits on the main circle's circumference.
              left:
                  _noteStatusCenter(
                    side,
                    radius,
                    (i - (badges.length - 1) / 2) *
                        (badges.length == 2 ? outerAngle * 2 : outerAngle),
                  ).dx -
                  markSize / 2,
              top:
                  _noteStatusCenter(
                    side,
                    radius,
                    (i - (badges.length - 1) / 2) *
                        (badges.length == 2 ? outerAngle * 2 : outerAngle),
                  ).dy -
                  markSize / 2,
              child: Container(
                key: ValueKey('note-status-orbit-${badges[i].id}'),
                width: markSize,
                height: markSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Exact card background, including selected tint.
                  color: backgroundColor,
                ),
                child: FittedBox(fit: BoxFit.scaleDown, child: badges[i].child),
              ),
            ),
        ],
      ),
    );
  }
}

/// Lower-arc marker centres are placed on the main circle's circumference.
Offset _noteStatusCenter(double side, double radius, double angle) {
  final center = side / 2;
  return Offset(
    center + radius * math.sin(angle),
    center + radius * math.cos(angle),
  );
}
