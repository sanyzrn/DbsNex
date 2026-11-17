import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../tokens/nex_appearance.dart';
import '../tokens/nex_tokens.dart';

/// One floating home dock. The capture button rises out of the same surface
/// as the four quieter destinations instead of separating them into islands.
///
/// The empty centre is a real gap in the hit targets: a tap beside capture
/// cannot accidentally open a different destination underneath it.
class NexNavigationDock extends StatelessWidget {
  const NexNavigationDock({
    super.key,
    required this.leading,
    required this.capture,
    required this.trailing,
    this.recede,
    this.away = false,
  });

  final List<Widget> leading;
  final Widget capture;
  final List<Widget> trailing;

  /// How far the four destinations have stepped back: 0 with the whole dock
  /// there, 1 with only capture left. The home screen runs it while someone
  /// reads down the list, so the notes have the bottom of the screen and the
  /// one primary action never moves from under the thumb.
  ///
  /// Stepping back, the capsule draws in to capture from both ends and sinks
  /// a little, its four places gathering towards the centre as they fade,
  /// and capture swells once as it takes them in (2.8.1). Coming back, the
  /// capsule opens out of capture again. The value may run a little below 0
  /// on the way back — a curve with give — and the capsule opens a touch
  /// past its width before it settles.
  ///
  /// Only the dock repaints while it runs; nothing above it is rebuilt.
  final Animation<double>? recede;

  /// Whether the destinations are stepped back. Faded out they must not be
  /// tappable or read out either: a control nobody can see is a trap.
  final bool away;

  static const height = 64.0;
  static const lift = 24.0;
  static const maxWidth = 352.0;
  static const _centreGap = 72.0;

