import 'dart:math' as math;

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
    // Eased so the last third of the hold is where most of the brightness
    // arrives — a linear ramp reads as "loading", this reads as "waking up".
    final t = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));

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
      // Starts at the bottom, under the capture button the press began on.
      transform: const GradientRotation(math.pi / 2),
      colors: [...colors, colors.first],
    ).createShader(rect);

    // Two passes: a wide soft bloom that reads as light spilling inward, and
    // a tighter bright line that gives it an edge to belong to. One pass on
    // its own is either a smudge or a hairline.
    canvas
      ..drawRRect(
        rrect,
        Paint()
          ..shader = sweep
          ..style = PaintingStyle.stroke
          ..strokeWidth = 26 * t
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 18 * t)
          ..color = Colors.white.withValues(alpha: 0.55 * t),
      )
      ..drawRRect(
        rrect,
        Paint()
          ..shader = sweep
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5 * t
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 * t)
          ..color = Colors.white.withValues(alpha: 0.9 * t),
      );
  }

  @override
  bool shouldRepaint(_EdgeGlowPainter old) =>
      old.progress != progress || old.colors != colors;
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
    _remove();
    widget.onTriggered();
  }

  void _start() {
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
