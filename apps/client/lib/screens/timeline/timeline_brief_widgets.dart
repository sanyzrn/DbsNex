part of '../timeline_screen.dart';

/// The brief's heading: its mark and name, the last update, and the arrow
/// that says the card folds — with the number of lines folded away beside
/// it, so a folded brief never looks like a whole one.
///
/// The mark is a sparkle in a soft accent disc that turns and settles once
/// each time a new brief arrives — the one moment the card has news — and
/// stays still otherwise. The plain report gets a list mark instead: nothing
/// in it was written by a model, and the card should not claim otherwise.
class _BriefHeader extends StatelessWidget {
  const _BriefHeader({
    required this.title,
    required this.byModel,
    required this.token,
    required this.collapsed,
    required this.hidden,
    this.updatedAt,
    this.solarCalendar = false,
  });

  final String title;
  final bool byModel;
  final Object? token;
  final DateTime? updatedAt;
  final bool solarCalendar;
  final bool collapsed;

  /// Lines the folded card is not showing; none hides the count.
  final int hidden;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final label = theme.textTheme.labelLarge?.copyWith(
      color: scheme.primary,
      fontWeight: FontWeight.w600,
    );
    final quiet = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w400,
    );
    final mark = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            scheme.primary.withValues(alpha: 0.2),
            scheme.tertiary.withValues(alpha: 0.12),
          ],
        ),
      ),
      child: SizedBox.square(
        dimension: 24,
        child: Icon(
          byModel ? Icons.auto_awesome : Icons.checklist_rtl,
          size: 14,
          color: scheme.primary,
        ),
      ),
    );
    final at = updatedAt;
    // The time goes under the name, not beside the arrow (2.8.1). On one row
    // the name and the time split the width between them, so the time was
    // cut short on a phone, and the count folding in and out pushed both
    // sideways at every tap. Now the name and its time are one block and
    // everything the fold changes lives in the pill at the end.
    return ExcludeSemantics(
      child: Row(
        children: [
          if (byModel)
            TweenAnimationBuilder<double>(
              key: ValueKey(token),
              tween: Tween(begin: 0, end: 1),
              duration: NexMotion.of(context, NexMotion.slow * 2),
              curve: Curves.easeOutBack,
              builder: (context, t, child) => Transform.rotate(
                angle: (1 - t) * -0.9,
                child: Transform.scale(scale: 0.7 + 0.3 * t, child: child),
              ),
              child: mark,
            )
          else
            mark,
          const SizedBox(width: NexSpacing.sm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (at != null)
                  SummaryUpdatedTime(at: at, solarCalendar: solarCalendar),
              ],
            ),
          ),
          const SizedBox(width: NexSpacing.sm),
          _FoldPill(
            collapsed: collapsed,
            more: hidden > 0 ? l10n.aiDaySummaryMore(hidden) : null,
            style: quiet,
          ),
        ],
      ),
    );
  }
}

/// What the brief's fold changes, in one place at the end of its heading:
/// how many lines are folded away and the arrow that opens them.
///
/// A soft pill of the accent, so the one control on the card reads as one.
/// Opening it, the count slides away into the arrow and the arrow turns
/// over with a little give; folding, the count slides back out. Only the
/// pill changes width — nothing else on the heading moves.
class _FoldPill extends StatelessWidget {
  const _FoldPill({required this.collapsed, required this.more, this.style});

  final bool collapsed;

