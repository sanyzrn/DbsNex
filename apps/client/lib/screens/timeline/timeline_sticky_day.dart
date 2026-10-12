part of '../timeline_screen.dart';

/// The day of the card at the top of the list, held under the filter row
/// while scrolling through older notes (W7.1).
///
/// The date groups say "This month" and "Older"; a card deep in "Older"
/// said nothing at all about when it was from until it was opened. The chip
/// names the day of whichever card is passing under the filter row, and is
/// the only thing that rebuilds as it changes — the list does not.
class TimelineStickyDay extends StatefulWidget {
  const TimelineStickyDay({super.key, required this.day, this.scroll});

  final ValueListenable<String?> day;

  /// The list it names the days of: which way it moved says which way a
  /// new date rolls in.
  final ScrollController? scroll;

  @override
  State<TimelineStickyDay> createState() => _TimelineStickyDayState();
}

/// How the chip moves.
///
/// It drops out from under the filter row as the first dated card passes,
/// and tucks back under it — quicker, as leaving always is — when the list
/// returns to the top. While it is up, a new date rolls through it the way
/// the list is going: older days come up from below as you scroll down, and
/// newer ones down from above on the way back, while the chip eases to the
/// new width. It sits flat on the page, with a hairline and no shadow, so it
/// reads as part of the header rather than something floating over the
/// notes.
class _TimelineStickyDayState extends State<TimelineStickyDay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shown = AnimationController(
    vsync: this,
    duration: NexMotion.enter,
    reverseDuration: NexMotion.exit,
  );

  /// The last date shown, kept while the chip leaves so it does not empty
  /// before it has gone.
  String? _label;

  /// Whether the latest date is older than the one before it.
  bool _older = true;
  double? _offsetAtLabel;

  @override
  void initState() {
    super.initState();
    widget.day.addListener(_changed);
    _label = widget.day.value;
    if (_label != null) _shown.value = 1;
  }

  @override
  void didUpdateWidget(TimelineStickyDay old) {
    super.didUpdateWidget(old);
    if (old.day != widget.day) {
      old.day.removeListener(_changed);
      widget.day.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.day.removeListener(_changed);
    _shown.dispose();
    super.dispose();
  }

  void _changed() {
    final next = widget.day.value;
    if (next == null) {
      _shown.reverse();
      return;
    }
    final scroll = widget.scroll;
    final offset = scroll != null && scroll.hasClients ? scroll.offset : null;
    if (next != _label) {
      setState(() {
        final before = _offsetAtLabel;
        if (_label != null && offset != null && before != null) {
          _older = offset >= before;
        }
        _label = next;
        _offsetAtLabel = offset;
      });
    }
    _shown.forward();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    _shown
      ..duration = NexMotion.of(context, NexMotion.enter)
      ..reverseDuration = NexMotion.of(context, NexMotion.exit);
    final roll = NexMotion.of(context, NexMotion.standard);
    final from = _older ? 1.0 : -1.0;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _shown,
        builder: (context, child) {
          final t = _shown.status == AnimationStatus.reverse
              ? NexMotion.exitCurve.transform(_shown.value)
              : NexMotion.curve.transform(_shown.value);
          if (t == 0) return const SizedBox.shrink();
          return Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, -12 * (1 - t)),
              child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
            ),
          );
        },
        child: Center(
          child: Container(
            margin: const EdgeInsets.only(top: NexSpacing.xs),
            padding: const EdgeInsets.symmetric(
              horizontal: NexSpacing.md,
              vertical: NexSpacing.xs,
            ),
            decoration: ShapeDecoration(
              color: scheme.surfaceContainerHigh,
              shape: StadiumBorder(
                side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                  width: 0.8,
                ),
              ),
            ),
            child: AnimatedSize(
              duration: roll,
              curve: NexMotion.moveCurve,
              alignment: Alignment.center,
              child: ClipRect(
                child: AnimatedSwitcher(
                  duration: roll,
                  switchInCurve: NexMotion.curve,
                  switchOutCurve: NexMotion.exitCurve,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.center,
                    children: [...previous, ?current],
                  ),
                  transitionBuilder: (child, animation) {
                    final entering = child.key == ValueKey(_label);
                    final slide = Tween<Offset>(
                      begin: Offset(0, entering ? from : -from),
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: slide, child: child),
                    );
                  },
                  child: Text(
                    _label ?? '',
                    key: ValueKey(_label),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
