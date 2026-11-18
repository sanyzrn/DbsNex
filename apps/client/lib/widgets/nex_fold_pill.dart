import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

/// What a card's fold changes, in one place at the end of its heading —
/// the recap's and the tool dates' (2.8.6):
/// how many lines are folded away and the arrow that opens them.
///
/// A soft pill of the accent, so the one control on the card reads as one.
/// Opening it, the count slides away into the arrow and the arrow turns
/// over with a little give; folding, the count slides back out. Only the
/// pill changes width — nothing else on the heading moves.
class NexFoldPill extends StatelessWidget {
  const NexFoldPill({
    super.key,
    required this.id,
    required this.collapsed,
    required this.more,
    this.style,
  });

  /// Names the pill and its parts for tests: `<id>-fold-pill`,
  /// `<id>-fold-arrow`.
  final String id;

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
      key: ValueKey('$id-fold-pill'),
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
                      key: ValueKey('$id-more-$count'),
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
                  : SizedBox(key: ValueKey('$id-no-more')),
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
              key: ValueKey('$id-fold-arrow'),
              size: 18,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
