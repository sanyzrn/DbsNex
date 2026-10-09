part of '../timeline_screen.dart';

/// The day of the card at the top of the list, held under the filter row
/// while scrolling through older notes (W7.1).
///
/// The date groups say "This month" and "Older"; a card deep in "Older"
/// said nothing at all about when it was from until it was opened. The chip
/// names the day of whichever card is passing under the filter row, and is
/// the only thing that rebuilds as it changes — the list does not.
class TimelineStickyDay extends StatelessWidget {
  const TimelineStickyDay({super.key, required this.day});

  final ValueListenable<String?> day;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: day,
    builder: (context, label, _) {
      final theme = Theme.of(context);
      return IgnorePointer(
        child: AnimatedOpacity(
          opacity: label == null ? 0 : 1,
          duration: NexMotion.fast,
          child: Center(
            child: Container(
              margin: const EdgeInsets.only(top: NexSpacing.xs),
              padding: const EdgeInsets.symmetric(
                horizontal: NexSpacing.md,
                vertical: NexSpacing.xs,
              ),
              decoration: ShapeDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: StadiumBorder(
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                shadows: const [
                  BoxShadow(color: Color(0x1A000000), blurRadius: 8),
                ],
              ),
              child: Text(
                label ?? '',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// A note row, known to the sticky day while it is on screen. Only the
/// dozen or so rows the lazy list has built are ever registered.
class _DayMark extends StatefulWidget {
  const _DayMark({
    required this.label,
    required this.marks,
    required this.child,
  });

  final String label;
  final Set<_DayMarkState> marks;
  final Widget child;

  @override
  State<_DayMark> createState() => _DayMarkState();
}

class _DayMarkState extends State<_DayMark> {
  @override
  void initState() {
    super.initState();
    widget.marks.add(this);
  }

  @override
  void dispose() {
    widget.marks.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Working out the sticky day.
extension _TimelineStickyDay on TimelineScreenState {
  /// How far the list must have moved before the day is worth naming: at
  /// the top, the group headings already say it.
  static const _showAfter = 160.0;

  /// Names the day of the row that is passing under the filter row.
  void _updateStickyDay() {
    if (_searching || !_scroll.hasClients || _scroll.offset < _showAfter) {
      _stickyDay.value = null;
      return;
    }
    final anchor = _stickyLine.currentContext?.findRenderObject();
    if (anchor is! RenderBox || !anchor.attached || !anchor.hasSize) return;
    final line = anchor.localToGlobal(Offset(0, anchor.size.height)).dy;
    String? label;
    var top = double.infinity;
    for (final mark in _dayMarks) {
      final box = mark.context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y + box.size.height <= line) continue;
      if (y < top) {
        top = y;
        label = mark.widget.label;
      }
    }
    _stickyDay.value = label;
  }

  /// The words for a row's day: the group's own name for pinned notes, today
  /// and yesterday; otherwise the weekday and the date, in the calendar and
  /// digits the reader uses.
  String _dayLabel(Note note, AppLocalizations l10n) {
    if (note.pinnedAt != null) return l10n.timelineGroupPinned;
    final at = note.updatedAt.toLocal();
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(at.year, at.month, at.day)).inDays;
    if (days <= 0) return l10n.timelineGroupToday;
    if (days == 1) return l10n.timelineGroupYesterday;
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    final weekday = persian
        ? const [
            'دوشنبه',
            'سه‌شنبه',
            'چهارشنبه',
            'پنج‌شنبه',
            'جمعه',
            'شنبه',
            'یکشنبه',
          ][at.weekday - 1]
        : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][at.weekday -
              1];
    final date = nexDisplayDate(
      at,
      solar: widget.services.solarCalendar,
      persian: persian,
    );
    return persian ? '$weekday $date' : '$weekday, $date';
  }
}