  @override
  Widget build(BuildContext context) {
    assert(leading.length == 2 && trailing.length == 2);
    final visual = context.nexVisualStyle;
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final viewport = MediaQuery.sizeOf(context).width;
    // On a narrow window the outer margin gives way before any 48dp target
    // does. The five controls need 256dp even at their tightest spacing.
    final width = (viewport < 304 ? viewport : viewport - NexSpacing.md * 2)
        .clamp(0.0, maxWidth);
    final narrow = width < 288;
    final edge = narrow ? NexSpacing.xs : NexSpacing.sm;
    final gap = narrow ? 56.0 : _centreGap;
    final radius = BorderRadius.circular(height / 2);
    final actions = Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: edge),
        child: Row(
          // Places stay put when the interface language changes. The text in
          // tooltips still inherits the ambient direction.
          textDirection: TextDirection.ltr,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final action in leading)
              SizedBox.square(dimension: nexMinTapTarget, child: action),
            SizedBox(width: gap),
            for (final action in trailing)
              SizedBox.square(dimension: nexMinTapTarget, child: action),
          ],
        ),
      ),
    );
    Widget capsule(Widget places) => Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        // Dark and Night separate by tone; Light gets a quiet lift.
        // Glass already paints its own optical edge and shadow.
        boxShadow: visual.liquidGlass || dark
            ? null
            : [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      // Paint after the opaque surface so it cannot cover the edge.
      foregroundDecoration: visual.liquidGlass
          ? null
          : BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: highContrast ? scheme.outline : scheme.outlineVariant,
                width: highContrast ? 1 : 0.75,
              ),
            ),
      child: NexGlassSurface(
        material: NexGlassMaterial.floating,
        borderRadius: radius,
        // White in Light; the elevated neutral tone in Dark/Night.
        fallbackColor: dark ? scheme.surfaceContainerHigh : scheme.surface,
        // The places keep the dock's whole width while the capsule draws in
        // round them, so they are tucked away by its ends rather than
        // squeezed into each other.
        child: ClipRRect(
          borderRadius: radius,
          child: OverflowBox(minWidth: width, maxWidth: width, child: places),
        ),
      ),
    );
    // Built once. While the dock steps back or returns, its layout, fade and
    // transforms follow [recede] in the render tree — no widget rebuilds, so
    // a scroll that sets it going costs the timeline's budget nothing.
    final t = recede ?? const AlwaysStoppedAnimation<double>(0);
    final along = _Mapped(t, (v) => v.clamp(0.0, 1.0));
    return SizedBox(
      width: width,
      height: height + lift,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: height,
            child: IgnorePointer(
              ignoring: away,
              child: ExcludeSemantics(
                excluding: away,
                child: CustomSingleChildLayout(
                  delegate: _CapsuleLayout(t),
                  // The capsule fades only once it is mostly gone behind
                  // capture.
                  child: FadeTransition(
                    opacity: _Mapped(
                      along,
                      (v) => 1 - ((v - 0.6) / 0.4).clamp(0.0, 1.0),
                    ),
                    child: capsule(
                      // The places go first, by the time the capsule is half
                      // drawn in, gathering towards capture as they go.
                      FadeTransition(
                        key: const ValueKey('dock-destinations'),
                        opacity: _Mapped(
                          along,
                          (v) => 1 - (v / 0.5).clamp(0.0, 1.0),
                        ),
                        child: _AnimatedScale(
                          scale: _Mapped(along, (v) => 1 - 0.3 * v),
                          child: actions,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              // Capture takes the dock in: one swell, back to its own size by
              // the end, so where it sits never changes.
              child: _AnimatedScale(
                scale: _Mapped(along, (v) => 1 + 0.08 * math.sin(math.pi * v)),
                child: capture,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// [parent] seen through [map], without a widget to do the mapping.
class _Mapped extends Animation<double> with AnimationWithParentMixin<double> {
  _Mapped(this.parent, this.map);

  @override
  final Animation<double> parent;
  final double Function(double) map;

  @override
  double get value => map(parent.value);
}

/// The capsule at [t] of the way to only capture: drawn in to a circle under
/// it at 1 and sunk a little; a little below 0 on the way back, a touch wider
/// than the dock, which is the give.
class _CapsuleLayout extends SingleChildLayoutDelegate {
  _CapsuleLayout(this.t) : super(relayout: t);

  final Animation<double> t;

  double _inset(Size size) =>
      (size.width - size.height) / 2 * t.value.clamp(-0.04, 1.0);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final size = constraints.biggest;
    return BoxConstraints.tight(
      Size(math.max(size.height, size.width - 2 * _inset(size)), size.height),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      Offset((size.width - childSize.width) / 2, 6 * t.value.clamp(0.0, 1.0));

  @override
  bool shouldRelayout(_CapsuleLayout old) => old.t != t;
}

/// Scales its child about its centre as [scale] runs, repainting rather than
/// rebuilding.
class _AnimatedScale extends SingleChildRenderObjectWidget {
  const _AnimatedScale({required this.scale, super.child});

  final Animation<double> scale;

  @override
  _RenderAnimatedScale createRenderObject(BuildContext context) =>
      _RenderAnimatedScale(scale);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAnimatedScale renderObject,
  ) => renderObject.scale = scale;
}

class _RenderAnimatedScale extends RenderProxyBox {
  _RenderAnimatedScale(this._scale);

  Animation<double> _scale;
  set scale(Animation<double> value) {
    if (value == _scale) return;
    if (attached) _scale.removeListener(markNeedsPaint);
    _scale = value;
    if (attached) _scale.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _scale.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _scale.removeListener(markNeedsPaint);
    super.detach();
  }

  Matrix4 get _transform {
    final s = _scale.value;
    final centre = size.center(Offset.zero);
    return Matrix4.identity()
      ..translateByDouble(centre.dx, centre.dy, 0, 1)
      ..scaleByDouble(s, s, 1, 1)
      ..translateByDouble(-centre.dx, -centre.dy, 0, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    if (_scale.value == 1) {
      layer = null;
      context.paintChild(child!, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      (context, offset) => context.paintChild(child!, offset),
      oldLayer: layer is TransformLayer ? layer as TransformLayer? : null,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintTransform(
        transform: _scale.value == 1 ? null : _transform,
        position: position,
        hitTest: (result, position) =>
            super.hitTestChildren(result, position: position),
      );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (_scale.value != 1) transform.multiply(_transform);
  }
}

/// A full-sized destination in the home dock, with a fixed place for a badge.
///
/// Under a finger its glyph gives a little and springs back on the way up:
/// the dock's four places have no labels, so the press itself is what says
/// "this one" before the page it leads to arrives.
class NexDockAction extends StatefulWidget {
  const NexDockAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badge,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Widget? badge;

  @override
  State<NexDockAction> createState() => _NexDockActionState();
}

class _NexDockActionState extends State<NexDockAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    child: InkResponse(
      onTap: widget.onPressed,
      onHighlightChanged: (down) {
        if (down != _pressed) setState(() => _pressed = down);
      },
      radius: nexMinTapTarget / 2,
      containedInkWell: true,
      customBorder: const CircleBorder(),
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AnimatedScale(
                scale: _pressed ? 0.86 : 1,
                duration: NexMotion.of(
                  context,
                  _pressed ? NexMotion.fast : NexMotion.pop,
                ),
                curve: _pressed ? NexMotion.curve : NexMotion.popCurve,
                child: Icon(widget.icon, size: 22),
              ),
            ),
            if (widget.badge case final mark?)
              Positioned(top: 9, right: 9, child: mark),
          ],
        ),
      ),
    ),
  );
}
