import 'dart:async';
import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';

/// The light that runs around the inside of the screen while a long press is
/// being held, the way Android's assistant and iOS's do it.
///
/// A border rather than a scrim: the point is to say "something is listening
/// at the edge of the app" without hiding the app. Nothing here is
/// interactive — it paints above everything and takes no hits — so a press
/// that gets cancelled leaves nothing behind but the animation running out.
///
/// [progress] is the whole control surface. 0 is invisible; 1 is fully lit.
/// Drive it from the press itself and the glow tracks the finger, which is
/// what makes it feel like a response rather than a cutscene.
class NexEdgeGlow extends StatelessWidget {
  const NexEdgeGlow({super.key, required this.progress, required this.colors});

  final double progress;

  /// Swept around the edge in order and back to the first, so the gradient
  /// closes on itself instead of showing a seam at twelve o'clock.
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    if (progress <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _EdgeGlowPainter(progress: progress, colors: colors),
        ),
      ),
    );
  }
}

/// A shortcut's colour traces the perimeter from the bottom in the physical
/// direction of the swipe. Distance, rather than time, controls its reach.
class NexEdgeTrace extends StatelessWidget {
  const NexEdgeTrace({
    super.key,
    required this.progress,
    required this.color,
    required this.toRight,
    this.opacity = 1,
  });

  final double progress;
  final Color color;
  final bool toRight;
  final double opacity;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _EdgeTracePainter(
          progress: progress,
          color: color,
          toRight: toRight,
          opacity: opacity,
        ),
      ),
    ),
  );
}

class _EdgeTracePainter extends CustomPainter {
  _EdgeTracePainter({
    required this.progress,
    required this.color,
    required this.toRight,
    required this.opacity,
  });

  final double progress;
  final Color color;
  final bool toRight;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || opacity <= 0 || size.isEmpty) return;
    final rect = (Offset.zero & size).deflate(2);
    final r = math.min(44.0, rect.shortestSide / 2);
    final corner = Radius.circular(r);
    // Bottom centre → bottom right → top right → top left → bottom left.
    final path = Path()
      ..moveTo(rect.center.dx, rect.bottom)
      ..lineTo(rect.right - r, rect.bottom)
      ..arcToPoint(
        Offset(rect.right, rect.bottom - r),
        radius: corner,
        clockwise: false,
      )
      ..lineTo(rect.right, rect.top + r)
      ..arcToPoint(
        Offset(rect.right - r, rect.top),
        radius: corner,
        clockwise: false,
      )
      ..lineTo(rect.left + r, rect.top)
      ..arcToPoint(
        Offset(rect.left, rect.top + r),
        radius: corner,
        clockwise: false,
      )
      ..lineTo(rect.left, rect.bottom - r)
      ..arcToPoint(
        Offset(rect.left + r, rect.bottom),
        radius: corner,
        clockwise: false,
      )
      ..close();
    final metric = path.computeMetrics().single;
    final trace = progress >= 1
        ? path
        : metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0));
    canvas.save();
    if (!toRight) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    canvas.drawPath(
      trace,
      Paint()
        ..color = color.withValues(alpha: 0.45 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      trace,
      Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EdgeTracePainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.toRight != toRight ||
      old.opacity != opacity;
}

class _EdgeGlowPainter extends CustomPainter {
  _EdgeGlowPainter({required this.progress, required this.colors});

  final double progress;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    // Eased twice over. `easeOutSine` does the visible work — it opens
    // immediately and then keeps almost the whole hold at gentle, even
    // brightening, where the old cubic put a lurch in the first sixth and
    // then crawled. The width and the blur ride a slower curve than the
    // brightness below, which is what stops the ring from appearing at full
    // thickness the instant a finger lands.
    final p = progress.clamp(0.0, 1.0);
    final t = Curves.easeOutSine.transform(p);
    final spread = Curves.easeInOutCubic.transform(p);

    // The screen's own corner radius is unknowable, so this uses a generous
    // one: too round on a square-cornered phone is far less noticeable than
    // too square on a rounded one, where the glow would cut across the
    // display's actual corner.
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(1),
      const Radius.circular(44),
    );

    final sweep = SweepGradient(
      // Starts at the bottom, under the capture button the press began on,
      // and turns as the hold builds. A fixed gradient reads as a picture of
      // a glow; a moving one reads as light, and it costs nothing — the
      // rotation comes off the same value that is already animating, so
      // there is no second ticker driving it.
      transform: GradientRotation(math.pi / 2 + spread * math.pi * 0.55),
      colors: [...colors, colors.first],
    ).createShader(rect);

    // The two soft passes are the expensive part — a wide stroke under a
    // large blur, around the whole screen — and they were redrawn on every
    // frame of the hold and of the hand-off, the same frames the assistant's
    // sheet is rising in. That was the stutter when the assistant opened.
    // They are drawn once per screen size into an image now, and each frame
    // only fades that image; the thin line on top stays live, so the light
    // still turns as the hold builds.
    final bloom = _Bloom.of(size, rrect, colors);
    canvas.drawImage(
      bloom,
      Offset.zero,
      Paint()
        ..filterQuality = FilterQuality.low
        ..color = Colors.white.withValues(alpha: (t * spread).clamp(0.0, 1.0)),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = sweep
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 + 2 * spread
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + spread)
        ..color = Colors.white.withValues(alpha: t),
    );
  }

  @override
  bool shouldRepaint(_EdgeGlowPainter old) =>
      old.progress != progress || old.colors != colors;
}

