import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Paints [shapes] as one liquid: where two come close they reach for each
/// other and merge, and when they part a neck stretches and snaps.
///
/// The classic "gooey" technique, done on the canvas rather than with a
/// filtered widget subtree: every shape is drawn blurred into one layer, and
/// that layer is composited through a colour matrix that turns alpha into a
/// hard edge. Two blurs that overlap add up past the threshold before the
/// shapes themselves touch, which is the whole effect.
///
/// Cheap enough to run every frame of a short transition, because the layer
/// is bounded to [bounds] and the blur only ever touches a few small shapes —
/// never the screen. Callers paint the plain shape once the motion is over;
/// nothing here is meant to sit on screen at rest.
void nexPaintGooey(
  Canvas canvas, {
  required Rect bounds,
  required Color color,
  required Iterable<RRect> shapes,
  double softness = 7,
}) {
  // Alpha × 10, less 4.5 × 255: everything under ~45% coverage vanishes,
  // everything over ~55% is solid, and the 10% between is the anti-aliasing.
  const gain = 10.0;
  const threshold = <double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, gain, -4.5 * 255,
  ];
  // The threshold decides only *where* the liquid is. Its colour is laid on
  // afterwards through that shape: renderers disagree about whether a colour
  // matrix sees premultiplied pixels, and on the ones that do, the soft edge
  // of every blurred shape came out as a dark rim once its alpha was pushed
  // to opaque.
  canvas.saveLayer(bounds, Paint());
  canvas.saveLayer(
    bounds,
    Paint()..colorFilter = const ColorFilter.matrix(threshold),
  );
  final paint = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, softness);
  for (final shape in shapes) {
    if (shape.width <= 0.5 || shape.height <= 0.5) continue;
    canvas.drawRRect(shape, paint);
  }
  canvas.restore();
  canvas.drawRect(
    bounds,
    Paint()
      ..color = color.withValues(alpha: 1)
      ..blendMode = BlendMode.srcIn,
  );
  canvas.restore();
}

/// A circle as the rounded rectangle [nexPaintGooey] takes.
RRect nexGooeyCircle(Offset center, double radius) => RRect.fromRectAndRadius(
  Rect.fromCircle(center: center, radius: math.max(radius, 0)),
  Radius.circular(math.max(radius, 0)),
);

/// The light of the assistant opening: a ring of its spectrum sweeps out
/// across the whole screen from the button that was held.
///
/// Played in the root overlay and removed when it ends. It takes no touches.
/// The panel's own arrival out of the button is [NexEmergeFrom].
abstract final class NexAssistantLaunch {
  static const duration = Duration(milliseconds: 900);

  /// [origin] is the held button's global rectangle.
  static void play(
    BuildContext context, {
    required Rect origin,
    required List<Color> spectrum,
  }) {
    if (MediaQuery.disableAnimationsOf(context)) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _Launch(
        origin: origin,
        spectrum: spectrum,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

class _Launch extends StatefulWidget {
  const _Launch({
    required this.origin,
    required this.spectrum,
    required this.onDone,
  });

  final Rect origin;
  final List<Color> spectrum;
  final VoidCallback onDone;

  @override
  State<_Launch> createState() => _LaunchState();
}

class _LaunchState extends State<_Launch> with SingleTickerProviderStateMixin {
  late final AnimationController _t;

  @override
  void initState() {
    super.initState();
    _t = AnimationController(
      vsync: this,
      duration: NexAssistantLaunch.duration,
    );
    unawaited(_t.forward().whenComplete(() => widget.onDone()));
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _LaunchPainter(
            progress: _t,
            origin: widget.origin,
            spectrum: widget.spectrum,
          ),
        ),
      ),
    ),
  );
}