  /// "3 more", while lines are folded away; null when nothing is.
  final String? more;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final count = more;
    final showCount = collapsed && count != null;
    final duration = NexMotion.of(context, NexMotion.slow);
    return AnimatedContainer(
      key: const ValueKey('brief-fold-pill'),
      duration: duration,
      curve: NexMotion.curve,
      padding: EdgeInsetsDirectional.fromSTEB(
        showCount ? NexSpacing.sm + 2 : NexSpacing.xs,
        NexSpacing.xs - 1,
        NexSpacing.xs,
        NexSpacing.xs - 1,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NexRadius.pill),
        // Open, the pill steps forward a shade: the card is in its other
        // state, and the control that returns it says so.
        color: scheme.primary.withValues(
          alpha: collapsed ? (dark ? 0.12 : 0.08) : (dark ? 0.2 : 0.14),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: duration,
            curve: NexMotion.curve,
            alignment: AlignmentDirectional.centerEnd,
            child: AnimatedSwitcher(
              duration: duration,
              switchInCurve: NexMotion.curve,
              switchOutCurve: NexMotion.exitCurve,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: animation.drive(
                    Tween(begin: const Offset(0.35, 0), end: Offset.zero),
                  ),
                  child: child,
                ),
              ),
              child: showCount
                  ? Padding(
                      key: ValueKey('brief-more-$count'),
                      padding: const EdgeInsetsDirectional.only(
                        end: NexSpacing.xs,
                      ),
                      child: Text(
                        count,
                        maxLines: 1,
                        style: style?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : const SizedBox(key: ValueKey('brief-no-more')),
            ),
          ),
          AnimatedRotation(
            // Folded, the arrow points down at what it would open; open, it
            // turns over to point back up — overshooting a touch, so the
            // turn reads as the card answering rather than a glyph swapped.
            turns: collapsed ? 0 : 0.5,
            duration: NexMotion.of(context, NexMotion.morph),
            curve: NexMotion.popCurve,
            child: Icon(
              Icons.expand_more,
              key: const ValueKey('brief-fold-arrow'),
              size: 18,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A line of the opened brief settling into place, a beat after the one
/// before it, so the fold opens as a list being read out rather than a block
/// dropped in.
class _ArrivingLine extends StatelessWidget {
  const _ArrivingLine({required this.index, required this.child});

  final int index;
  final Widget child;

  static const _beat = Duration(milliseconds: 45);

  @override
  Widget build(BuildContext context) {
    final lead = _beat * index.clamp(0, 6);
    final total = NexMotion.of(context, NexMotion.enter + lead);
    if (total == Duration.zero) return child;
    final start = lead.inMicroseconds / total.inMicroseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: NexMotion.curve),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 6),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// The brief's lines past its folded few (2.8.2).
///
/// Open, they are laid out as any line is. Folding, they used to leave on
/// the frame of the tap and the card then shrank round an empty space; now
/// they stay painted — taking no room, so the card's one size animation is
/// still the only one — and fade while the card closes over them. The same
/// widgets throughout, so a line that has arrived does not arrive again on
/// its way out.
class _FoldingLines extends StatefulWidget {
  const _FoldingLines({required this.open, required this.lines});

  final bool open;
  final List<Widget> lines;

  @override
  State<_FoldingLines> createState() => _FoldingLinesState();
}

class _FoldingLinesState extends State<_FoldingLines>
    with SingleTickerProviderStateMixin {
  late final _leave = AnimationController(vsync: this);
  late final Animation<double> _fading = ReverseAnimation(
    CurvedAnimation(parent: _leave, curve: NexMotion.exitCurve),
  );
  bool _leaving = false;

  @override
  void didUpdateWidget(_FoldingLines old) {
    super.didUpdateWidget(old);
    if (widget.open) {
      _leaving = false;
      _leave.stop();
      return;
    }
    if (!old.open && !_leaving) return;
    if (old.open) {
      // As long as the card takes to close.
      final duration = NexMotion.of(context, NexMotion.slow);
      if (duration == Duration.zero || old.lines.isEmpty) return;
      _leaving = true;
      _leave.duration = duration;
      _leave.forward(from: 0).whenComplete(() {
        if (mounted) setState(() => _leaving = false);
      });
    }
  }

  @override
  void dispose() {
    _leave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.open && !_leaving) return const SizedBox.shrink();
    final leaving = !widget.open;
    return IgnorePointer(
      ignoring: leaving,
      child: ExcludeSemantics(
        excluding: leaving,
        // No room of its own while leaving: painted below the folded lines,
        // where the card's bottom edge clips it as it closes.
        child: Align(
          alignment: AlignmentDirectional.topStart,
          heightFactor: leaving ? 0 : 1,
          child: FadeTransition(
            opacity: leaving ? _fading : kAlwaysCompleteAnimation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.lines,
            ),
          ),
        ),
      ),
    );
  }
}

/// Clips only what passes below the bottom edge: a mark that glows past the
/// sides or the top is left as it is.
class _BottomEdge extends CustomClipper<Rect> {
  const _BottomEdge();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-size.width, -size.height, size.width * 2, size.height);

  @override
  bool shouldReclip(_BottomEdge old) => false;
}

/// One line of the brief: its emoji in a column of its own, the words beside
/// it.
///
/// A hanging mark, the way a list is set. With the emoji inline, a line that
/// wrapped put its second row under the emoji rather than under the words,
/// and the width of each emoji — a phone and a stopwatch are not the same
/// width, and one drawn from the text font is narrower again — moved where
/// every line's words began. A column one emoji wide lines all of them up.
///
/// The line takes its own direction, so a Persian line in an English
/// interface puts its mark on the right.
class _BriefLine extends StatelessWidget {
  const _BriefLine(this.text, {this.folded = false, this.onOpen});