/// The glow's soft passes, rendered once and reused.
///
/// One entry: the screen is one size at a time, and a rotation or resize
/// simply replaces it.
class _Bloom {
  static Size? _size;
  static List<Color>? _colors;
  static ui.Image? _image;

  static ui.Image of(Size size, RRect rrect, List<Color> colors) {
    final cached = _image;
    if (cached != null && _size == size && listEquals(_colors, colors)) {
      return cached;
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Offset.zero & size;
    final sweep = SweepGradient(
      transform: const GradientRotation(math.pi / 2 + math.pi * 0.55),
      colors: [...colors, colors.first],
    ).createShader(rect);
    void ring(double width, double blur, double alpha) => canvas.drawRRect(
      rrect,
      Paint()
        ..shader = sweep
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur)
        ..color = Colors.white.withValues(alpha: alpha),
    );
    // Bright enough to read as light flooding in from the edge, the way the
    // system assistant does it; until 1.92 these were 0.22 and 0.42 and the
    // bloom was a haze most people never noticed.
    ring(72, 42, 0.5);
    ring(30, 20, 0.78);
    ring(10, 6, 0.9);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      math.max(size.width.ceil(), 1),
      math.max(size.height.ceil(), 1),
    );
    picture.dispose();
    _image?.dispose();
    _image = image;
    _size = size;
    _colors = List.of(colors);
    return image;
  }
}

/// A thin line of the same light running round the screen for as long as its
/// child is on screen.
///
/// The hold that opens the assistant ends in a bloom that fades out, and what
/// comes up afterwards looks like any other sheet. A moving border of the
/// same colours is how the app says it is still in that mode — the way a
/// call in progress keeps a bar at the top rather than trusting you to
/// remember. It turns slowly, once every [period], so it reads as light
/// rather than as a frame; and it is a few pixels wide, a fraction of the
/// opening bloom, so it never crowds the content.
///
/// Reduce-motion keeps the line and stops it turning. The line is not motion
/// — it is the only thing saying which mode the app is in.
class NexAmbientEdgeGlow extends StatefulWidget {
  const NexAmbientEdgeGlow({
    super.key,
    required this.child,
    required this.colors,
    this.width = 3,
    this.period = const Duration(seconds: 6),
  });

  final Widget child;
  final List<Color> colors;

  /// The line's width in logical pixels; a soft halo twice as wide sits
  /// under it.
  final double width;

  /// One full turn of the colours round the screen.
  final Duration period;

  /// Whether the border turns. A border that turns for as long as the
  /// assistant is open is an animation that never ends, and widget tests
  /// that wait for the screen to settle would wait forever; the client's
  /// test config sets this false, and must be the only thing that does.
  static bool turns = true;

  @override
  State<NexAmbientEdgeGlow> createState() => _NexAmbientEdgeGlowState();
}

