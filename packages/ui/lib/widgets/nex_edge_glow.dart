import 'dart:async';
import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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

class _NexAmbientEdgeGlowState extends State<NexAmbientEdgeGlow>
    with TickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  OverlayEntry? _glow;
  bool _asked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    // After the frame, not during it. This runs while the tree is being
    // built, and inserting an overlay entry marks the Overlay itself dirty —
    // which is a "setState called during build" the moment the route this
    // sits in is the thing currently building.
    final still = MediaQuery.disableAnimationsOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final entry = OverlayEntry(
        builder: (context) => Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: Listenable.merge([_fade, _turn]),
                builder: (context, _) => CustomPaint(
                  size: Size.infinite,
                  painter: _AmbientBorderPainter(
                    opacity: _fade.value,
                    turn: _turn.value,
                    width: widget.width,
                    colors: widget.colors,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      Overlay.of(context, rootOverlay: true).insert(entry);
      _glow = entry;
      if (still) {
        _fade.value = 1;
      } else {
        _fade.forward();
        if (NexAmbientEdgeGlow.turns) _turn.repeat();
      }
    });
  }

  @override
  void dispose() {
    // Before the controllers, for the reason [NexLongPressGlowState]
    // documents: the overlay's builder reads them every frame.
    _glow?.remove();
    _glow = null;
    _fade.dispose();
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AmbientBorderPainter extends CustomPainter {
  _AmbientBorderPainter({
    required this.opacity,
    required this.turn,
    required this.width,
    required this.colors,
  });

  final double opacity;
  final double turn;
  final double width;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final rect = Offset.zero & size;
    // The same generous corner as the bloom, for the same reason.
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(width / 2),
      const Radius.circular(44),
    );
    final sweep = SweepGradient(
      transform: GradientRotation(math.pi / 2 + turn * 2 * math.pi),
      colors: [...colors, colors.first],
    ).createShader(rect);
    canvas
      ..drawRRect(
        rrect,
        Paint()
          ..shader = sweep
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 3
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 2)
          ..color = Colors.white.withValues(alpha: 0.45 * opacity),
      )
      ..drawRRect(
        rrect,
        Paint()
          ..shader = sweep
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = Colors.white.withValues(alpha: opacity),
      );
  }

  @override
  bool shouldRepaint(_AmbientBorderPainter old) =>
      old.opacity != opacity ||
      old.turn != turn ||
      old.width != width ||
      old.colors != colors;
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
    this.onHoldStart,
  });

  final Widget child;
  final VoidCallback onTriggered;

  /// Fired the moment the finger goes down, before the ramp — for the small
  /// haptic that tells someone the hold is being counted.
  final VoidCallback? onHoldStart;

  final List<Color> colors;
  final Duration holdDuration;

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
    // Before the controller: the overlay's builder reads it every frame.
    _remove();
    _hold
      ..removeStatusListener(_onStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    // Listener rather than GestureDetector.onLongPress: that only reports
    // once the press has already succeeded, which is too late to have been
    // animating during it — and the animation *is* the feature.
    onPointerDown: (_) => _start(),
    onPointerUp: (_) => _cancel(),
    onPointerCancel: (_) => _cancel(),
    child: widget.child,
  );
}