  final String text;

  /// The folded card shows each of its lines on one row.
  final bool folded;

  /// Opens the note this line was written from. Null for a line that is not
  /// about one note — a model's own sentence, a standing commitment — which
  /// leaves the tap to the card, as a fold.
  final VoidCallback? onOpen;

  /// The leading emoji, when the line starts with one: a first character that
  /// is neither a letter nor a digit, followed by a space.
  static (String, String)? split(String line) {
    final characters = line.characters;
    if (characters.length < 3) return null;
    final mark = characters.first;
    if (RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(mark)) return null;
    if (RegExp(r'^[\p{P}\s]', unicode: true).hasMatch(mark)) return null;
    final words = characters.skip(1).toString().trim();
    return words.isEmpty ? null : (mark, words);
  }

  @override
  Widget build(BuildContext context) {
    final direction = nexDirectionOf(text);
    final parts = split(text);
    final words = parts?.$2 ?? text;
    final paragraph = Text(
      words,
      maxLines: folded ? 1 : null,
      overflow: folded ? TextOverflow.ellipsis : TextOverflow.clip,
      textAlign: TextAlign.start,
      textDirection: direction,
    );
    final line = parts == null && onOpen == null
        ? paragraph
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (parts != null) ...[
                SizedBox(
                  // An emoji is about one and a quarter ems wide; the column
                  // grows with the text size so a large setting does not
                  // clip it.
                  width: MediaQuery.textScalerOf(context).scale(
                    (DefaultTextStyle.of(context).style.fontSize ?? 14) * 1.4,
                  ),
                  child: Text(parts.$1, textAlign: TextAlign.center),
                ),
                const SizedBox(width: NexSpacing.sm),
              ],
              Expanded(child: paragraph),
              // A line that leads to its note says so at its end, in the
              // direction it is read: the glyph turns round with the line.
              if (onOpen != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: NexSpacing.xs,
                    top: 2,
                  ),
                  child: Icon(
                    Icons.navigate_next_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
            ],
          );
    final open = onOpen;
    // Room above and below each line, inside what a tap on it reaches: a
    // line that opens a note is a link in a paragraph, and the gap between
    // two of them belongs to one or the other rather than to neither.
    final padded = Padding(
      padding: const EdgeInsets.symmetric(vertical: NexSpacing.xs - 1),
      child: Directionality(
        textDirection: direction ?? Directionality.of(context),
        child: line,
      ),
    );
    if (open == null) {
      return Semantics(label: text, excludeSemantics: true, child: padded);
    }
    return Semantics(
      label: text,
      link: true,
      excludeSemantics: true,
      onTap: open,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          nexTick();
          open();
        },
        child: padded,
      ),
    );
  }
}