class _NexAmbientEdgeGlowState extends State<NexAmbientEdgeGlow> {
  /// Set when the assistant starts to go — the sheet sliding away, or this
  /// widget leaving the tree — and cleared if a half-dismissed sheet comes
  /// back up.
  final _closing = ValueNotifier<bool>(false);

  OverlayEntry? _glow;
  Animation<double>? _route;
  bool _asked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    // The route's own animation says when the sheet begins to leave, so the
    // border starts its exit with the sheet rather than vanishing after it.
    _route = ModalRoute.of(context)?.animation?..addStatusListener(_onRoute);
    // After the frame, not during it. This runs while the tree is being
    // built, and inserting an overlay entry marks the Overlay itself dirty —
    // which is a "setState called during build" the moment the route this
    // sits in is the thing currently building.
    final still = MediaQuery.disableAnimationsOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      late final OverlayEntry entry;
      entry = OverlayEntry(
        builder: (context) => _AmbientBorder(
          colors: widget.colors,
          width: widget.width,
          period: widget.period,
          still: still,
          closing: _closing,
          // The entry outlives this widget by the length of its exit, and
          // takes itself down once that has played.
          onGone: () {
            if (entry.mounted) entry.remove();
            if (identical(_glow, entry)) _glow = null;
          },
        ),
      );
      Overlay.of(context, rootOverlay: true).insert(entry);
      _glow = entry;
    });
  }

  void _onRoute(AnimationStatus status) {
    _closing.value =
        status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed;
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_onRoute);
    // Not removed here: the border plays its way out on its own, and removes
    // its entry when it is done.
    _closing.value = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The border itself, living in the overlay so it can finish leaving after
/// the assistant has gone.
///
/// Its exit is the opening run backwards. The assistant is summoned by
/// holding the capture button, and its light rises from there; when it
/// closes, the ring of light runs back down both sides of the screen, its two
/// ends meeting at the bottom centre — where the button is — and a last soft
/// pulse there is the light going home.
class _AmbientBorder extends StatefulWidget {
  const _AmbientBorder({
    required this.colors,
    required this.width,
    required this.period,
    required this.still,
    required this.closing,
    required this.onGone,
  });

  final List<Color> colors;
  final double width;
  final Duration period;
  final bool still;
  final ValueListenable<bool> closing;
  final VoidCallback onGone;

  @override
  State<_AmbientBorder> createState() => _AmbientBorderState();
}

class _AmbientBorderState extends State<_AmbientBorder>
    with TickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: widget.period,
  );
  late final AnimationController _exit =
      AnimationController(
        vsync: this,
        duration: Duration(milliseconds: widget.still ? 200 : 720),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onGone();
      });

  @override
  void initState() {
    super.initState();
    if (widget.still) {
      _fade.value = 1;
    } else {
      _fade.forward();
      if (NexAmbientEdgeGlow.turns) _turn.repeat();
    }
    widget.closing.addListener(_onClosing);
    _onClosing();
  }

  void _onClosing() {
    if (widget.closing.value) {
      _exit.forward();
    } else if (_exit.value > 0) {
      _exit.reverse();
    }
  }

  @override
  void dispose() {
    widget.closing.removeListener(_onClosing);
    _fade.dispose();
    _turn.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_fade, _turn, _exit]),
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: _AmbientBorderPainter(
              opacity: _fade.value,
              turn: _turn.value,
              width: widget.width,
              colors: widget.colors,
              exit: widget.still
                  ? 0
                  : Curves.easeInOutCubic.transform(_exit.value),
              fadeOut: widget.still ? _exit.value : 0,
            ),
          ),
        ),
      ),
    ),
  );
}

class _AmbientBorderPainter extends CustomPainter {
  _AmbientBorderPainter({
    required this.opacity,
    required this.turn,
    required this.width,
    required this.colors,
    this.exit = 0,
    this.fadeOut = 0,
  });

  final double opacity;
  final double turn;
  final double width;
  final List<Color> colors;

  /// How far the ring has drawn back into the bottom centre, 0 to 1.
  final double exit;

  /// Reduce-motion's exit: a plain fade, 0 to 1.
  final double fadeOut;

  static const _radius = 44.0;

