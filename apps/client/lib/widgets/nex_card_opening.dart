import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:nex_ui/nex_ui.dart';

/// Where a sheet is opening from: the card that was tapped, where it was on
/// screen, and a copy of it to hold in place while the sheet grows out of it.
class NexSheetOrigin {
  const NexSheetOrigin({required this.rect, required this.ghost});

  /// The card from the context of the widget that drew it, or null when it
  /// is no longer laid out anywhere a sheet could grow from.
  static NexSheetOrigin? of(BuildContext context, {required Widget ghost}) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return NexSheetOrigin(
      rect: box.localToGlobal(Offset.zero) & box.size,
      ghost: ghost,
    );
  }

  /// The card's whole slot, its outer margin included, in global coordinates.
  final Rect rect;

  /// The card, drawn again: the same widget the timeline built, without its
  /// tap.
  final Widget ghost;
}

/// The note sheet opening out of the card that was tapped (W7.3).
///
/// A sheet sliding up from the bottom edge says "something else came up",
/// when what happened is that this card opened. So, only while it opens:
///
/// - the sheet does not slide; it is drawn where it will come to rest and
///   shown through a rounded window that starts as the card's own outline
///   and grows to the sheet's;
/// - the card itself stays exactly where it was — icon, title, tag dots —
///   drawn over the growing window, and fades as the note's own content
///   fades in underneath it.
///
/// Everything after that is the ordinary sheet: dragging it, closing it,
/// the keyboard. Closing slides down as it always did, because by then the
/// card is behind the barrier, where it has been all along. With animations
/// off in the system none of this runs.
class NexCardOpening extends StatefulWidget {
  const NexCardOpening({super.key, required this.origin, required this.child});

  final NexSheetOrigin origin;
  final Widget child;

  @override
  State<NexCardOpening> createState() => _NexCardOpeningState();
}

class _NexCardOpeningState extends State<NexCardOpening> {
  Animation<double>? _route;
  OverlayEntry? _ghost;
  bool _done = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_route != null || _done) return;
    final route = ModalRoute.of(context)?.animation;
    if (route == null ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
        route.status == AnimationStatus.completed) {
      _done = true;
      return;
    }
    _route = route..addStatusListener(_status);
    WidgetsBinding.instance.addPostFrameCallback((_) => _showGhost());
  }

  void _showGhost() {
    if (!mounted || _done) return;
    final route = _route!;
    final origin = widget.origin;
    final entry = OverlayEntry(
      builder: (_) => Positioned.fromRect(
        rect: origin.rect,
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: route,
            builder: (_, child) => Opacity(
              opacity: 1 - _ghostFade.transform(route.value),
              child: child,
            ),
            child: origin.ghost,
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
    _ghost = entry;
  }

  void _status(AnimationStatus status) {
    if (status == AnimationStatus.forward) return;
    _finish();
  }

  void _finish() {
    _route?.removeStatusListener(_status);
    _ghost?.remove();
    _ghost = null;
    if (mounted && !_done) setState(() => _done = true);
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_status);
    _ghost?.remove();
    _ghost = null;
    super.dispose();
  }

  static const _ghostFade = Interval(0.2, 0.75, curve: Curves.easeOut);
  static const _contentFade = Interval(0, 0.45, curve: Curves.easeIn);
  static const _grow = Curves.easeInOutCubicEmphasized;

  @override
  Widget build(BuildContext context) {
    final route = _route;
    if (_done || route == null) return widget.child;
    final inset = nexCardInsets.resolve(Directionality.of(context));
    final from = inset.deflateRect(widget.origin.rect);
    final bottom = MediaQuery.sizeOf(context).height;
    return AnimatedBuilder(
      animation: route,
      builder: (_, child) => _Opening(
        from: from,
        restingBottom: bottom,
        grow: _grow.transform(route.value),
        opacity: _contentFade.transform(route.value),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _Opening extends SingleChildRenderObjectWidget {
  const _Opening({
    required this.from,
    required this.restingBottom,
    required this.grow,
    required this.opacity,
    super.child,
  });

  final Rect from;
  final double restingBottom;
  final double grow;
  final double opacity;

  @override
  _RenderOpening createRenderObject(BuildContext context) => _RenderOpening(
    from: from,
    restingBottom: restingBottom,
    grow: grow,
    opacity: opacity,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderOpening render) {
    render
      ..from = from
      ..restingBottom = restingBottom
      ..grow = grow
      ..opacity = opacity;
  }
}

class _RenderOpening extends RenderProxyBox {
  _RenderOpening({
    required Rect from,
    required double restingBottom,
    required double grow,
    required double opacity,
  }) : _from = from,
       _restingBottom = restingBottom,
       _grow = grow,
       _opacity = opacity;

  Rect _from;
  set from(Rect value) {
    if (value == _from) return;
    _from = value;
    markNeedsPaint();
  }

  double _restingBottom;
  set restingBottom(double value) {
    if (value == _restingBottom) return;
    _restingBottom = value;
    markNeedsPaint();
  }

  double _grow;
  set grow(double value) {
    if (value == _grow) return;
    _grow = value;
    markNeedsPaint();
  }

  double _opacity;
  set opacity(double value) {
    if (value == _opacity) return;
    _opacity = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  final _clip = LayerHandle<ClipRRectLayer>();
  final _fade = LayerHandle<OpacityLayer>();

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    // Where the sheet is being slid to by its route right now, against
    // where it will rest: the difference is undone, so the sheet is drawn
    // at rest from the first frame and only the window onto it moves.
    final now = localToGlobal(Offset.zero);
    final resting = _restingBottom - size.height;
    final lift = Offset(0, resting - now.dy);
    final target = lift & size;
    final card = _from.shift(-now);
    final window = Rect.lerp(card, target, _grow)!;
    final corner = NexRadius.lg + (NexRadius.xl - NexRadius.lg) * _grow;
    final bottomCorner = NexRadius.lg * (1 - _grow);
    final rrect = RRect.fromRectAndCorners(
      window,
      topLeft: Radius.circular(corner),
      topRight: Radius.circular(corner),
      bottomLeft: Radius.circular(math.max(0, bottomCorner)),
      bottomRight: Radius.circular(math.max(0, bottomCorner)),
    );
    // The note's content rides down with the window's top edge, so what
    // appears in it reads from the card's own first line.
    final ride = Offset(0, window.top - target.top);
    _clip.layer = context.pushClipRRect(
      needsCompositing,
      offset,
      window,
      rrect,
      (context, offset) {
        _fade.layer = context.pushOpacity(
          offset,
          (_opacity * 255).round(),
          (context, offset) => context.paintChild(child, offset + lift + ride),
          oldLayer: _fade.layer,
        );
      },
      oldLayer: _clip.layer,
    );
  }

  @override
  void dispose() {
    _clip.layer = null;
    _fade.layer = null;
    super.dispose();
  }
}
