import 'package:flutter/widgets.dart';

import '../tokens/nex_tokens.dart';
import 'nex_animated_size.dart';

/// What a segment shows, changing with it: the outgoing view fades as the
/// new one fades in and rises a touch, instead of one replacing the other on
/// a frame (2.8.2). [selection] is what tells them apart — a new value is a
/// new view; anything else the child rebuilds with stays in place.
///
/// Only for views whose state lives above them (fields owned by the screen,
/// lists read from its data): the outgoing view is a widget leaving, and
/// state kept inside it would go with it. A view that keeps its own state
/// across a switch keeps all its views built instead (as Gold Check's tabs do).
class NexSegmentSwap extends StatelessWidget {
  const NexSegmentSwap({
    super.key,
    required this.selection,
    required this.child,
    this.resize = false,
  });

  final Object selection;
  final Widget child;

  /// Eases the height from one view to the next, for a swap with more of
  /// the screen under it: without it, what is below waits for the old view
  /// to go and then jumps to the new one's height.
  final bool resize;

  @override
  Widget build(BuildContext context) {
    final swap = _swap(context);
    return resize ? NexAnimatedSize(child: swap) : swap;
  }

  Widget _swap(BuildContext context) => AnimatedSwitcher(
    duration: NexMotion.of(context, NexMotion.standard),
    reverseDuration: NexMotion.of(context, NexMotion.fast),
    switchInCurve: NexMotion.curve,
    switchOutCurve: NexMotion.exitCurve,
    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.topCenter,
      children: [
        for (final child in previous)
          IgnorePointer(child: ExcludeSemantics(child: child)),
        ?current,
      ],
    ),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: animation.drive(
          Tween(begin: const Offset(0, 0.012), end: Offset.zero),
        ),
        child: child,
      ),
    ),
    child: KeyedSubtree(key: ValueKey(selection), child: child),
  );
}