  /// The screen's edge as one line that starts and ends at the bottom
  /// centre, so drawing back from both ends collapses it onto that point.
  static Path _edge(Rect r) {
    const c = _radius;
    return Path()
      ..moveTo(r.center.dx, r.bottom)
      ..lineTo(r.left + c, r.bottom)
      ..arcToPoint(
        Offset(r.left, r.bottom - c),
        radius: const Radius.circular(c),
      )
      ..lineTo(r.left, r.top + c)
      ..arcToPoint(Offset(r.left + c, r.top), radius: const Radius.circular(c))
      ..lineTo(r.right - c, r.top)
      ..arcToPoint(Offset(r.right, r.top + c), radius: const Radius.circular(c))
      ..lineTo(r.right, r.bottom - c)
      ..arcToPoint(
        Offset(r.right - c, r.bottom),
        radius: const Radius.circular(c),
      )
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = opacity * (1 - fadeOut);
    if (alpha <= 0) return;
    final rect = Offset.zero & size;
    final inner = rect.deflate(width / 2);
    final sweep = SweepGradient(
      transform: GradientRotation(math.pi / 2 + turn * 2 * math.pi),
      colors: [...colors, colors.first],
    ).createShader(rect);

    Path line;
    if (exit <= 0) {
      // The same generous corner as the bloom, for the same reason.
      line = Path()
        ..addRRect(
          RRect.fromRectAndRadius(inner, const Radius.circular(_radius)),
        );
    } else {
      final metric = _edge(inner).computeMetrics().first;
      final half = metric.length / 2 * (1 - exit);
      line = Path()
        ..addPath(metric.extractPath(0, half), Offset.zero)
        ..addPath(
          metric.extractPath(metric.length - half, metric.length),
          Offset.zero,
        );
    }
    // A little brighter as it gathers, the way light concentrates.
    final glow = (0.45 + 0.35 * exit) * alpha;
    canvas
      ..drawPath(
        line,
        Paint()
          ..shader = sweep
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width * (3 + exit)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 2)
          ..color = Colors.white.withValues(alpha: glow),
      )
      ..drawPath(
        line,
        Paint()
          ..shader = sweep
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width
          ..color = Colors.white.withValues(alpha: alpha),
      );
    // The last of it: one soft pulse where the two ends meet, swelling and
    // fading as the line runs out.
    if (exit > 0.7) {
      final t = (exit - 0.7) / 0.3;
      final centre = Offset(rect.center.dx, rect.bottom);
      final radius = 18 + 46 * t;
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              colors[(colors.length ~/ 2).clamp(0, colors.length - 1)]
                  .withValues(alpha: 0.55 * (1 - t) * alpha),
              colors.first.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: centre, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_AmbientBorderPainter old) =>
      old.opacity != opacity ||
      old.turn != turn ||
      old.width != width ||
      old.colors != colors ||
      old.exit != exit ||
      old.fadeOut != fadeOut;
}

/// Drives a [NexEdgeGlow] from a long press, and reports when it completes.
///
/// The glow grows for [holdDuration] while the finger is down. Letting go
/// early runs it back down and nothing fires; holding to the end fires
/// [onTriggered] once. The child keeps its own [onTap] — this only claims the
/// long press.
///
/// Reduce-motion skips the ramp: the press still has to be held, it simply
/// does not paint. `MediaQuery.disableAnimations` already carries the in-app
/// preference (see `app.dart`), so this needs no preference of its own.
class NexLongPressGlow extends StatefulWidget {
  const NexLongPressGlow({
    super.key,
    required this.child,
    required this.onTriggered,
    required this.colors,
    this.holdDuration = const Duration(milliseconds: 420),
    this.startDelay = Duration.zero,
    this.onHoldStart,
  });

  final Widget child;
  final VoidCallback onTriggered;

  /// Fired after [startDelay], before the ramp — for the small
  /// haptic that tells someone the hold is being counted.
  final VoidCallback? onHoldStart;

  final List<Color> colors;
  final Duration holdDuration;

  /// Wait silently before painting or giving feedback, leaving time for a
  /// tap to become a swipe. Movement or release cancels the pending start.
  final Duration startDelay;

  @override
  State<NexLongPressGlow> createState() => NexLongPressGlowState();
}