class _LaunchPainter extends CustomPainter {
  _LaunchPainter({
    required this.progress,
    required this.origin,
    required this.spectrum,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Rect origin;
  final List<Color> spectrum;

  static double _span(
    double t,
    double a,
    double b, [
    Curve curve = Curves.linear,
  ]) => curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    _wave(canvas, size, t);
  }

  /// A ring of the spectrum travelling out from the button to the far
  /// corners, soft on both sides, fading as it goes.
  void _wave(Canvas canvas, Size size, double t) {
    final center = origin.center;
    final reach = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((c) => (c - center).distance).reduce(math.max);
    final p = _span(t, 0, 1, Curves.easeOutCubic);
    final radius = 24 + (reach + 80) * p;
    final band = 70 + 60 * p;
    final alpha = (1 - _span(t, 0.45, 1)) * 0.75;
    if (alpha <= 0) return;
    final bounds = Rect.fromCircle(center: center, radius: radius + band);
    canvas.saveLayer(bounds, Paint());
    canvas.drawCircle(
      center,
      radius + band,
      Paint()
        // The whole spectrum across the upper half, where the ring is
        // actually seen: spread around a full turn, most of it would be
        // below the button and off the screen.
        ..shader = SweepGradient(
          startAngle: math.pi,
          endAngle: 2 * math.pi,
          tileMode: TileMode.mirror,
          transform: GradientRotation(t * math.pi / 3),
          colors: spectrum,
        ).createShader(bounds),
    );
    // Keep only a soft band around the ring's radius.
    final inner = ((radius - band) / (radius + band)).clamp(0.0, 1.0);
    final middle = (radius / (radius + band)).clamp(0.0, 1.0);
    canvas.drawRect(
      bounds,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.Gradient.radial(
          center,
          radius + band,
          [
            Colors.transparent,
            Colors.transparent,
            Colors.white.withValues(alpha: alpha),
            Colors.transparent,
          ],
          [0, inner, middle, 1],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LaunchPainter old) =>
      old.origin != origin || old.spectrum != spectrum;
}

/// The liquid bridge between two circles, as a closed path — the neck that
/// forms when two drops are near and thins until it breaks as they part.
///
/// Analytic rather than blurred, so it is crisp at any size and costs a few
/// trigonometric calls. Null when the circles are too far apart to be joined
/// (the neck has broken) or one contains the other.
///
/// [spread] (0–1) is how far round each circle the neck takes hold; the
/// defaults are the classic metaball proportions.
Path? nexMetaballBridge(
  Offset c1,
  double r1,
  Offset c2,
  double r2, {
  double spread = 0.5,
  double handle = 2.4,
  double reach = 2.5,
}) {
  final d = (c2 - c1).distance;
  if (r1 <= 0 || r2 <= 0) return null;
  if (d > r1 + r2 * reach || d <= (r1 - r2).abs()) return null;
  double clampCos(double v) => math.acos(v.clamp(-1.0, 1.0));
  final u1 = d < r1 + r2
      ? clampCos((r1 * r1 + d * d - r2 * r2) / (2 * r1 * d))
      : 0.0;
  final u2 = d < r1 + r2
      ? clampCos((r2 * r2 + d * d - r1 * r1) / (2 * r2 * d))
      : 0.0;
  final between = math.atan2(c2.dy - c1.dy, c2.dx - c1.dx);
  final maxSpread = clampCos((r1 - r2) / d);
  final a1 = between + u1 + (maxSpread - u1) * spread;
  final a2 = between - u1 - (maxSpread - u1) * spread;
  final a3 = between + math.pi - u2 - (math.pi - u2 - maxSpread) * spread;
  final a4 = between - math.pi + u2 + (math.pi - u2 - maxSpread) * spread;
  Offset polar(Offset c, double a, double r) =>
      c + Offset(math.cos(a) * r, math.sin(a) * r);
  final p1 = polar(c1, a1, r1);
  final p2 = polar(c1, a2, r1);
  final p3 = polar(c2, a3, r2);
  final p4 = polar(c2, a4, r2);
  final total = r1 + r2;
  final base = math.min(spread * handle, (p1 - p3).distance / total);
  final d2 = base * math.min(1.0, d * 2 / total);
  final h1 = polar(p1, a1 - math.pi / 2, r1 * d2);
  final h2 = polar(p2, a2 + math.pi / 2, r1 * d2);
  final h3 = polar(p3, a3 + math.pi / 2, r2 * d2);
  final h4 = polar(p4, a4 - math.pi / 2, r2 * d2);
  return Path()
    ..moveTo(p1.dx, p1.dy)
    ..cubicTo(h1.dx, h1.dy, h3.dx, h3.dy, p3.dx, p3.dy)
    ..lineTo(p4.dx, p4.dy)
    ..cubicTo(h4.dx, h4.dy, h2.dx, h2.dy, p2.dx, p2.dy)
    ..close();
}

/// A modal sheet that grows out of a button instead of sliding up.
///
/// Wrap a modal bottom sheet's content in this with the button's global
/// rectangle. While the route is arriving, the sheet is held where it will
/// rest — the route's own slide is cancelled, curve for curve — and revealed
/// through a liquid shape: the button swells, a drop climbs out of it on a
/// neck that stretches and snaps, and the drop spreads into the panel, still
/// in the button's colour, before that colour clears to show the content.
///
/// Only the arrival. Once the route has fully arrived this is its child and
/// nothing else, so dragging and dismissing the sheet behave exactly as they
/// always did.
class NexEmergeFrom extends StatefulWidget {
  const NexEmergeFrom({
    super.key,
    required this.origin,
    required this.color,
    required this.child,
    this.radius = 28,
  });

  /// The button's rectangle in global coordinates, or null for a plain sheet.
  final Rect? origin;

  /// The button's fill, which the liquid starts as.
  final Color color;

  /// The sheet's top corner radius.
  final double radius;

  final Widget child;

  @override
  State<NexEmergeFrom> createState() => _NexEmergeFromState();
}

class _NexEmergeFromState extends State<NexEmergeFrom> {
  Animation<double>? _route;
  bool _settled = false;

  /// Where the sheet's top will rest, in global coordinates — measured, not
  /// assumed: the route, a safe area or a width cap can all move it. The
  /// first frame guesses from the screen height; every later one knows.
  final _content = GlobalKey();
  double? _restTop;

  void _measure() {
    final box = _content.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !mounted) return;
    // The route's slide and this widget's counter-slide cancel, so where
    // the content is drawn now is where it will rest.
    final top = box.localToGlobal(Offset.zero).dy;
    if (top != _restTop) setState(() => _restTop = top);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context)?.animation;
    if (route == _route) return;
    _route?.removeStatusListener(_status);
    _route = route?..addStatusListener(_status);
    if (route == null || route.status == AnimationStatus.completed) {
      _settled = true;
    }
  }

  void _status(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_settled) {
      setState(() => _settled = true);
    }
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_status);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    final origin = widget.origin;
    if (_settled ||
        route == null ||
        origin == null ||
        MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    final screen = MediaQuery.sizeOf(context).height;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return AnimatedBuilder(
      animation: route,
      child: widget.child,
      builder: (context, child) {
        final v = route.value;
        // The bottom sheet moves its child down by (1 - curve(v)) of the
        // child's height, with this curve. Moving it back up by the same
        // fraction leaves it standing where it will rest.
        final slide = Easing.legacyDecelerate.transform(v);
        return FractionalTranslation(
          translation: Offset(0, -(1 - slide)),
          child: ClipPath(
            clipper: _EmergeClipper(
              progress: v,
              origin: origin,
              restTop: _restTop,
              screenHeight: screen,
              radius: widget.radius,
            ),
            child: Stack(
              key: _content,
              children: [
                child!,
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      // The button's colour only while the liquid is small.
                      // It turns toward the panel's own surface as it
                      // climbs, so by the time it is panel-sized it is
                      // nearly the panel — a large block of saturated
                      // accent flashed across the sheet before, most
                      // visibly in the dark theme — and then clears to
                      // show what is on it.
                      color: Color.lerp(
                        widget.color,
                        // The panel, with a breath of the button left in it.
                        Color.alphaBlend(
                          widget.color.withValues(alpha: .22),
                          Theme.of(context).colorScheme.surface,
                        ),
                        _EmergeClipper.span(v, .12, .42, Curves.easeIn),
                      )!.withValues(alpha: 1 - _EmergeClipper.span(v, .42, .7)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmergeClipper extends CustomClipper<Path> {
  _EmergeClipper({
    required this.progress,
    required this.origin,
    required this.restTop,
    required this.screenHeight,
    required this.radius,
  });

  final double progress;
  final Rect origin;
  final double? restTop;
  final double screenHeight;
  final double radius;

  static double span(double t, double a, double b, [Curve c = Curves.linear]) =>
      c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Path getClip(Size size) {
    final t = progress;
    // Before the first measurement: a bottom sheet rests against the bottom
    // of the screen.
    final top = restTop ?? screenHeight - size.height;
    final button = origin.center - Offset(0, top);
    final r = origin.shortestSide / 2;
    final full = Offset.zero & size;

    final swell = r * (1 + 0.2 * span(t, 0, .15, Curves.easeOut));
    final buttonRadius = swell * (1 - span(t, .34, .6, Curves.easeIn));
    final rise = span(t, 0, .38, Curves.easeInOutCubic);
    // The drop climbs to where the panel's top edge will rest and spreads
    // from there — down and out — rather than swelling in mid-air and
    // jumping to full size.
    final dropRadius = ui.lerpDouble(r * .7, r * 1.5, rise)!;
    final dropCenter = Offset.lerp(
      button,
      Offset(size.width / 2, dropRadius + 6),
      rise,
    )!;
    final grow = span(t, .28, .92, const Cubic(0.2, 0.9, 0.3, 1.04));
    final from = Rect.fromCircle(center: dropCenter, radius: dropRadius);
    final body = Rect.lerp(from, full, grow)!;
    // easeOutBack overshoots past 1 on purpose — the panel lands with a
    // little give — so the radii are clamped rather than trusted.
    final corner = math.max(ui.lerpDouble(dropRadius, radius, grow)!, 0.0);
    final base = math.max(ui.lerpDouble(dropRadius, 0, grow)!, 0.0);
    final panel = Path()
      ..addRRect(
        RRect.fromRectAndCorners(
          body,
          topLeft: Radius.circular(corner),
          topRight: Radius.circular(corner),
          bottomLeft: Radius.circular(base),
          bottomRight: Radius.circular(base),
        ),
      );
    var shape = panel;
    if (buttonRadius > 0.5) {
      shape = Path.combine(
        PathOperation.union,
        shape,
        Path()..addOval(Rect.fromCircle(center: button, radius: buttonRadius)),
      );
      // A long reach: the neck is meant to stretch the whole way up and give
      // only when the button lets go of it.
      final neck = nexMetaballBridge(
        button,
        buttonRadius,
        dropCenter,
        math.max(dropRadius, 1),
        reach: 8,
      );
      if (neck != null && grow < .5) {
        shape = Path.combine(PathOperation.union, shape, neck);
      }
    }
    return shape;
  }

  @override
  bool shouldReclip(_EmergeClipper old) =>
      old.progress != progress ||
      old.origin != origin ||
      old.restTop != restTop ||
      old.screenHeight != screenHeight;
}
