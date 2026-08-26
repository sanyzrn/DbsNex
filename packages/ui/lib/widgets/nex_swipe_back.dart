import 'package:flutter/material.dart';

/// The Cupertino slide transition, with a back-swipe that can start anywhere
/// on the page rather than only at its leading edge.
///
/// [CupertinoPageTransitionsBuilder] already gives every pushed route a
/// drag-to-pop, and it is the convention this app follows — a horizontal drag
/// away from the leading edge takes you back, mirrored under RTL so a Persian
/// reader drags the way the text runs. What it does not give is *reach*: the
/// gesture is only recognised inside a 20-logical-pixel strip at the very
/// edge, which on a large phone is the one part of the screen a thumb has to
/// stretch for. The back arrow is at the same far corner, so a screen with a
/// long list had two ways back and both of them were in the corner.
///
/// So the Cupertino transition is kept exactly as it is — it owns the motion,
/// and its own edge gesture keeps working — and the page it wraps gains a
/// second recogniser spanning the whole width. Anything horizontally
/// scrollable inside the page still wins the gesture arena against it: a
/// recogniser closer to the pointer beats one further up the tree, which is
/// why dragging a row of tag chips still scrolls the chips.
class NexSwipeBackPageTransitionsBuilder extends PageTransitionsBuilder {
  const NexSwipeBackPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return const CupertinoPageTransitionsBuilder().buildTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      // The first route has nothing behind it, and a full-screen route that
      // says it is not popped by a back gesture — a form guarding unsaved
      // work — must not be popped by this one either.
      route.isFirst ? child : _NexSwipeBack(child: child),
    );
  }
}

/// Follows a back-swipe with the page, and pops when it has gone far enough.
class _NexSwipeBack extends StatefulWidget {
  const _NexSwipeBack({required this.child});

  final Widget child;

  @override
  State<_NexSwipeBack> createState() => _NexSwipeBackState();
}

class _NexSwipeBackState extends State<_NexSwipeBack>
    with SingleTickerProviderStateMixin {
  /// How much of the width has to be crossed for a slow drag to count.
  static const _commitFraction = 0.35;

  /// A flick counts at any distance. In logical pixels per second, the same
  /// order as the Cupertino gesture's own threshold.
  static const _commitVelocity = 700.0;

  /// Built in [initState] rather than lazily: a page whose back-swipe is
  /// never declined never touches this, and a `late final` would then run its
  /// initialiser inside [dispose] — asking a deactivated element for the
  /// TickerMode above it, which throws.
  late final AnimationController _settle;

  /// Where the page was when a declined drag let go, so the settle back to
  /// rest is a fraction of that rather than of the screen.
  double _settleFrom = 0;

  /// How far the page has been dragged back, in logical pixels, never
  /// negative: dragging the other way is the page staying where it is.
  double _drag = 0;
  bool _popping = false;

  @override
  void initState() {
    super.initState();
    _settle =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 180),
        )..addListener(
          () => setState(() => _drag = _settleFrom * (1 - _settle.value)),
        );
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  /// +1 when back is to the right of the content, -1 when it is to the left.
  double get _sign =>
      Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;

  void _onStart(DragStartDetails details) {
    _settle.stop();
    _drag = 0;
  }

  void _onUpdate(DragUpdateDetails details) {
    if (_popping) return;
    final delta = (details.primaryDelta ?? 0) * _sign;
    setState(() => _drag = (_drag + delta).clamp(0.0, double.infinity));
  }

  void _onEnd(DragEndDetails details) {
    if (_popping) return;
    final width = context.size?.width ?? 0;
    final velocity = details.velocity.pixelsPerSecond.dx * _sign;
    final committed =
        velocity > _commitVelocity ||
        (velocity > -_commitVelocity && _drag > width * _commitFraction);
    if (committed) {
      _popping = true;
      Navigator.of(context).maybePop();
      return;
    }
    // Not far enough. The page goes back where it was rather than snapping,
    // which is what tells you the gesture was seen and declined.
    _settleFrom = _drag;
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _onStart,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      child: Transform.translate(
        offset: Offset(_drag * _sign, 0),
        child: widget.child,
      ),
    );
  }
}