class NexLongPressGlowState extends State<NexLongPressGlow>
    with SingleTickerProviderStateMixin {
  /// Created in initState, not lazily — the same trap [NexSkeleton] documents.
  /// A `late final` controller is only built on first touch, so a button that
  /// is mounted and disposed without ever being pressed constructs its ticker
  /// *inside* dispose, against an element that has already been deactivated.
  late final AnimationController _hold;

  OverlayEntry? _glow;
  Timer? _pendingStart;
  int? _pointer;

  /// Set once a hold has completed, cleared when the next one starts. Lifting
  /// the finger after the trigger has already fired must not turn the gentle
  /// hand-off fade into the fast abandon-the-press one.
  bool _handedOff = false;

  @override
  void initState() {
    super.initState();
    _hold = AnimationController(
      vsync: this,
      duration: widget.holdDuration,
      // Faster on the way out: an abandoned press should feel dropped, not
      // slowly reconsidered.
      reverseDuration: const Duration(milliseconds: 160),
    )..addStatusListener(_onStatus);
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _handedOff = true;
    widget.onTriggered();
    // Faded out rather than cut. The sheet the trigger opens takes a moment
    // to rise, and removing the light on the same frame left a visible blink
    // between the two — the glow gone, the sheet not yet there. Slower than
    // the abandon-the-press reverse for the same reason: this one is a
    // hand-off, not a cancellation.
    unawaited(
      _hold
          .animateBack(
            0,
            duration: const Duration(milliseconds: 340),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(_remove),
    );
  }

  void _start() {
    if (!mounted) return;
    _handedOff = false;
    widget.onHoldStart?.call();
    if (MediaQuery.disableAnimationsOf(context)) {
      // No paint, but the hold still has to be a hold — firing instantly
      // would turn every tap-and-linger into an accidental trigger.
      _hold.value = 0;
      _hold.duration = widget.holdDuration;
      _hold.forward();
      return;
    }
    _show();
    _hold.forward();
  }

  void _cancel() {
    _pendingStart?.cancel();
    _pendingStart = null;
    // A pointer route can still deliver its up/cancel after this button
    // left the tree (for example when the target opens on release).
    if (!mounted) return;
    if (_handedOff) return;
    _hold.reverse().whenComplete(() {
      if (_hold.value == 0) _remove();
    });
  }

  /// An overlay, not a widget in this subtree: the glow belongs to the whole
  /// screen, and anything painted inside the button's own tree would be
  /// clipped to the button.
  void _show() {
    if (_glow != null) return;
    final entry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: AnimatedBuilder(
          animation: _hold,
          builder: (context, _) =>
              NexEdgeGlow(progress: _hold.value, colors: widget.colors),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
    _glow = entry;
  }

  void _remove() {
    _glow?.remove();
    _glow = null;
  }

  @override
  void dispose() {
    _pendingStart?.cancel();
    // Before the controller: the overlay's builder reads it every frame.
    _remove();
    _hold
      ..removeStatusListener(_onStatus)
      ..dispose();
    super.dispose();
  }

  /// Where the finger went down, while it is still a hold.
  Offset? _down;

  @override
  Widget build(BuildContext context) => Listener(
    // Listener rather than GestureDetector.onLongPress: that only reports
    // once the press has already succeeded, which is too late to have been
    // animating during it — and the animation *is* the feature.
    onPointerDown: (event) {
      if (_pointer != null) return;
      _pointer = event.pointer;
      _down = event.position;
      if (widget.startDelay == Duration.zero) {
        _start();
      } else {
        _pendingStart = Timer(widget.startDelay, () {
          _pendingStart = null;
          if (mounted && _down != null) _start();
        });
      }
    },
    // A finger that travels is not holding: it is flicking or scrolling
    // whatever it pressed on, and the hold gives way rather than firing
    // under it.
    onPointerMove: (event) {
      if (event.pointer != _pointer) return;
      final down = _down;
      if (down == null || (event.position - down).distance <= kTouchSlop) {
        return;
      }
      _down = null;
      _cancel();
    },
    onPointerUp: (event) {
      if (event.pointer != _pointer) return;
      _pointer = null;
      _down = null;
      _cancel();
    },
    onPointerCancel: (event) {
      if (event.pointer != _pointer) return;
      _pointer = null;
      _down = null;
      _cancel();
    },
    child: widget.child,
  );
}
