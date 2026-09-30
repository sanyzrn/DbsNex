import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Changes the look of the whole app as a circle opening out from the last
/// touch, the new theme revealed under the old one.
///
/// Wraps the app once, above everything that changes with the theme, and is
/// told what the theme currently is through [signature]. When the signature
/// changes, the frame that is still on screen — the old theme — is taken as
/// a picture before anything repaints, laid over the app, and a hole grows
/// in it until the new theme is all that is left. Every way of changing the
/// theme gets it: the Theme page, a palette, the accent, the assistant, the
/// system switching to dark.
///
/// With animations off in the system it does nothing, and the theme changes
/// at once as it always did.
class NexThemeReveal extends StatefulWidget {
  const NexThemeReveal({
    super.key,
    required this.signature,
    required this.child,
    this.duration = const Duration(milliseconds: 650),
  });

  /// Anything that differs whenever the theme does.
  final Object signature;
  final Widget child;
  final Duration duration;

  @override
  State<NexThemeReveal> createState() => _NexThemeRevealState();
}

class _NexThemeRevealState extends State<NexThemeReveal>
    with SingleTickerProviderStateMixin {
  final _boundary = GlobalKey();
  late final AnimationController _reveal;
  late final Animation<double> _eased;

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(vsync: this, duration: widget.duration);
    _eased = CurvedAnimation(parent: _reveal, curve: Curves.easeInOutCubic);
  }

  ui.Image? _old;
  Offset? _origin;

  /// Where the last touch went down, and when: a theme is almost always
  /// changed by tapping something, and the circle opens from that tap.
  Offset? _lastTouch;
  DateTime _lastTouchAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void didUpdateWidget(NexThemeReveal old) {
    super.didUpdateWidget(old);
    if (old.signature == widget.signature) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    // Taken now, while this is being rebuilt and before anything below it
    // has been told about the new theme: what is on the layer is still the
    // old one.
    final picture = _capture();
    if (picture == null) return;
    _old?.dispose();
    final size = MediaQuery.maybeSizeOf(context) ?? Size.zero;
    final recent =
        DateTime.now().difference(_lastTouchAt) < const Duration(seconds: 3);
    _old = picture;
    _origin = recent && _lastTouch != null
        ? _lastTouch
        : size.center(Offset.zero);
    unawaited(
      _reveal.forward(from: 0).whenComplete(() {
        if (!mounted) return;
        setState(() {
          _old?.dispose();
          _old = null;
        });
      }),
    );
  }

  ui.Image? _capture() {
    final boundary = _boundary.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) return null;
    try {
      final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
      return boundary.toImageSync(pixelRatio: ratio);
    } catch (_) {
      // Nothing painted yet, or the layer is mid-change: no effect this time,
      // and the theme still changes.
      return null;
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    _old?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final old = _old;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _lastTouch = event.position;
        _lastTouchAt = DateTime.now();
      },
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          RepaintBoundary(key: _boundary, child: widget.child),
          if (old != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RevealPainter(
                    image: old,
                    origin: _origin ?? Offset.zero,
                    progress: _eased,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The old theme, with a hole of the new one growing in it.
class _RevealPainter extends CustomPainter {
  _RevealPainter({
    required this.image,
    required this.origin,
    required this.progress,
  }) : super(repaint: progress);

  final ui.Image image;
  final Offset origin;
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final reach = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((corner) => (corner - origin).distance).reduce(math.max);
    final radius = reach * progress.value;
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());
    paintImage(
      canvas: canvas,
      rect: bounds,
      image: image,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
    canvas.drawCircle(origin, radius, Paint()..blendMode = BlendMode.clear);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RevealPainter old) =>
      old.image != image || old.origin != origin;
}
