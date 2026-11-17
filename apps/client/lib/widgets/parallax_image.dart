import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

/// A picture filling its box that drifts against the scroll (2.8.2).
///
/// The picture is laid out a little taller than the box — at its own shape
/// up to [tallest] times the box's height, and never less than [shortest] —
/// and moves through the box as the box crosses the screen: its top shows
/// as the box comes up from the bottom of the list, its foot as the box
/// leaves at the top. A tall photo is seen whole that way, a little at a
/// time, instead of cut to a band.
///
/// Painted, never rebuilt: the movement is a [Flow] repainting from the
/// scroll position, so a list scrolling past a screenful of these rebuilds
/// no widget (the timeline's budget). Without a vertical scrollable above
/// it, or with animations off, the picture simply sits centred.
class NexParallaxImage extends StatelessWidget {
  const NexParallaxImage({
    super.key,
    required this.image,
    this.alignment = Alignment.center,
    this.shortest = 1.2,
    this.tallest = 2.6,
    this.errorBuilder,
  });

  final ImageProvider image;

  /// Where a picture sits when it does not drift.
  final Alignment alignment;
  final double shortest;
  final double tallest;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    final picture = Image(
      image: image,
      fit: BoxFit.cover,
      alignment: alignment,
      gaplessPlayback: true,
      errorBuilder: errorBuilder,
      frameBuilder: (context, child, frame, synchronous) => synchronous
          ? child
          : AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: NexMotion.of(context, NexMotion.exit),
              curve: NexMotion.curve,
              child: child,
            ),
    );
    final scrollable = Scrollable.maybeOf(context, axis: Axis.vertical);
    if (scrollable == null || MediaQuery.disableAnimationsOf(context)) {
      return SizedBox.expand(child: picture);
    }
    return Flow(
      clipBehavior: Clip.hardEdge,
      delegate: _Drift(
        scrollable: scrollable,
        box: context,
        shortest: shortest,
        tallest: tallest,
      ),
      children: [picture],
    );
  }
}

class _Drift extends FlowDelegate {
  _Drift({
    required this.scrollable,
    required this.box,
    required this.shortest,
    required this.tallest,
  }) : super(repaint: scrollable.position);

  final ScrollableState scrollable;
  final BuildContext box;
  final double shortest;
  final double tallest;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      BoxConstraints(
        minWidth: constraints.maxWidth,
        maxWidth: constraints.maxWidth,
        minHeight: constraints.maxHeight * shortest,
        maxHeight: constraints.maxHeight * tallest,
      );

  @override
  void paintChildren(FlowPaintingContext context) {
    final travel = (context.getChildSize(0)?.height ?? 0) - context.size.height;
    var along = 0.5;
    final viewport = scrollable.context.findRenderObject();
    final self = box.findRenderObject();
    if (viewport is RenderBox &&
        self is RenderBox &&
        self.attached &&
        viewport.attached &&
        viewport.hasSize &&
        self.hasSize) {
      final top = self.localToGlobal(Offset.zero, ancestor: viewport).dy;
      // 0 as the box enters at the bottom of the list, 1 as it leaves at the
      // top: the picture moves the other way, so its top shows first.
      along =
          (1 -
                  (top + context.size.height) /
                      (viewport.size.height + context.size.height))
              .clamp(0.0, 1.0);
    }
    context.paintChild(
      0,
      transform: Matrix4.translationValues(0, -travel * along, 0),
    );
  }

  @override
  bool shouldRepaint(_Drift old) =>
      scrollable != old.scrollable ||
      box != old.box ||
      shortest != old.shortest ||
      tallest != old.tallest;

  @override
  bool shouldRelayout(_Drift old) =>
      shortest != old.shortest || tallest != old.tallest;
}
